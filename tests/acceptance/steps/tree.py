from pytest_bdd import parsers, then, when

from tests.support.grove import GroveDriver, GroveFrame, VisibleRow
from tests.support.workspace import WorkspaceFixture

from .rows import scenario_path


def _visible_row(
    frame: GroveFrame,
    name: str,
) -> VisibleRow | None:
    return frame.row(scenario_path(name))


@then(parsers.parse('the File tree shows "{name}"'))
def file_tree_shows(grove: GroveDriver, name: str) -> None:
    grove.wait_for_row(scenario_path(name))


@then(parsers.parse('the File tree already shows "{name}"'))
def file_tree_already_shows(grove: GroveDriver, name: str) -> None:
    assert _visible_row(grove.capture(), name) is not None, (
        f'Grove did not yet show "{name}"'
    )


@then(parsers.parse('the File tree already does not show "{name}"'))
def file_tree_already_does_not_show(grove: GroveDriver, name: str) -> None:
    assert _visible_row(grove.capture(), name) is None, f'Grove still showed "{name}"'


@then(
    parsers.re(
        r'^the content of "(?P<name>.+)" '
        r'(?P<comparison>starts with|contains) "(?P<text>.*)"$'
    )
)
def file_content_matches(
    grove: GroveDriver,
    workspace: WorkspaceFixture,
    name: str,
    text: str,
    comparison: str,
) -> None:
    document = workspace.path(name)

    def mismatch(_frame: GroveFrame) -> str | None:
        try:
            content = document.read_text(encoding="utf-8")
        except FileNotFoundError:
            return f'"{name}" disappeared while Helix saved it'
        matches = (
            content.startswith(text) if comparison == "starts with" else text in content
        )
        return None if matches else f'Expected "{name}" content: {comparison} {text!r}'

    grove.wait(mismatch)


@then(parsers.parse('the File tree does not show "{name}"'))
def file_tree_does_not_show(grove: GroveDriver, name: str) -> None:
    path = scenario_path(name)

    def absent(frame: GroveFrame) -> str | None:
        return None if frame.row(path) is None else f'Grove kept showing "{name}"'

    grove.wait(absent)
    grove.hold(absent)


@then("File tree rows appear in order")
def file_tree_rows_appear_in_order(
    grove: GroveDriver,
    datatable: list[list[str]],
) -> None:
    names = [row[0] for row in datatable[1:]]

    def mismatch(frame: GroveFrame) -> str | None:
        rows = [_visible_row(frame, name) for name in names]
        missing = [name for name, row in zip(names, rows, strict=True) if row is None]
        if missing:
            return f"Grove did not show File tree rows {missing!r}"
        positions = [row.number for row in rows if row is not None]
        if positions == sorted(positions):
            return None
        actual = [
            name
            for _position, name in sorted(
                zip(positions, names, strict=True),
            )
        ]
        return f"File tree row order was {actual!r}, not {names!r}"

    grove.wait(mismatch)


_ICONS = {
    "Broken link": "󰌺",
    "File link": "",
    "directory": "",
    "file": "󰈙",
}


@then(
    parsers.re(
        r'^"(?P<name>.+)" uses the '
        r"(?P<kind>Broken link|File link|directory|file) icon$"
    )
)
def entry_uses_icon(grove: GroveDriver, name: str, kind: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if (row := _visible_row(frame, name)) is not None
            and _ICONS[kind] in row.text[: row.label_column]
            else f'"{name}" did not use the {kind} icon'
        ),
    )


@then("the Workspace root uses one File tree icon")
def workspace_root_uses_one_icon(grove: GroveDriver) -> None:
    frame = _frame_with_rows(grove)
    row = frame.pane.workspace_root if frame.pane else None
    assert row is not None
    assert row.text.count("󰙅") == 1
    assert row.disclosure is None and "" not in row.text


@then("the Workspace root has neither an Ancestor trace nor a Leaf mark")
def workspace_root_has_no_ancestor_trace_or_leaf_mark(grove: GroveDriver) -> None:
    frame = _frame_with_rows(grove)
    row = frame.pane.workspace_root if frame.pane else None
    assert row is not None
    assert "│" not in row.text[: row.label_column]
    assert "·" not in row.text[: row.label_column]


@then(
    parsers.re(
        r'^"(?P<name>.+)" uses (?P<count>\d+) '
        r"(?P<kind>Ancestor trace|Leaf mark)s?$"
    )
)
def entry_uses_guides(grove: GroveDriver, name: str, count: str, kind: str) -> None:
    frame = _frame_with_rows(grove, name)
    row = _visible_row(frame, name)
    assert row is not None
    glyph = "│" if kind == "Ancestor trace" else "·"
    assert row.text[: row.label_column].count(glyph) == int(count)


