# Use the Elm Architecture

Grove uses the Elm Architecture so one Model remains the authoritative semantic
state. Adapters decode raw keys, pointer events, coordinates, and Host callback
payloads, then call named Model transitions. Each transition purely returns the
next Model and an optional Command.

The Helix adapter has one commit path. It installs the next Model before it
performs the Command. When the Model stops requesting presentation, commit
first releases the Pane: remove its clip, forget its rendered frame, and cancel
its active gesture. Event and callback commits request a redraw only when the
presentation request changes.

The `open-file` Command is the only Host effect that returns keyboard control
to an Editor view. Its Model transition removes Cursor before returning the
Command. Renaming an active document and closing affected buffers are file
transaction reconciliation, not control transfer.

A deferred completion carries the Workspace root where its work started and
re-enters through a named Model transition. The Model ignores the completion
after the Workspace root changes. Focus and geometry transitions committed
during rendering are command-free because the active frame applies their new
presentation directly.

Adapters keep runtime state outside Model. Values derived only from Model are
not stored as independent state. The latest rendered frame is valid for pointer
input only while its Workspace root matches the current Model. Releasing the
Pane also invalidates this frame, so pointer input maps only to what the user
saw.
