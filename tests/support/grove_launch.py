from __future__ import annotations

import json
from collections.abc import Mapping
from pathlib import Path, PurePath

from libtmux.server import Server

from .grove import GroveDriver
from .helix import TEST_THEME, HelixDriver, HelixSandbox
from .workspace import WorkspaceFixture

_SETTING_VALUES = {
    "enabled": "#t",
    "disabled": "#f",
    "left": "'left",
    "right": "'right",
    "always": "'always",
    "focused": "'focused",
    "middle": "'middle",
    "wide text": json.dumps("wide"),
    "non-boolean": "'enabled",
}


def start_grove(
    sandbox: HelixSandbox,
    repository: Path,
    server: Server,
    workspace: WorkspaceFixture,
    *,
    active_file: Path | None = None,
    settings: Mapping[str, str] | None = None,
    theme: str | None = None,
    init: str = "",
) -> GroveDriver:
    helix = start_grove_helix(
        sandbox,
        repository,
        server,
        workspace,
        active_file=active_file,
        settings=settings,
        theme=theme,
        init=init,
    )
    try:
        grove = GroveDriver(helix, workspace)
        if (settings or {}).get("visibility", "always") == "always":
            grove.wait_for_row(PurePath(), timeout=30)
        # Focusing before Helix opens the Active file starts the Cursor on the
        # Workspace root instead. A file outside it lands there either way.
        if active_file is not None and active_file.is_relative_to(workspace.root):
            grove.wait_for_active_document(active_file.name)
        return grove
    except Exception:
        helix.close()
        raise


def start_grove_helix(
    sandbox: HelixSandbox,
    repository: Path,
    server: Server,
    workspace: WorkspaceFixture,
    *,
    active_file: Path | None = None,
    settings: Mapping[str, str] | None = None,
    starts: int = 1,
    theme: str | None = None,
    init: str = "",
) -> HelixDriver:
    arguments = " ".join(
        f"#:{name} {_SETTING_VALUES.get(value, value)}"
        for name, value in (settings or {}).items()
    )
    call = f"(grove-start! {arguments})" if arguments else "(grove-start!)"
    startup = "\n".join(call for _ in range(starts))
    return sandbox.start(
        server,
        cwd=workspace.root,
        documents=(active_file,) if active_file is not None else (),
        init=_grove_init(repository, startup, init),
        theme=theme or TEST_THEME,
    )


def _grove_init(repository: Path, startup: str, init: str) -> str:
    return (
        f'(require "{repository / "grove.scm"}")\n'
        "(define (grove-test-key-received)\n"
        ' (set-status! "Grove test key reached Helix"))\n'
        f"{startup}\n"
        "(keymap (global)\n"
        ' (normal (space (e ":grove-focus!")\n'
        '                (E ":grove-visibility-toggle!"))\n'
        "  (C-n grove-test-key-received) (C-r grove-test-key-received)\n"
        "  (C-d grove-test-key-received) (C-j grove-test-key-received)\n"
        "  (C-y grove-test-key-received)))\n"
        f"{init}\n"
    )