@then(parsers.parse('"{name}" uses the Active file mark'))
@then(parsers.parse('"{name}" keeps the Active file mark'))
def entry_uses_active_file_mark(grove: GroveDriver, name: str) -> None:
    def mismatch(frame: GroveFrame) -> str | None:
        row = _visible_row(frame, name)
        if row is None:
            return f'Grove did not show "{name}"'
        leading = row.text[: row.label_column]
        return (
            None
            if leading.count("*") == 1 and "·" not in leading
            else f'"{name}" did not use the Active file mark'
        )

    grove.wait(mismatch)


@then(parsers.parse('"{name}" already uses the Active file mark'))
def entry_already_uses_active_file_mark(grove: GroveDriver, name: str) -> None:
    row = _visible_row(grove.capture(), name)
    assert row is not None
    assert "*" in row.text[: row.label_column]


@then(parsers.parse('"{name}" uses the Cursor mark in the first cell'))
def entry_uses_cursor_mark(grove: GroveDriver, name: str) -> None:
    frame = _frame_with_rows(grove, name)
    row = _visible_row(frame, name)
    assert row is not None
    assert frame.pane is not None and frame.pane.cursor == row


@then(parsers.parse('"{name}" has no Cursor mark'))
def entry_has_no_cursor_mark(grove: GroveDriver, name: str) -> None:
    frame = _frame_with_rows(grove, name)
    row = _visible_row(frame, name)
    assert row is not None
    assert frame.pane is not None and frame.pane.cursor != row


@then("the Cursor mark uses the Cursor row colors")
def cursor_mark_uses_cursor_colors(grove: GroveDriver) -> None:
    frame = grove.wait(
        lambda frame: (
            None if frame.pane and frame.pane.cursor else "Grove has no Cursor"
        )
    )
    assert frame.pane is not None and frame.pane.cursor is not None
    row = frame.pane.cursor
    assert row.foreground_at(">") == (216, 216, 216)
    assert row.background_at(">") == (48, 48, 48)


@then("the Active file mark uses the theme info foreground and Cursor row background")
def active_file_mark_uses_info_on_cursor(grove: GroveDriver) -> None:
    frame = grove.wait(
        lambda frame: (
            None
            if frame.pane
            and frame.pane.cursor
            and "*" in frame.pane.cursor.text[: frame.pane.cursor.label_column]
            else "Cursor did not carry the Active file mark"
        )
    )
    assert frame.pane is not None and frame.pane.cursor is not None
    row = frame.pane.cursor
    assert row.foreground_at("*") == (0, 255, 255)
    assert row.background_at("*") == (48, 48, 48)


@then(
    parsers.re(
        r'^the Ancestor traces? and Leaf mark on "(?P<name>.+)" '
        r"use the (?P<source>theme Guides|terminal gray) foreground$"
    )
)
def ancestor_traces_and_leaf_mark_use_foreground(
    grove: GroveDriver,
    name: str,
    source: str,
) -> None:
    frame = _frame_with_rows(grove, name)
    row = _visible_row(frame, name)
    assert row is not None
    foreground = (136, 136, 136) if source == "theme Guides" else (128, 128, 128)
    assert row.foreground_at("│") == foreground
    assert row.foreground_at("·") == foreground
    assert not any((row.is_dimmed_at("│"), row.is_dimmed_at("·")))


@then(parsers.parse('"{file}" aligns with "{directory}" in icon mode'))
def icon_mode_entries_align(grove: GroveDriver, file: str, directory: str) -> None:
    frame = _frame_with_rows(grove, file, directory)
    file_row = frame.row(scenario_path(file))
    directory_row = frame.row(scenario_path(directory))
    assert file_row is not None and directory_row is not None
    assert file_row.label_column == directory_row.label_column


@then(
    parsers.parse(
        'the Workspace label starts in column 4 and "{directory}" and "{file}" '
        "labels start in column 6"
    )
)
def icon_label_columns(grove: GroveDriver, directory: str, file: str) -> None:
    frame = _frame_with_rows(grove, directory, file)
    root = frame.pane.workspace_root if frame.pane else None
    directory_row = frame.row(scenario_path(directory))
    file_row = frame.row(scenario_path(file))
    assert root is not None and root.label_column == 3
    assert directory_row is not None and directory_row.label_column == 5
    assert file_row is not None and file_row.label_column == 5


@then(parsers.parse('"{name}" can expand'))
def entry_can_expand(grove: GroveDriver, name: str) -> None:
    _wait_for_disclosure(grove, name, "▸")


@then(parsers.parse('"{name}" cannot expand'))
def entry_cannot_expand(grove: GroveDriver, name: str) -> None:
    _wait_for_disclosure(grove, name, None)


@then(parsers.parse('"{child}" is indented two columns from "{parent}"'))
def child_is_indented(grove: GroveDriver, child: str, parent: str) -> None:
    frame = _frame_with_rows(grove, child, parent)
    child_row = frame.row(scenario_path(child))
    parent_row = frame.row(scenario_path(parent))
    assert child_row is not None and parent_row is not None
    assert child_row.label_column == parent_row.label_column + 2


