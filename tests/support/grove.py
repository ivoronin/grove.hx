from __future__ import annotations

import json
import unicodedata
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import PurePath

from rich.console import Console
from rich.style import Style
from rich.text import Text

from .helix import HelixDriver, HelixFrame
from .tui import PointerContact
from .workspace import WorkspaceFixture

_Rgb = tuple[int, int, int]
_CONSOLE = Console(color_system="truecolor")
_RAIL_GLYPHS = frozenset("▕▐▏▌")
_LEFT_RAIL_GLYPHS = frozenset("▕▐")
_RIGHT_RAIL_GLYPHS = frozenset("▏▌")


class _IncompleteGroveFrame(Exception):
    pass


@dataclass(frozen=True)
class VisibleRow:
    path: PurePath
    number: int
    label: str
    text: str
    styled: Text

    @property
    def label_column(self) -> int:
        column = _label_start(self.text, self.label)
        if column is None:
            raise AssertionError(f'Visible row has no label "{self.label}"')
        return column

    @property
    def disclosure(self) -> str | None:
        return next((glyph for glyph in "▸▾" if glyph in self.text), None)

    @property
    def has_unsaved_mark(self) -> bool:
        return self.text.endswith((" +", "…+"))

    @property
    def has_active_mark(self) -> bool:
        return "*" in self.text[: self.label_column]

    def style_at(self, marker: str) -> Style:
        offset = self.label_column if marker == self.label else self.text.find(marker)
        if offset < 0:
            raise AssertionError(f'Visible row has no marker "{marker}"')
        return self.styled.get_style_at_offset(_CONSOLE, offset)

    def foreground_at(self, marker: str) -> _Rgb | None:
        if marker != self.label and marker not in self.text:
            return None
        return _rgb(self.style_at(marker).color)

    def background_at(self, marker: str) -> _Rgb | None:
        if marker != self.label and marker not in self.text:
            return None
        return _rgb(self.style_at(marker).bgcolor)

    def is_dimmed_at(self, marker: str) -> bool:
        return self.style_at(marker).dim


@dataclass(frozen=True)
class Rail:
    column: int
    track_rows: tuple[int, ...]
    thumb_rows: tuple[int, ...]

    @property
    def thumb(self) -> tuple[int, int] | None:
        return (self.column, self.thumb_rows[0]) if self.thumb_rows else None

    def track(self, direction: str) -> tuple[int, int] | None:
        if direction not in {"above", "below"}:
            raise ValueError(f"Unknown Rail direction: {direction!r}")
        if not self.thumb_rows:
            return None
        if direction == "above":
            row = max(
                (row for row in self.track_rows if row < min(self.thumb_rows)),
                default=None,
            )
        else:
            row = min(
                (row for row in self.track_rows if row > max(self.thumb_rows)),
                default=None,
            )
        return (self.column, row) if row is not None else None


@dataclass(frozen=True)
class Pane:
    side: str
    width: int
    lines: tuple[str, ...]
    rows: tuple[VisibleRow, ...]
    workspace_root: VisibleRow | None
    cursor: VisibleRow | None
    rail: Rail

    @property
    def active_file(self) -> VisibleRow | None:
        return next(
            (row for row in self.rows if row.has_active_mark),
            None,
        )

    @property
    def blank_row(self) -> int | None:
        return next(
            (
                number
                for number, line in enumerate(self.lines, start=1)
                if not line.strip()
            ),
            None,
        )

    def row_text(self, number: int) -> str:
        return self.lines[number - 1].rstrip()


@dataclass(frozen=True)
class GroveFrame:
    helix: HelixFrame
    pane: Pane | None

    @classmethod
    def decode(cls, helix: HelixFrame, workspace: WorkspaceFixture) -> GroveFrame:
        try:
            return cls._decode(helix, workspace)
        except _IncompleteGroveFrame as error:
            raise AssertionError("Incomplete Grove frame") from error

    @classmethod
    def _decode(cls, helix: HelixFrame, workspace: WorkspaceFixture) -> GroveFrame:
        lines = helix.terminal.lines
        rail_column, grove_before = _layout(lines)
        if rail_column is None:
            return cls(helix, None)
        grove_lines = tuple(
            line[:rail_column] if grove_before else line[rail_column + 1 :]
            for line in lines
        )
        styled_lines = tuple(
            _styled_slice(line, rail_column, grove_before)
            for line in helix.terminal.styled_lines
        )
        root = _workspace_root(grove_lines, styled_lines, workspace)
        rows = _visible_rows(grove_lines, styled_lines, workspace)
        all_rows = ((root,) if root is not None else ()) + rows
        cursors = tuple(row for row in all_rows if row.text.startswith(">"))
        if len(cursors) > 1:
            raise AssertionError("Grove rendered multiple Cursor marks")
        if sum(row.has_active_mark for row in all_rows) > 1:
            raise AssertionError("Grove rendered multiple Active file marks")
        thumb_rows = tuple(
            number
            for number, line in enumerate(lines, start=1)
            if len(line) > rail_column and line[rail_column] in "▐▌"
        )
        track_rows = tuple(
            number
            for number, line in enumerate(lines, start=1)
            if len(line) > rail_column and line[rail_column] in "▕▏"
        )
        rail = Rail(rail_column + 1, track_rows, thumb_rows)
        side = "left" if grove_before else "right"
        width = rail.column if grove_before else helix.terminal.width - rail_column
        pane = Pane(
            side,
            width,
            grove_lines,
            all_rows,
            root,
            cursors[0] if cursors else None,
            rail,
        )
        return cls(helix, pane)

    def row(self, path: PurePath) -> VisibleRow | None:
        if self.pane is None:
            return None
        matches = [row for row in self.pane.rows if row.path == path]
        if len(matches) > 1:
            raise AssertionError(f"Grove rendered duplicate row identity: {path}")
        return matches[0] if matches else None


