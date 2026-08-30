from pathlib import PurePath

from pytest_bdd import parsers, then

from tests.support.grove import GroveDriver, GroveFrame, VisibleRow

from .rows import scenario_path


@then(parsers.parse('Grove is Docked on the "{side}" at width {width:d}'))
def grove_is_docked(grove: GroveDriver, side: str, width: int) -> None:
    def mismatch(frame: GroveFrame) -> str | None:
        actual = frame.pane.width if frame.pane and frame.pane.side == side else None
        if actual == width:
            return None
        return (
            f"Grove was not Docked on the {side} at width {width}; "
            f"observed width {actual}"
        )

    grove.wait(mismatch)


@then(parsers.parse("Grove has width {width:d}"))
def grove_has_width(grove: GroveDriver, width: int) -> None:
    grove.wait(
        lambda frame: (
            None
            if frame.pane is not None and frame.pane.width == width
            else f"Grove did not retain width {width}"
        ),
    )


@then("Grove yields the whole terminal to Helix")
def grove_yields_to_helix(grove: GroveDriver) -> None:
    def mismatch(frame: GroveFrame) -> str | None:
        if frame.pane is not None:
            return "Grove still has a Pane"
        view = frame.helix.active_view
        if view is None:
            return "Helix has no active Editor view"
        if view.column_bounds != (0, frame.helix.terminal.width):
            raise AssertionError("Grove left empty space before Helix reclaimed it")
        return None

    grove.wait(mismatch)


_FOREGROUNDS = {
    "conflict Git": (255, 0, 255),
    "deleted Git": (255, 0, 0),
    "modified Git": (255, 255, 0),
    "configured modified Git": (69, 103, 137),
    "created Git": (0, 255, 0),
    "theme text": (216, 216, 216),
}


def _has_background(
    row: VisibleRow,
    markers: tuple[str, ...],
    expected: tuple[int, int, int],
) -> bool:
    return all(row.background_at(marker) == expected for marker in markers)


@then(
    parsers.re(
        r'^"(?P<name>.+)" uses the '
        r"(?P<foreground>conflict Git|deleted Git|modified Git|configured modified Git|created Git|theme text) "
        r"foreground$"
    )
)
def entry_uses_foreground(grove: GroveDriver, name: str, foreground: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if (row := frame.row(scenario_path(name))) is not None
            and row.foreground_at(row.label) == _FOREGROUNDS[foreground]
            else f'"{name}" did not use the {foreground} foreground'
        ),
    )


@then(
    parsers.re(
        r'^"(?P<name>.+)" uses the (?P<kind>unreadable-directory|broken-link) '
        r"icon and error foreground$"
    )
)
def failed_entry_uses_error_presentation(
    grove: GroveDriver, name: str, kind: str
) -> None:
    icon = {"unreadable-directory": "󰷌", "broken-link": "󰌺"}[kind]
    grove.wait(
        lambda frame: (
            None
            if (row := frame.row(scenario_path(name))) is not None
            and row.foreground_at(icon) == (255, 0, 255)
            and row.foreground_at(row.label) == (255, 0, 255)
            else f'"{name}" did not use the error foreground'
        ),
    )


@then(parsers.parse('"{name}" uses the "{variant}" file icon variant'))
def file_icon_uses_variant(grove: GroveDriver, name: str, variant: str) -> None:
    color = {"dark": (137, 224, 81), "light": (68, 112, 40)}[variant]
    grove.wait(
        lambda frame: (
            None
            if (row := frame.row(scenario_path(name))) is not None
            and row.foreground_at("󰈙") == color
            else f"Grove did not use the {variant} file-icon variant"
        ),
    )


@then(parsers.re(r"^these rows carry (?P<amount>one|no) Unsaved mark$"))
def rows_carry_unsaved_mark(
    grove: GroveDriver,
    datatable: list[list[str]],
    amount: str,
) -> None:
    expected = amount == "one"
    names = [row[0] for row in datatable[1:]]

    def mismatch(frame: GroveFrame) -> str | None:
        for name in names:
            row = (
                frame.pane.workspace_root
                if name == "Workspace root" and frame.pane is not None
                else frame.row(scenario_path(name))
            )
            if row is None:
                return f'Grove did not show "{name}"'
            if row.has_unsaved_mark != expected:
                return (
                    f'"{name}" carried an Unsaved mark'
                    if not expected
                    else f'"{name}" did not carry an Unsaved mark'
                )
        return None

    grove.wait(mismatch)


@then(
    parsers.re(
        r'^"(?P<name>.+)" clips '
        r"(?P<mark>without an Unsaved mark|with its Unsaved mark visible)$"
    )
)
def long_filename_clips(grove: GroveDriver, name: str, mark: str) -> None:
    suffix = {
        "without an Unsaved mark": "…",
        "with its Unsaved mark visible": "…+",
    }[mark]
    grove.wait(
        lambda frame: (
            None
            if (row := frame.row(scenario_path(name))) is not None
            and row.text.endswith(suffix)
            else f'"{name}" did not end with {suffix!r}'
        ),
    )


