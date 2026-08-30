# Grove

## Language

**Workspace**:
Grove's current filesystem knowledge of the Workspace selected from Helix's
current working directory: its root identity and current File tree. It owns
filesystem truth only. Git state and Grove interaction are owned separately.
_Avoid_: Project, Tree model, provider state, project pane

**Observation snapshot**:
One atomic external observation of Workspace root, File tree, Git status, and
Active file. Every field belongs to the same Workspace root. The snapshot is a
Model transition payload, not a state owner.
_Avoid_: Workspace snapshot, application snapshot

**Model**:
Grove's one authoritative state at an instant. It owns observed Workspace, Git,
and Host facts together with persistent Grove interaction state. Visible rows
and resolved Layout are pure projections, not separate state owners.
_Avoid_: Application state, pane model, presentation model

**Active file**:
The Workspace file in Helix's active editor split. Only Host observation changes
it; an open command never predicts it. Regular refresh does not expand
or scan through collapsed ancestors only to follow it. Focusing Grove takes a
complete observation, scans the Active file path, then expands and reveals it
when Pane is available. When Visible, the Active file mark identifies it while
its background can follow the active Helix theme. Normal activation only returns
control to Helix, preserving the editor cursor and viewport. Split activation
still opens the requested split.
_Avoid_: Cursor, selected row

**Editor view**:
One Helix editor split. Its rendered document, cursor, and viewport are Host
Context that Grove may observe but does not own.
_Avoid_: Pane, Active file, Grove view

**Cursor**:
The Grove tree row targeted by keyboard navigation and row actions. It exists
only while Grove is focused, begins on the Active file when possible, and
otherwise begins on the Workspace root. The Cursor mark identifies it. Cursor
disappears after file activation, Escape, an outside click, or the first key
Grove does not bind. An unbound key is passed to Helix after Cursor disappears.
A present Unsaved mark preserves Cursor emphasis. A refreshed File tree keeps
the Cursor on the same row when it survives and resets it to the Workspace root
when it does not. Pane unavailability removes Cursor; restoring terminal space
does not restore focus.
_Avoid_: Active file, current file

**Workspace session**:
The expansion, optional Cursor, and Scroll anchor retained for the current
Workspace. Changing Helix's current directory replaces the session when it
changes the Workspace root. Collapsing a directory also clears expansion for
every descendant. Grove width is retained independently across roots.
_Avoid_: Interaction state, persisted settings

**Scroll anchor**:
The Visible row intended to be the first ordinary row in Layout. It preserves a
semantic viewport position across File tree and Host geometry changes.
_Avoid_: Numeric viewport offset, Viewport intent, Cursor

**Pane**:
Grove's visible docked region: File tree rows plus the permanent Rail. It is
presentation geometry, not a state owner or a separate Helix pane.
_Avoid_: Runtime pane, pane model, interaction state

**Visibility**:
The policy that controls when Grove presents an available Pane. `always` keeps
the Pane visible. `focused` presents it only while Grove owns Cursor. Toggling
Visibility changes the policy for the current Helix process without changing
the Workspace session, side, or requested width.
_Avoid_: Hidden flag, show state, Pane availability

**Host geometry**:
The latest component rectangle reported by Helix at the start of rendering.
Model stores this observation. Layout combines it with requested width and side
to derive Pane bounds, Pane availability, ordinary capacity, and Rail geometry.
_Avoid_: Pane geometry, viewport geometry

**Rail**:
The permanent editor-facing column of Grove. Its track separates Grove from the
editor, its optional thumb represents the viewport, and horizontal dragging
resizes Grove.
_Avoid_: Separator, scrollbar column

**Theme role**:
A named visual part of Grove. Its documented colors can follow a Helix theme
key or use fixed colors.
_Avoid_: Style role, theme slot

**File tree**:
One immutable ordered filesystem hierarchy containing the entries currently
known to Grove from the latest Observation snapshot. Its Workspace root is a
separate identity. Collapse does not edit this hierarchy. Expansion controls
which known descendants become Visible rows; a later observation may replace
the hierarchy with a scan that did not traverse a collapsed directory.
_Avoid_: Tree state, session

**Unreadable directory**:
A directory present in the File tree whose contents Grove could not read. It
remains expandable and has a distinct error presentation. An Unreadable
Workspace root has the same failure presentation but cannot expand.
_Avoid_: Failed entry, unavailable subtree, inert directory

**Unfollowed directory link**:
A symbolic link whose target is a directory. Grove deliberately does not
traverse it. It remains visible but cannot expand.
_Avoid_: Symlink folder, inert directory, broken directory

**File link**:
A symbolic link whose target is a regular file. Grove opens it like a regular
file.
_Avoid_: Symlink file, linked entry

**Broken link**:
A symbolic link whose target is missing, unreadable, or unsupported. Grove
keeps it visible but inert, with a distinct error presentation.
_Avoid_: Inert symlink, unknown entry

**Git status**:
Grove's latest optional Git state for paths in the current Workspace. File names
use the status foreground directly. Directory names use the strongest status
beneath their path, including collapsed descendants, in this order: conflict,
deleted, modified, created. Ignored status dims only the exact entry label. Git
status never controls the File tree or recolors entry icons and Unsaved marks.
Cursor styling keeps the Git foreground while applying its row background. Git
status is scoped to the Workspace.
_Avoid_: Git overlay, Git snapshot, Git truth, Git mark

**Unsaved status**:
The distinction between a file with unsaved edits (`unsaved`) and a directory
or Workspace root containing such a file (`unsaved-ancestor`). Files outside
the current Workspace give neither status.
_Avoid_: Dirty flag, Buffer status

**Unsaved mark**:
The single trailing `+` presenting either Unsaved status. It appears on
collapsed directories and the Workspace root, and never becomes a count.
_Avoid_: Buffer overlay, Buffer mark, dirty count

**Cursor mark**:
The single leading `>` presenting Cursor on a Visible row. Every row reserves
its position so the mark never shifts File tree content.
_Avoid_: Cursor prefix, selection arrow

**Active file mark**:
The single `*` presenting the Active file when it is Visible. It occupies the
Leaf mark position and remains visible when Guides are disabled.
_Avoid_: Current buffer flag, Active marker

**Guides**:
The visual cues before File tree labels that expose ancestry and expansion
capability. Ancestor traces follow non-root directories through nested rows;
Leaf marks identify non-root rows that cannot expand. Cursor and Active file
marks are independent of Guides.
_Avoid_: Decoration, Hierarchy decoration

**Ancestor trace**:
The muted vertical stroke representing one non-root ancestor directory of a
Visible row. The Workspace root contributes none.
_Avoid_: Hierarchy guide, Indent guide, Folder level line, tree branch

**Leaf mark**:
The single leading `·` identifying a non-root Visible row without an expansion
control. It occupies that control's position without replacing the entry icon;
the Active file mark replaces it when both apply.
_Avoid_: File dot, bullet

**Visible row**:
One semantic filesystem entry in the current File tree. Its stable identity
drives navigation. Its identity is the exact Workspace-relative path within the
current Workspace session. The Workspace root uses the empty relative path.
Recreating an entry at the same path preserves that row identity. Grove creates
an absolute path only when it sends a Host command.
_Avoid_: Rendered line, row index

**Pinned ancestor row**:
The presentation of an expanded ancestor directory held above scrolling Visible
rows to keep the current hierarchy legible.
_Avoid_: Sticky row, pinned folder, folder header

**Ancestor stack**:
The outermost ordered prefix of Pinned ancestor rows shown above scrolling File
tree content.
_Avoid_: Folder stacking, sticky headers, breadcrumb