_GroveCheck = Callable[[GroveFrame], str | None]


@dataclass
class GroveDriver:
    helix: HelixDriver
    workspace: WorkspaceFixture

    def close(self) -> None:
        self.helix.close()

    def capture(self) -> GroveFrame:
        return GroveFrame.decode(self.helix.capture(), self.workspace)

    def wait(self, check: _GroveCheck, *, timeout: float = 10) -> GroveFrame:
        def helix_check(frame: HelixFrame) -> str | None:
            try:
                grove = GroveFrame._decode(frame, self.workspace)
            except _IncompleteGroveFrame:
                return "Grove frame is incomplete"
            return check(grove)

        return GroveFrame._decode(
            self.helix.wait(helix_check, timeout=timeout),
            self.workspace,
        )

    def hold(self, check: _GroveCheck, *, duration: float = 0.25) -> GroveFrame:
        result: GroveFrame | None = None

        def helix_check(frame: HelixFrame) -> str | None:
            nonlocal result
            try:
                result = GroveFrame._decode(frame, self.workspace)
            except _IncompleteGroveFrame:
                return None
            return check(result)

        self.helix.hold(helix_check, duration=duration)
        if result is None:
            raise AssertionError("No complete Grove frame observed")
        return result

    def wait_for_active_document(self, fragment: str) -> None:
        self.wait(
            lambda frame: (
                None
                if fragment in (frame.helix.document or "")
                else f'Helix did not make "{fragment}" Active'
            )
        )

    def wait_for_row(self, path: PurePath, *, timeout: float = 10) -> VisibleRow:
        frame = self.wait(
            lambda current: (
                None
                if current.row(path) is not None
                else f'Grove did not show "{path}"'
            ),
            timeout=timeout,
        )
        row = frame.row(path)
        assert row is not None
        return row

    def focus(self) -> None:
        self.helix.terminal.key("Space")
        self.helix.terminal.write("e")
        # Focus starts the Cursor on the Active file when Grove can see one,
        # so waiting for any Cursor accepts a frame observed too early.
        self.wait(
            lambda frame: (
                None
                if frame.pane is not None
                and frame.pane.cursor is not None
                and frame.pane.active_file in (None, frame.pane.cursor)
                else "Grove did not render focus on the Active file"
            )
        )

    def toggle_visibility(self) -> None:
        self.helix.terminal.key("Space")
        self.helix.terminal.write("E")

    def key(self, name: str) -> None:
        self.helix.terminal.key(name)

    def press_row(self, path: PurePath) -> PointerContact:
        row = self.wait_for_row(path)
        return self.helix.terminal.press(row.number, self._pane_column())

    def click_editor(self) -> None:
        terminal = self.helix.terminal.capture()
        self.helix.terminal.click(1, min(50, terminal.width - 2))

    def click_blank_pane(self) -> None:
        frame = self.wait(
            lambda current: (
                None
                if current.pane is not None and current.pane.blank_row is not None
                else "Grove has no blank Pane row"
            )
        )
        assert frame.pane is not None and frame.pane.blank_row is not None
        self.helix.terminal.click(frame.pane.blank_row, self._pane_column(frame))

    def wheel(
        self,
        direction: str,
        *,
        over: PurePath | None = None,
    ) -> None:
        frame = self.capture()
        target_row = (
            self.wait_for_row(over).number
            if over is not None
            else min(5, frame.helix.terminal.height)
        )
        self.helix.terminal.wheel(
            direction,
            target_row,
            self._pane_column(frame),
        )

    def click_rail_track(self, direction: str) -> None:
        frame = self.capture()
        if frame.pane is None:
            raise AssertionError("Grove has no Pane")
        position = frame.pane.rail.track(direction)
        if position is None:
            raise AssertionError(f"Rail has no track {direction} the thumb")
        column, row = position
        self.helix.terminal.click(row, column)

    def drag_rail_to_width(self, width: int) -> None:
        frame = self.capture()
        if frame.pane is None:
            raise AssertionError("Grove has no Pane")
        direction = 1 if frame.pane.side == "left" else -1
        destination = frame.pane.rail.column + direction * (width - frame.pane.width)
        terminal_width = frame.helix.terminal.width
        destination = max(2, min(terminal_width - 1, destination))
        self.helix.terminal.press(2, frame.pane.rail.column).drag_to(
            row=2,
            column=destination,
        )

    def change_workspace(self, workspace: WorkspaceFixture) -> None:
        self.helix.command(f"cd {json.dumps(str(workspace.root))}")
        self.workspace = workspace

    def push_workspace(self, workspace: WorkspaceFixture) -> None:
        self.helix.command(f"pushd {json.dumps(str(workspace.root))}")
        self.workspace = workspace

    def pop_workspace(self, workspace: WorkspaceFixture) -> None:
        self.helix.command("popd")
        self.workspace = workspace

    def _pane_column(self, frame: GroveFrame | None = None) -> int:
        frame = frame or self.capture()
        if frame.pane is None:
            raise AssertionError("Grove has no Pane")
        return 5 if frame.pane.side == "left" else frame.helix.terminal.width - 5