@then(
    parsers.parse(
        'Workspace, "{directory}", and "{file}" labels occupy reclaimed icon columns'
    )
)
def labels_reclaim_icon_columns(
    grove: GroveDriver,
    workspace: WorkspaceFixture,
    directory: str,
    file: str,
) -> None:
    frame = _frame_with_rows(grove, directory, file)
    root = frame.pane.workspace_root if frame.pane else None
    directory_row = frame.row(scenario_path(directory))
    file_row = frame.row(scenario_path(file))
    assert root is not None and root.label == workspace.root.name
    assert root.label_column == 1
    assert directory_row is not None and directory_row.label_column == 3
    assert file_row is not None and file_row.label_column == 3


def _frame_with_rows(grove: GroveDriver, *names: str) -> GroveFrame:
    def mismatch(frame: GroveFrame) -> str | None:
        if frame.pane is None or frame.pane.workspace_root is None:
            return "Grove did not show the Workspace root"
        missing = [name for name in names if _visible_row(frame, name) is None]
        return f"Grove did not show rows {missing!r}" if missing else None

    return grove.wait(mismatch)


@when(parsers.parse('the "{name}" directory is expanded'))
def expand_directory(grove: GroveDriver, name: str) -> None:
    _toggle_directory(grove, name, "▾")


@when(parsers.parse('the "{name}" directory is collapsed'))
def collapse_directory(grove: GroveDriver, name: str) -> None:
    _toggle_directory(grove, name, "▸")


@then(parsers.parse('"{name}" remains expanded'))
def directory_remains_expanded(grove: GroveDriver, name: str) -> None:
    _wait_for_disclosure(grove, name, "▾")


@then(parsers.parse('"{name}" remains collapsed'))
def directory_remains_collapsed(grove: GroveDriver, name: str) -> None:
    _wait_for_disclosure(grove, name, "▸")


def _toggle_directory(grove: GroveDriver, name: str, disclosure: str) -> None:
    grove.press_row(scenario_path(name)).release()
    _wait_for_disclosure(grove, name, disclosure)


def _wait_for_disclosure(grove: GroveDriver, name: str, disclosure: str | None) -> None:
    grove.wait(
        lambda frame: (
            None
            if (row := _visible_row(frame, name)) is not None
            and row.disclosure == disclosure
            else f'Grove did not show "{name}" with disclosure {disclosure!r}'
        ),
    )


@then(parsers.parse('the File tree root is "{name}"'))
def file_tree_root_is(grove: GroveDriver, name: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if frame.pane is not None
            and (root := frame.pane.workspace_root) is not None
            and root.label == name
            else f'Grove did not show Workspace root "{name}"'
        ),
    )


@then(parsers.parse('Pane row {number:d} is "{name}"'))
def pane_row_is(grove: GroveDriver, number: int, name: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if (row := _visible_row(frame, name)) is not None and row.number == number
            else f'Pane row {number} was not "{name}"'
        ),
    )


@then(parsers.parse('Pane row {number:d} is not "{name}"'))
def pane_row_is_not(grove: GroveDriver, number: int, name: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if frame.pane is not None
            and frame.pane.workspace_root is not None
            and ((row := _visible_row(frame, name)) is None or row.number != number)
            else f'Pane row {number} remained "{name}"'
        ),
    )


@then(parsers.parse("Pane row {number:d} is unused"))
def pane_row_is_unused(grove: GroveDriver, number: int) -> None:
    grove.wait(
        lambda frame: (
            None
            if frame.pane is not None and not frame.pane.row_text(number).strip()
            else f"Pane row {number} was not unused"
        ),
    )


@then(parsers.parse('the File tree ends with "{name}"'))
def file_tree_ends_with(grove: GroveDriver, name: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if (row := _visible_row(frame, name)) is not None
            and row.number == frame.helix.terminal.height
            else f'Grove did not clamp the File tree at "{name}"'
        ),
    )


@then(
    parsers.parse(
        'the Ancestor stack is "{names}" above File tree row "{first_visible}"'
    )
)
def ancestor_stack_is_above_file_tree_row(
    grove: GroveDriver,
    names: str,
    first_visible: str,
) -> None:
    expected = (*names.split(" > "), first_visible)
    grove.wait(
        lambda frame: (
            None
            if all(
                (row := _visible_row(frame, name)) is not None and row.number == number
                for number, name in enumerate(expected, start=1)
            )
            else (
                f'Grove did not show Ancestor stack "{names}" above "{first_visible}"'
            )
        ),
    )


@then(parsers.parse('the Ancestor stack is "{names}" above File tree content'))
def ancestor_stack_is_above_file_tree_content(
    grove: GroveDriver,
    names: str,
) -> None:
    expected = names.split(" > ")
    grove.wait(
        lambda frame: (
            None
            if all(
                (row := _visible_row(frame, name)) is not None and row.number == number
                for number, name in enumerate(expected, start=1)
            )
            and frame.pane is not None
            and bool(frame.pane.row_text(len(expected) + 1).strip())
            else f'Grove did not show Ancestor stack "{names}" above File tree content'
        ),
    )
