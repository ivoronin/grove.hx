import json
from pathlib import Path

from pytest_bdd import parsers, then, when

from tests.support.grove import GroveDriver, GroveFrame
from tests.support.workspace import WorkspaceFixture

from .rows import scenario_path


@when(parsers.parse('the editor receives "{key}" while Grove is unfocused'))
def editor_receives(grove: GroveDriver, key: str) -> None:
    grove.helix.terminal.write(key)


@when(
    parsers.parse(
        'Grove receives Helix\'s file-picker chord and searches for "{query}"'
    )
)
def grove_receives_file_picker_chord(grove: GroveDriver, query: str) -> None:
    grove.helix.terminal.key("Space")
    grove.helix.terminal.write("f")
    grove.helix.terminal.write(query)
    grove.helix.terminal.key("Enter")
    # The picker decides the Active file. Focusing Grove before it finishes
    # starts the Cursor on the previous Active file.
    grove.wait_for_active_document(query)


@when(parsers.parse('Helix changes the Active file to "{name}"'))
def helix_changes_active_file(
    tmp_path: Path,
    workspace: WorkspaceFixture,
    name: str,
) -> None:
    workspace.document_path(name)
    (tmp_path / "host-file-change").touch()


@when(
    parsers.parse(
        'the editor cursor moves to line {line_number:d} in "{name}" '
        "with line {first_visible_line_number:d} first"
    )
)
def editor_moves_and_aligns_line(
    grove: GroveDriver,
    workspace: WorkspaceFixture,
    line_number: int,
    name: str,
    first_visible_line_number: int,
) -> None:
    grove.wait(
        lambda frame: (
            None
            if frame.helix.view(name) is not None
            else f'Helix did not show "{name}" before navigation'
        ),
    )
    grove.helix.terminal.write(f"{line_number}Gzt")
    grove.wait(
        lambda frame: (
            None
            if (view := frame.helix.view(name)) is not None
            and view.first_visible_line is not None
            and workspace.numbered_line(name, first_visible_line_number)
            in view.first_visible_line
            else (
                f'Helix did not show line {first_visible_line_number} first in "{name}"'
            )
        ),
    )


@when(
    parsers.parse(
        'the editor inserts "{text}" without saving and returns to Normal mode'
    )
)
def editor_inserts_without_saving(grove: GroveDriver, text: str) -> None:
    _insert(grove, text)


@when(parsers.parse('the editor pastes "{text}"'))
def editor_pastes(grove: GroveDriver, text: str) -> None:
    grove.helix.terminal.paste(text)


@when(parsers.parse('the editor inserts "{text}" and saves'))
def editor_inserts_and_saves(grove: GroveDriver, text: str) -> None:
    _insert(grove, text)
    grove.helix.command("write")


def _insert(grove: GroveDriver, text: str) -> None:
    grove.helix.terminal.write("i")
    grove.helix.terminal.write(text)
    grove.wait(
        lambda frame: (
            None if frame.helix.mode == "Insert" else "Helix did not enter Insert mode"
        ),
    )
    grove.helix.terminal.key("Escape")
    grove.wait(
        lambda frame: (
            None if frame.helix.mode == "Normal" else "Helix did not leave Insert mode"
        ),
    )


@when(parsers.parse("the terminal width becomes {width:d} columns"))
def terminal_width_becomes(grove: GroveDriver, width: int) -> None:
    grove.helix.terminal.resize(width=width)
    grove.wait(
        lambda frame: (
            None
            if frame.helix.terminal.width == width
            else f"Terminal did not resize to {width} columns"
        ),
    )


@when(parsers.parse("the terminal height becomes {height:d} rows"))
def terminal_height_becomes(grove: GroveDriver, height: int) -> None:
    grove.helix.terminal.resize(height=height)
    grove.wait(
        lambda frame: (
            None
            if frame.helix.terminal.height == height == len(frame.helix.terminal.lines)
            else f"Terminal did not resize to {height} rows"
        ),
    )


@when("Grove is focused")
def focus_grove(grove: GroveDriver) -> None:
    grove.focus()


@when("Grove Visibility is toggled")
def toggle_grove_visibility(grove: GroveDriver) -> None:
    grove.toggle_visibility()


@when(parsers.parse('Grove receives "{key}"'))
def grove_receives_key(grove: GroveDriver, key: str) -> None:
    grove.key(key)


@when(parsers.parse('Helix runs "{command}" for Workspace "{workspace_name}"'))
def change_workspace(
    grove: GroveDriver,
    workspaces: dict[str, WorkspaceFixture],
    command: str,
    workspace_name: str,
) -> None:
    workspace = workspaces[workspace_name]
    {
        "cd": grove.change_workspace,
        "push-directory": grove.push_workspace,
        "pop-directory": grove.pop_workspace,
    }[command](workspace)


@when("a file outside the Workspace is opened")
def open_file_outside_workspace(
    grove: GroveDriver, workspace: WorkspaceFixture
) -> None:
    outside = workspace.root.parent / "outside.txt"
    outside.write_text("outside\n", encoding="utf-8")
    grove.helix.command(f"open {json.dumps(str(outside))}")
    grove.wait(
        lambda frame: (
            None
            if frame.helix.contains("outside")
            else "Helix did not open the file outside the Workspace"
        ),
    )


