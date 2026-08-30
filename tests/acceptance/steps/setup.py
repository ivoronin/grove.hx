import json
from contextlib import ExitStack
from pathlib import Path

import pytest
from libtmux.server import Server
from pytest_bdd import given, parsers, then, when

from tests.support.git import GitFixture, GitStatusSpec
from tests.support.grove import GroveDriver
from tests.support.grove_launch import start_grove, start_grove_helix
from tests.support.helix import TEST_THEME, HelixDriver, HelixSandbox
from tests.support.workspace import EntrySpec, WorkspaceFixture

REPOSITORY = Path(__file__).parents[3]


@pytest.fixture
def grove_settings() -> dict[str, str]:
    return {}


@pytest.fixture
def helix_theme() -> str:
    return TEST_THEME


@pytest.fixture
def grove_start_count() -> int:
    return 1


@pytest.fixture
def grove_init() -> str:
    return ""


@given("Grove settings", target_fixture="grove_settings")
def configured_grove(datatable: list[list[str]]) -> dict[str, str]:
    return dict(datatable[1:])


@given("Grove starts twice", target_fixture="grove_start_count")
def start_twice() -> int:
    return 2


@given(
    parsers.parse('Grove calls "{action}" during Helix initialization'),
    target_fixture="grove_init",
)
def call_grove_during_initialization(action: str) -> str:
    if action not in {"grove-focus!", "grove-visibility-toggle!"}:
        raise ValueError(f"Unknown Grove action: {action}")
    return f"({action})"


@when("Grove startup is attempted", target_fixture="helix")
def attempt_start(
    resources: ExitStack,
    tmp_path: Path,
    server: Server,
    helix_sandbox: HelixSandbox,
    grove_settings: dict[str, str],
    grove_start_count: int,
) -> HelixDriver:
    workspace = WorkspaceFixture.create(
        tmp_path / "workspace",
        [EntrySpec(Path("anchor.txt"))],
    )
    resources.callback(workspace.close)
    helix = start_grove_helix(
        helix_sandbox,
        REPOSITORY,
        server,
        workspace,
        active_file=None,
        settings=grove_settings,
        starts=grove_start_count,
        theme=TEST_THEME,
    )
    resources.callback(helix.close)
    return helix


@then(parsers.parse('Grove startup reports "{message}"'))
def startup_reports(helix: HelixDriver, message: str) -> None:
    helix.terminal.wait(
        lambda frame: (
            None
            if any(message in line for line in frame.lines)
            else f'Grove startup did not report "{message}"'
        )
    )


@when("Helix starts with Grove in that Workspace", target_fixture="grove")
def start_helix(
    resources: ExitStack,
    server: Server,
    helix_sandbox: HelixSandbox,
    workspace: WorkspaceFixture,
    active_file: Path | None,
    grove_settings: dict[str, str],
    grove_init: str,
    helix_theme: str,
) -> GroveDriver:
    return _launch(
        resources,
        helix_sandbox,
        server,
        workspace,
        active_file,
        settings=grove_settings,
        theme=helix_theme,
        init=grove_init,
    )


@given(
    parsers.parse('the Host theme uses background "{background}" and text "{text}"'),
    target_fixture="helix_theme",
)
def theme_with_inputs(
    background: str,
    text: str,
) -> str:
    return (
        TEST_THEME
        + f'"ui.background" = {{ bg = "{background}" }}\n'
        + f'"ui.text" = {{ fg = "{text}" }}\n'
    )


@given(
    parsers.parse(
        'the Host theme uses Active buffer background "{bufferline}" '
        'and Statusline background "{statusline}"'
    ),
    target_fixture="helix_theme",
)
def theme_with_active_file_backgrounds(
    bufferline: str,
    statusline: str,
) -> str:
    bufferline_background = f', bg = "{bufferline}"' if bufferline != "missing" else ""
    return (
        TEST_THEME
        + '"ui.bufferline.active" = { fg = "#abcdef", '
        + f'modifiers = ["bold"]{bufferline_background} }}\n'
        + f'"ui.statusline.active" = {{ bg = "{statusline}" }}\n'
    )