def _layout(lines: tuple[str, ...]) -> tuple[int | None, bool]:
    layout_lines = lines
    positions = [
        {index for index, character in enumerate(line) if character in _RAIL_GLYPHS}
        for line in lines
    ]
    if not positions or all(not row for row in positions):
        return None, True
    if any(not row for row in positions):
        missing = {index for index, row in enumerate(positions) if not row}
        if missing == {len(positions) - 1}:
            positions = [row for row in positions if row]
            layout_lines = lines[:-1]
        else:
            counts = {
                column: sum(column in row for row in positions)
                for column in set().union(*positions)
            }
            if counts and max(counts.values()) >= max(2, len(lines) - 1):
                raise _IncompleteGroveFrame
            return None, True
    layouts = []
    for column in set.intersection(*positions):
        glyphs = {line[column] for line in layout_lines}
        if glyphs <= _LEFT_RAIL_GLYPHS:
            layouts.append((column, True))
        elif glyphs <= _RIGHT_RAIL_GLYPHS:
            layouts.append((column, False))
    if len(layouts) != 1:
        raise AssertionError("Grove frame has no unique Rail")
    return layouts[0]


def _workspace_root(
    lines: tuple[str, ...],
    styled: tuple[Text, ...],
    workspace: WorkspaceFixture,
) -> VisibleRow | None:
    if not lines:
        return None
    text = lines[0].rstrip()
    label = workspace.root.name
    if _label_start(text, label) is None:
        return None
    return VisibleRow(PurePath(), 1, label, text, styled[0])


def _visible_rows(
    lines: tuple[str, ...],
    styled: tuple[Text, ...],
    workspace: WorkspaceFixture,
) -> tuple[VisibleRow, ...]:
    labels = {_display_label(path.name) for path in workspace.paths}
    rows: list[VisibleRow] = []
    parents: list[tuple[int, PurePath]] = []
    for number, raw in enumerate(lines, start=1):
        text = raw.rstrip()
        match = _matched_label(text, labels)
        if match is None:
            continue
        label, column = match
        while parents and parents[-1][0] >= column:
            parents.pop()
        parent = parents[-1][1] if parents else PurePath()
        candidates = [
            path
            for path in workspace.paths
            if path.parent
            in {parent, PurePath(".") if parent == PurePath() else parent}
            and _display_label(path.name) == label
        ]
        if not candidates and not rows:
            candidates = [
                path for path in workspace.paths if _display_label(path.name) == label
            ]
        if len(candidates) != 1:
            raise AssertionError(
                f"Grove row has ambiguous filesystem identity: {text!r}"
            )
        path = candidates[0]
        rows.append(VisibleRow(path, number, label, text, styled[number - 1]))
        if path in workspace.directories:
            parents.append((column, path))
    return tuple(rows)


def _styled_slice(line: str, rail: int, grove_before: bool) -> Text:
    styled = Text.from_ansi(line)
    return styled[:rail] if grove_before else styled[rail + 1 :]


def _matched_label(row: str, names: set[str]) -> tuple[str, int] | None:
    matches = [
        (name, column)
        for name in names
        if (column := _label_start(row, name)) is not None
    ]
    if len(matches) > 1:
        raise AssertionError(f"Grove row has ambiguous identity: {row!r}")
    return matches[0] if matches else None


def _label_start(row: str, label: str) -> int | None:
    texts = [
        row.rstrip(),
        row.removesuffix("+").rstrip(),
    ]
    for text in texts:
        if _has_label(text, label):
            return len(text) - len(label)
    for length in range(len(label) - 1, 0, -1):
        clipped = f"{label[:length]}…"
        for text in texts:
            if _has_label(text, clipped):
                return len(text) - len(clipped)
    return None


def _has_label(text: str, label: str) -> bool:
    if not text.endswith(label):
        return False
    start = len(text) - len(label)
    if (
        start
        and not text[start - 1].isspace()
        and not (start == 1 and text.startswith(">"))
    ):
        return False
    return all(
        character.isspace()
        or character in ">*▸▾│·"
        or unicodedata.category(character) in {"Co", "So"}
        for character in text[:start]
    )


def _display_label(label: str) -> str:
    return "".join(
        "?" if unicodedata.category(character) == "Cc" else character
        for character in label
    )


def _rgb(color) -> _Rgb | None:
    if color is None:
        return None
    triplet = color.get_truecolor()
    return triplet.red, triplet.green, triplet.blue
