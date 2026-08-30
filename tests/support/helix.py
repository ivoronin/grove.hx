from __future__ import annotations

import json
import os
import re
import shutil
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from libtmux.server import Server

from .tui import TerminalFrame, TuiDriver

_MODES = {"GNR": "Normal", "GIN": "Insert", "GSE": "Select"}

TEST_THEME = """\
inherits = "base16_default_dark"
"ui.text.focus" = { bg = "#303030" }
"ui.virtual.indent-guide" = { fg = "#888888" }
"ui.virtual.ruler" = { bg = "#202020" }
"error" = { fg = "#ff00ff" }
"diff.minus" = { fg = "#ff0000" }
"diff.delta" = { fg = "#ffff00" }
"diff.plus" = { fg = "#00ff00" }
"info" = { fg = "#00ffff" }
"grove.test.cursor" = { bg = "#112233" }
"grove.test.modified" = { fg = "#456789" }
"grove.test.empty" = {}
"""
ALT_TEST_THEME = TEST_THEME.replace(
    '"grove.test.cursor" = { bg = "#112233" }',
    '"grove.test.cursor" = { bg = "#334455" }',
)


@dataclass(frozen=True)
class EditorView:
    document: str
    mode: str | None
    cursor: tuple[int, int] | None
    column_bounds: tuple[int, int]
    lines: tuple[str, ...]
    status_row: int

    @property
    def first_visible_line(self) -> str | None:
        return self.lines[0] if self.lines else None


@dataclass(frozen=True)
class _StatusSegment:
    row: int
    start: int
    end: int
    text: str


@dataclass(frozen=True)
class HelixFrame:
    terminal: TerminalFrame
    views: tuple[EditorView, ...]
    bottom_line: str

    @classmethod
    def decode(cls, terminal: TerminalFrame) -> HelixFrame:
        segments = tuple(_status_segments(terminal.lines, terminal.width))
        views = tuple(
            _view(
                segment,
                terminal.lines[_content_start(segment, segments) : segment.row],
            )
            for segment in segments
        )
        active = [view for view in views if view.mode is not None]
        if len(active) > 1:
            raise AssertionError("Helix rendered multiple active Editor views")
        return cls(terminal, views, terminal.lines[-1] if terminal.lines else "")

    @property
    def active_view(self) -> EditorView | None:
        return next((view for view in self.views if view.mode is not None), None)

    @property
    def mode(self) -> str | None:
        return self.active_view.mode if self.active_view else None

    @property
    def document(self) -> str | None:
        return self.active_view.document if self.active_view else None

    def view(self, document: str) -> EditorView | None:
        matches = [view for view in self.views if view.document == document]
        if len(matches) > 1:
            raise AssertionError(
                f'Helix rendered multiple views for document "{document}"'
            )
        return matches[0] if matches else None

    def contains(self, text: str) -> bool:
        return any(text in line for view in self.views for line in view.lines)


_HelixCheck = Callable[[HelixFrame], str | None]


@dataclass
class HelixDriver:
    terminal: TuiDriver

    def close(self) -> None:
        self.terminal.close()

    def wait_for_exit(self, timeout: float = 10) -> int:
        return self.terminal.wait_for_exit(timeout)

    def capture(self) -> HelixFrame:
        return HelixFrame.decode(self.terminal.capture())

    def wait(self, check: _HelixCheck, *, timeout: float = 10) -> HelixFrame:
        def terminal_check(terminal: TerminalFrame) -> str | None:
            return check(HelixFrame.decode(terminal))

        return HelixFrame.decode(self.terminal.wait(terminal_check, timeout=timeout))

    def hold(self, check: _HelixCheck, *, duration: float = 0.25) -> HelixFrame:
        def terminal_check(terminal: TerminalFrame) -> str | None:
            return check(HelixFrame.decode(terminal))

        return HelixFrame.decode(self.terminal.hold(terminal_check, duration=duration))

    def command(self, text: str) -> HelixFrame:
        if not text or text.startswith(":") or "\n" in text:
            raise ValueError(f"Invalid Helix command: {text!r}")
        self.wait(
            lambda frame: None if frame.mode == "Normal" else "Helix is not Normal"
        )
        self.terminal.write(":")
        self.terminal.wait(
            lambda frame: (
                None
                if frame.lines and frame.lines[-1].startswith(":")
                else "Helix did not open the command line"
            )
        )
        self.terminal.paste(text)
        self.terminal.key("Enter")
        return self.wait(
            lambda frame: (
                None
                if not frame.bottom_line.startswith(":")
                else "Helix did not finish command entry"
            )
        )

    def quit(self) -> None:
        self.wait(
            lambda frame: None if frame.mode == "Normal" else "Helix is not Normal"
        )
        self.terminal.write(":quit!")
        self.terminal.key("Enter")