@given(
    "the Host theme defines ui.virtual.whitespace but not ui.virtual.indent-guide",
    target_fixture="helix_theme",
)
def theme_with_whitespace_guides() -> str:
    theme = TEST_THEME.replace(
        '"ui.virtual.indent-guide" = { fg = "#888888" }',
        '"ui.virtual.whitespace" = { fg = "#888888" }',
    )
    assert theme != TEST_THEME
    return theme


@when(
    parsers.parse('Helix starts with Grove in Workspace "{workspace_name}"'),
    target_fixture="grove",
)
def start_helix_in_named_workspace(
    resources: ExitStack,
    server: Server,
    helix_sandbox: HelixSandbox,
    workspaces: dict[str, WorkspaceFixture],
    active_file: Path | None,
    workspace_name: str,
) -> GroveDriver:
    return _launch(
        resources,
        helix_sandbox,
        server,
        workspaces[workspace_name],
        active_file,
    )


@when(
    parsers.parse(
        'Helix starts with Grove ready for an Active file change to "{name}"'
    ),
    target_fixture="grove",
)
def start_helix_ready_for_active_file_change(
    resources: ExitStack,
    tmp_path: Path,
    server: Server,
    helix_sandbox: HelixSandbox,
    workspace: WorkspaceFixture,
    active_file: Path | None,
    name: str,
) -> GroveDriver:
    target = json.dumps(str(workspace.document_path(name)))
    signal = json.dumps(str(tmp_path / "host-file-change"))
    init = (
        '(require "helix/misc.scm")\n'
        '(require (prefix-in helix. "helix/commands.scm"))\n'
        "(define (host-file-change-ready?)\n"
        f"  (with-handler (lambda (_) #f) (file-metadata {signal})))\n"
        "(define (await-host-file-change)\n"
        "  (if (host-file-change-ready?)\n"
        f"      (helix.open {target})\n"
        "      (enqueue-thread-local-callback-with-delay\n"
        "       20 await-host-file-change)))\n"
        "(enqueue-thread-local-callback-with-delay\n"
        " 20 await-host-file-change)"
    )
    return _launch(
        resources,
        helix_sandbox,
        server,
        workspace,
        active_file,
        init=init,
    )


def _launch(
    resources: ExitStack,
    helix_sandbox: HelixSandbox,
    server: Server,
    workspace: WorkspaceFixture,
    active_file: Path | None,
    *,
    settings: dict[str, str] | None = None,
    theme: str = TEST_THEME,
    init: str = "",
) -> GroveDriver:
    grove = start_grove(
        helix_sandbox,
        REPOSITORY,
        server,
        workspace,
        active_file=active_file,
        settings=settings,
        theme=theme,
        init=init,
    )
    resources.callback(grove.close)
    return grove


@given(
    "a Workspace containing entries",
    target_fixture="workspace",
)
def workspace_with_entries(
    resources: ExitStack,
    tmp_path: Path,
    datatable: list[list[str]],
) -> WorkspaceFixture:
    workspace = WorkspaceFixture.create(tmp_path / "workspace", _entries(datatable))
    resources.callback(workspace.close)
    return workspace


@given(parsers.parse('"{name}" is Active'), target_fixture="active_file")
def select_active_file(workspace: WorkspaceFixture, name: str) -> Path:
    return workspace.document_path(name)


@given("an Active file outside the Workspace", target_fixture="active_file")
def select_active_file_outside_workspace(workspace: WorkspaceFixture) -> Path:
    outside = workspace.root.parent / "outside.txt"
    outside.write_text("outside\n", encoding="utf-8")
    return outside


@given(parsers.parse('a Workspace named "{name}" containing entries'))
def named_workspace_with_entries(
    resources: ExitStack,
    tmp_path: Path,
    workspaces: dict[str, WorkspaceFixture],
    name: str,
    datatable: list[list[str]],
) -> None:
    workspace = WorkspaceFixture.create(tmp_path / name, _entries(datatable))
    resources.callback(workspace.close)
    workspaces[name] = workspace