@then(parsers.parse('ignored status dims the "{name}" label only'))
def ignored_status_dims_label(grove: GroveDriver, name: str) -> None:
    def mismatch(frame: GroveFrame) -> str | None:
        ignored = frame.row(scenario_path(name))
        root = frame.pane.workspace_root if frame.pane else None
        if ignored is None:
            return f'Grove did not show ignored row "{name}"'
        if root is None:
            return "Grove did not show the Workspace root"
        if not ignored.is_dimmed_at(ignored.label):
            return f'Ignored label "{name}" was not dimmed'
        icon = "" if "" in ignored.text else "󰈙"
        if ignored.is_dimmed_at(icon) or root.is_dimmed_at(root.label):
            return "Ignored dimming leaked beyond the item label"
        return None

    grove.wait(mismatch)


@then(
    parsers.parse(
        'the Workspace icon, "{name}" file icon, and their Unsaved marks keep their foregrounds'
    )
)
def icons_and_unsaved_marks_keep_foregrounds(
    grove: GroveDriver,
    name: str,
) -> None:
    def mismatch(frame: GroveFrame) -> str | None:
        root = frame.pane.workspace_root if frame.pane else None
        row = frame.row(scenario_path(name))
        if root is None:
            return "Grove did not show the Workspace root"
        if row is None:
            return f'Grove did not show status row "{name}"'
        if root.foreground_at("󰙅") != (216, 216, 216):
            return "Git status recolored the Workspace icon"
        if row.foreground_at("󰈙") != (137, 224, 81):
            return f'File icon for "{name}" lost its palette foreground'
        if root.foreground_at("+") != (0, 255, 255):
            return "Git status recolored the Workspace Unsaved mark"
        if row.foreground_at("+") != (0, 255, 255):
            return f'Git status recolored the "{name}" Unsaved mark'
        return None

    grove.wait(mismatch)


@then(
    parsers.re(
        r'^the Cursor "(?P<name>.+)" row background '
        r"spans its icon, label, and Unsaved mark$"
    )
)
def selected_background_spans_row(
    grove: GroveDriver,
    name: str,
) -> None:
    markers = ("󰈙", PurePath(name).name, "+")
    grove.wait(
        lambda frame: (
            None
            if (row := frame.row(scenario_path(name))) is not None
            and _has_background(row, markers, (48, 48, 48))
            else f'Cursor background did not span the whole "{name}" row'
        ),
    )


@then(
    parsers.re(
        r'^the ignored "(?P<name>.+)" label stays dimmed on the '
        r"Cursor row background$"
    )
)
def ignored_dimming_composes_with_selected_background(
    grove: GroveDriver,
    name: str,
) -> None:
    def mismatch(frame: GroveFrame) -> str | None:
        row = frame.row(scenario_path(name))
        if row is None:
            return f'Grove did not show ignored row "{name}"'
        if "󰈙" not in row.text:
            return f'Ignored row "{name}" did not show its file icon'
        if "+" not in row.text:
            return f'Ignored row "{name}" did not show its Unsaved mark'
        if not row.is_dimmed_at(row.label):
            return "Ignored item label was not dimmed"
        if row.is_dimmed_at("󰈙") or row.is_dimmed_at("+"):
            return "Ignored dimming leaked to the icon or Unsaved mark"
        if not _has_background(
            row,
            ("󰈙", row.label, "+"),
            (48, 48, 48),
        ):
            return "Selected background did not span the ignored row"
        return None

    grove.wait(mismatch)


@then(parsers.parse('the Pinned "{name}" row keeps ordinary status layers'))
def pinned_row_keeps_ordinary_status_layers(grove: GroveDriver, name: str) -> None:
    grove.wait(
        lambda frame: (
            None
            if (row := frame.row(scenario_path(name))) is not None
            and "▾" in row.text
            and "" in row.text
            and "+" in row.text
            and row.foreground_at(row.label) == (255, 255, 0)
            and row.foreground_at("+") == (0, 255, 255)
            and _has_background(row, ("", row.label, "+"), (48, 48, 48))
            else f'Pinned row "{name}" lost ordinary status layers'
        ),
    )


@then(
    parsers.parse(
        'the Pinned "{name}" row keeps its background while its label is dimmed'
    )
)
def pinned_background_composes_with_ignored_dimming(
    grove: GroveDriver,
    name: str,
) -> None:
    grove.wait(
        lambda frame: (
            None
            if (row := frame.row(scenario_path(name))) is not None
            and "▾" in row.text
            and "" in row.text
            and row.is_dimmed_at(row.label)
            and not row.is_dimmed_at("")
            and not row.is_dimmed_at("▾")
            and _has_background(row, ("▾", "", row.label), (32, 32, 32))
            else f'Pinned row "{name}" lost its background or ignored dimming'
        ),
    )