@dataclass(frozen=True)
class HelixSandbox:
    root: Path

    def start(
        self,
        server: Server,
        *,
        cwd: Path,
        documents: tuple[Path, ...] = (),
        init: str = "",
        theme: str = TEST_THEME,
    ) -> HelixDriver:
        self.root.mkdir(parents=True, exist_ok=True)
        config_home, steel_home = self._prepare_homes(init, theme)
        driver = HelixDriver(
            TuiDriver.start(
                server,
                [
                    "hx",
                    "--working-dir",
                    str(cwd),
                    *(str(document) for document in documents),
                ],
                cwd=cwd,
                env={
                    "XDG_CONFIG_HOME": str(config_home),
                    "STEEL_HOME": str(steel_home),
                },
            )
        )
        try:
            driver.wait(
                lambda frame: None if frame.mode == "Normal" else "Helix did not start"
            )
        except Exception:
            driver.close()
            raise
        return driver

    @property
    def closed_documents(self) -> tuple[str, ...]:
        log = self.root / "closed-documents"
        return (
            tuple(log.read_text(encoding="utf-8").splitlines()) if log.exists() else ()
        )

    def _prepare_homes(
        self,
        init: str,
        theme: str,
    ) -> tuple[Path, Path]:
        config_home = self.root / "xdg"
        helix_config = config_home / "helix"
        steel_home = self.root / "steel"
        (helix_config / "themes").mkdir(parents=True)
        shutil.copytree(
            _installed_steel_home() / "cogs" / "devicons",
            steel_home / "cogs" / "devicons",
        )
        (helix_config / "themes" / "grove_test.toml").write_text(
            theme, encoding="utf-8"
        )
        (helix_config / "themes" / "grove_test_alt.toml").write_text(
            ALT_TEST_THEME, encoding="utf-8"
        )
        (helix_config / "config.toml").write_text(
            'theme = "grove_test"\n'
            "[editor]\n"
            "mouse = true\n"
            "[editor.statusline]\n"
            'left = ["file-name", "separator", "selections"]\n'
            "center = []\n"
            'right = ["mode", "separator", "position"]\n'
            'separator = "¦"\n'
            'mode.normal = "GNR"\n'
            'mode.insert = "GIN"\n'
            'mode.select = "GSE"\n',
            encoding="utf-8",
        )
        (helix_config / "init.scm").write_text(
            '(require "helix/components.scm")\n'
            '(require "helix/keymaps.scm")\n'
            '(require "helix/misc.scm")\n'
            f"{_document_close_hook(self.root / 'closed-documents')}\n"
            f"{init}\n",
            encoding="utf-8",
        )
        return config_home, steel_home


def _view(segment: _StatusSegment, lines: Sequence[str]) -> EditorView:
    document, separator, _rest = segment.text.partition("¦")
    if not separator or not document.strip():
        raise AssertionError(f"Malformed test statusline: {segment.text!r}")
    modes = [
        name for token, name in _MODES.items() if _status_token(segment.text, token)
    ]
    if len(modes) > 1:
        raise AssertionError(f"Ambiguous Helix mode: {segment.text!r}")
    cursor = re.search(r"(\d+):(\d+)\s*$", segment.text)
    return EditorView(
        document.strip(),
        modes[0] if modes else None,
        (int(cursor.group(1)), int(cursor.group(2))) if cursor else None,
        (segment.start, segment.end),
        tuple(line[segment.start : segment.end].rstrip() for line in lines),
        segment.row,
    )


def _status_segments(lines: tuple[str, ...], terminal_width: int):
    for row, line in enumerate(lines):
        for match in re.finditer(r"[^│▕▐▏▌]+", line):
            status = match.group().strip()
            if _is_status(status):
                start, end = match.span()
                # tmux omits Helix's trailing blank status cell.
                if end == len(line) and end < terminal_width:
                    end += 1
                yield _StatusSegment(row, start, end, status)


def _is_status(line: str) -> bool:
    document, separator, rest = line.partition("¦")
    if not separator:
        return False
    has_selection = re.match(r"\d+\s+sel(?:\s|$)", rest.strip()) is not None
    has_coordinates = re.search(r"\d+:\d+\s*$", line) is not None
    has_mode = any(_status_token(line, mode) for mode in _MODES)
    return bool(document.strip()) and has_coordinates and (has_selection or has_mode)


def _status_token(text: str, token: str) -> bool:
    return re.search(rf"(?:^|\s|¦){token}(?=\s|¦|$)", text) is not None


def _content_start(
    segment: _StatusSegment,
    segments: tuple[_StatusSegment, ...],
) -> int:
    previous = [
        candidate.row
        for candidate in segments
        if candidate.row < segment.row and candidate.start == segment.start
    ]
    return max(previous, default=-1) + 1


def _document_close_hook(destination: Path) -> str:
    path = json.dumps(str(destination))
    return (
        '(require "helix/editor.scm")\n'
        "(register-hook\n"
        " 'document-closed\n"
        " (lambda (event)\n"
        f"  (call-with-output-file {path}\n"
        "   (lambda (port)\n"
        "    (display (doc-closed-path event) port)\n"
        "    (newline port))\n"
        "   #:exists 'append)))"
    )


def _installed_steel_home() -> Path:
    if configured := os.environ.get("STEEL_HOME"):
        return Path(configured).expanduser()
    data_home = os.environ.get("XDG_DATA_HOME")
    return (
        Path(data_home).expanduser() if data_home else Path.home() / ".local/share"
    ) / "steel"
