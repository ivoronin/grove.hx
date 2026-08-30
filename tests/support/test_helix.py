from pathlib import Path

from libtmux.server import Server

from tests.support.helix import HelixFrame, HelixSandbox
from tests.support.tui import TerminalFrame


def _frame(*lines: str) -> HelixFrame:
    return HelixFrame.decode(TerminalFrame.decode(100, len(lines), lines))


def test_helix_frame_decodes_vertical_editor_views() -> None:
    frame = _frame(
        f"{'left-001':36}│{'right-001':63}",
        f"{'left.txt ¦ 1 sel ¦ 1:1':36}│{'right.txt ¦ 1 sel GNR ¦ 2:1':63}",
    )

    left = frame.view("left.txt")
    right = frame.view("right.txt")

    assert len(frame.views) == 2
    assert frame.document == "right.txt"
    assert left is not None
    assert right is not None
    assert left.column_bounds == (0, 36)
    assert right.column_bounds == (37, 100)
    assert right.cursor == (2, 1)


def test_helix_frame_restores_only_one_omitted_trailing_cell() -> None:
    frame = _frame(f"{'right.txt ¦ 1 sel GNR ¦ 1:1':67}")

    view = frame.active_view

    assert view is not None
    assert view.column_bounds == (0, 68)


def test_helix_frame_ignores_a_partial_status_line() -> None:
    frame = _frame("anchor.txt ¦ 1 sel")

    assert frame.mode is None
    assert frame.views == ()


def test_helix_sandbox_starts_drives_and_stops_helix(
    server: Server,
    tmp_path: Path,
) -> None:
    document = tmp_path / "document.txt"
    document.write_text("content\n", encoding="utf-8")
    helix = HelixSandbox(tmp_path / "sandbox").start(
        server,
        cwd=tmp_path,
        documents=(document,),
    )
    try:
        assert helix.capture().document == "document.txt"
        helix.command("write")
        helix.hold(
            lambda frame: None if frame.mode == "Normal" else "Helix is not Normal"
        )
        helix.quit()
        assert helix.wait_for_exit() == 0
    finally:
        helix.close()