@then(parsers.parse("the active Editor view is in {mode} mode"))
def editor_has_mode(grove: GroveDriver, mode: str) -> None:
    grove.wait(
        lambda frame: (
            None if frame.helix.mode == mode else f"Editor did not enter {mode} mode"
        ),
    )


@then(parsers.parse('Helix shows the "{name}" document'))
def helix_shows_document(grove: GroveDriver, name: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if frame.helix.document == name
            else f'Helix did not show document "{name}"'
        ),
    )


@then("the editor still shows the outside file")
def editor_still_shows_outside_file(grove: GroveDriver) -> None:
    grove.wait(
        lambda frame: (
            None
            if frame.helix.contains("outside")
            else "Helix stopped showing the file outside the Workspace"
        ),
    )


@then(
    parsers.parse(
        'the editor view for "{name}" is restored at line {line_number:d} '
        "with line {first_visible_line_number:d} first"
    )
)
def editor_view_is_restored(
    grove: GroveDriver,
    workspace: WorkspaceFixture,
    name: str,
    line_number: int,
    first_visible_line_number: int,
) -> None:
    grove.wait(
        lambda frame: (
            None
            if (view := frame.helix.view(name)) is not None
            and view.cursor == (line_number, 1)
            and view.first_visible_line is not None
            and workspace.numbered_line(name, first_visible_line_number)
            in view.first_visible_line
            else f'Helix did not restore "{name}" at line {line_number}'
        ),
    )


@then(parsers.parse("the editor cursor is on line {line_number:d}"))
def editor_cursor_is_on_line(grove: GroveDriver, line_number: int) -> None:
    grove.wait(
        lambda frame: (
            None
            if (view := frame.helix.active_view) is not None
            and view.cursor is not None
            and view.cursor[0] == line_number
            else f"Helix did not move the editor cursor to line {line_number}"
        ),
    )


@then("Helix receives the modified key")
def helix_receives_modified_key(grove: GroveDriver) -> None:
    grove.helix.wait(
        lambda frame: (
            None
            if "Grove test key reached Helix" in frame.bottom_line
            else "Helix did not receive the modified key"
        )
    )


@then(parsers.parse('the editor does not contain "{text}"'))
def editor_does_not_contain(grove: GroveDriver, text: str) -> None:
    grove.hold(
        lambda frame: (
            f'Helix inserted "{text}" into the editor'
            if frame.helix.contains(text)
            else None
        ),
    )


@then(parsers.parse("Helix Editor view count is {count:d}"))
def helix_has_editor_views(grove: GroveDriver, count: int) -> None:
    grove.wait(
        lambda frame: (
            None
            if len(frame.helix.views) == count
            else f"Helix did not show {count} editor views"
        ),
    )


@then(parsers.parse("Helix Editor views are split {direction}"))
def helix_editor_views_are_split(grove: GroveDriver, direction: str) -> None:
    def mismatch(frame: GroveFrame) -> str | None:
        if len(frame.helix.views) != 2:
            return "Helix did not show two Editor views"
        first, second = frame.helix.views
        horizontal = first.status_row != second.status_row
        if horizontal == (direction == "horizontally"):
            return None
        return f"Helix Editor views were not split {direction}"

    if direction not in {"horizontally", "vertically"}:
        raise ValueError(f"Unknown split direction: {direction!r}")
    grove.wait(mismatch)


@then(parsers.parse('"{name}" has Cursor'))
def entry_has_cursor(grove: GroveDriver, name: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if (row := frame.row(scenario_path(name))) is not None
            and frame.pane is not None
            and frame.pane.cursor == row
            else f'Grove did not place Cursor on "{name}"'
        ),
    )


@when("Helix closes the active Editor view")
def helix_closes_active_editor_view(grove: GroveDriver) -> None:
    grove.helix.command("quit!")


@when("Helix exits")
def exit_helix(grove: GroveDriver) -> None:
    grove.helix.quit()


@when(
    parsers.parse(
        'Helix reloads configuration {count:d} times through "{method}" '
        "with reload key {key}"
    )
)
def repeated_configuration_reload(
    grove: GroveDriver, count: int, method: str, key: str
) -> None:
    for iteration in range(count):
        if iteration:
            grove.helix.terminal.key("Escape")
            grove.helix.wait(
                lambda frame: (
                    None
                    if "Config refreshed" not in frame.bottom_line
                    else "Reload status not cleared"
                )
            )
        if method == "command prompt":
            grove.helix.command("config-reload")
        elif method == "hotkey":
            grove.helix.terminal.key(key.replace("C-", "Ctrl-", 1))
        else:
            raise ValueError(f"Unknown reload method: {method}")
        grove.helix.wait(
            lambda frame: (
                None
                if "Config refreshed" in frame.bottom_line
                else "Reload not completed"
            )
        )


@then("Helix exits normally")
def helix_exits_normally(grove: GroveDriver) -> None:
    assert grove.helix.wait_for_exit() == 0


@then("Grove does not replace the error with a generic notice")
def grove_does_not_replace_open_error(grove: GroveDriver) -> None:
    grove.hold(
        lambda frame: (
            "Grove replaced Helix's open error with a generic notice"
            if frame.helix.contains("Grove: cannot open file")
            else None
        ),
    )