@given(
    parsers.parse('"{name}" is Active in Workspace "{workspace_name}"'),
    target_fixture="active_file",
)
def select_named_active_file(
    workspaces: dict[str, WorkspaceFixture],
    workspace_name: str,
    name: str,
) -> Path:
    return workspaces[workspace_name].document_path(name)


@given(parsers.parse('Git tracks "{name}" as {status} in Workspace "{workspace_name}"'))
def named_workspace_git_status(
    workspaces: dict[str, WorkspaceFixture],
    workspace_name: str,
    name: str,
    status: str,
) -> None:
    workspace = workspaces[workspace_name]
    if status not in {"clean", "modified"}:
        raise ValueError(f"Unsupported Git test status: {status!r}")
    GitFixture(workspace).report([GitStatusSpec(name, status)])


@given(parsers.parse('"{name}" is unreadable'))
@when(parsers.parse('"{name}" becomes unreadable'))
def make_entry_unreadable(
    workspace: WorkspaceFixture,
    name: str,
) -> None:
    workspace.set_unreadable(name)


@when(parsers.parse('"{name}" is created'))
def create_workspace_file(workspace: WorkspaceFixture, name: str) -> None:
    workspace.create_file(name)


@when(parsers.parse('"{name}" is deleted'))
def delete_workspace_file(workspace: WorkspaceFixture, name: str) -> None:
    workspace.delete(name)


@when(parsers.parse('"{name}" appears as a file'))
def create_external_link_target(workspace: WorkspaceFixture, name: str) -> None:
    target = workspace.root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("target\n", encoding="utf-8")


@when(parsers.parse('"{name}" becomes readable'))
def entry_becomes_readable(workspace: WorkspaceFixture, name: str) -> None:
    workspace.set_readable(name)


@given("Git reports statuses")
def git_reports_statuses(
    workspace: WorkspaceFixture,
    datatable: list[list[str]],
) -> None:
    header, *rows = datatable
    records = (dict(zip(header, row)) for row in rows)
    GitFixture(workspace).report(
        [
            GitStatusSpec(record["path"], record["status"], record.get("source"))
            for record in records
        ]
    )


@given(parsers.parse('Git tracks "{name}"'))
def git_tracks_path(workspace: WorkspaceFixture, name: str) -> None:
    GitFixture(workspace).initialize(name)


@given(
    parsers.parse(
        'a parent Git repository tracks "{name}" as modified inside the Workspace'
    )
)
def parent_git_tracks_modified(workspace: WorkspaceFixture, name: str) -> None:
    GitFixture(workspace).initialize(root=workspace.root.parent)
    with workspace.document_path(name).open("a", encoding="utf-8") as document:
        document.write("modified\n")


@given(parsers.parse('"{name}" is a Git repository'))
def directory_is_git_repository(workspace: WorkspaceFixture, name: str) -> None:
    root = workspace.root / name
    if not root.is_dir():
        raise ValueError(f'Git repository directory does not exist: "{name}"')
    GitFixture(workspace).initialize(root=root)


@when("the Workspace root becomes unreadable")
def workspace_root_becomes_unreadable(
    workspace: WorkspaceFixture,
) -> None:
    workspace.set_root_unreadable()


@when("Git metadata becomes unavailable")
def git_metadata_becomes_unavailable(workspace: WorkspaceFixture) -> None:
    GitFixture(workspace).hide_metadata()


def _entries(table: list[list[str]]) -> list[EntrySpec]:
    header, *rows = table
    entries = []
    for row in rows:
        record = dict(zip(header, row))
        count = int(record.get("count") or "1")
        for index in range(count):
            path = record["path"].format(index) if count > 1 else record["path"]
            entries.append(
                EntrySpec(
                    Path(path),
                    record.get("kind") or "file",
                    Path(record["target"]) if record.get("target") else None,
                    int(record.get("lines") or "1"),
                )
            )
    return entries
