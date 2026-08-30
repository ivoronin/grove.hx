Feature: Manage Workspace files

  Scenario: Create a file inside a directory
    Given a Workspace containing entries
      | kind      | path            |
      | directory | docs            |
      | file      | docs/anchor.txt |
    And "docs/anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "n"
    Then the native prompt is "New file in docs/"
    When the prompt receives "new.txt"
    Then "docs/new.txt" exists as an empty file
    And the File tree already shows "docs/new.txt"
    And Helix shows the "docs/new.txt" document
    When the editor receives "i" while Grove is unfocused
    Then the active Editor view is in Insert mode

  Scenario: Reclaim editor space before opening a created file
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting    | value   |
      | visibility | focused |
    When Helix starts with Grove in that Workspace
    Then Grove yields the whole terminal to Helix
    When Grove is focused
    And Grove receives "n"
    Then the native prompt is "New file in ./"
    When the prompt receives "new.txt"
    Then Grove yields the whole terminal to Helix
    And Helix shows the "new.txt" document

  Scenario: Create a directory beside a file
    Given a Workspace containing entries
      | kind | path       |
      | file | anchor.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "N"
    Then the native prompt is "New directory in ./"
    When the prompt receives "generated"
    Then "generated" exists as a directory
    And the File tree already shows "generated"
    And "anchor.txt" has Cursor

  Scenario: Treat an unfollowed directory link as a leaf
    Given a Workspace containing entries
      | kind                       | path                | target   |
      | directory                  | a-target            |          |
      | file                       | a-target/inside.txt |          |
      | unfollowed directory link  | z-link              | a-target |
      | file                       | anchor.txt          |          |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "n"
    Then the native prompt is "New file in ./"
    When the prompt receives "sibling.txt"
    Then "sibling.txt" exists as an empty file
    And "a-target/sibling.txt" does not exist
    When Grove is focused
    And Grove receives "Up"
    And Grove receives "Up"
    And Grove receives "d"
    Then Helix shows the message "Permanently delete z-link? y to confirm"
    When Grove receives "y"
    Then "z-link" no longer exists
    And "a-target" still exists
    And "a-target/inside.txt" still exists

  Scenario: Rename a directory and close its clean buffers
    Given a Workspace containing entries
      | kind      | path               |
      | file      | anchor.txt         |
      | directory | old                |
      | file      | old/background.txt |
      | directory | archive            |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Helix opens "old/background.txt"
    And Helix opens "anchor.txt"
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "r"
    Then the native prompt is "Rename or move old to"
    When the prompt receives "archive/new"
    Then "old" no longer exists and "archive/new" exists
    And the File tree already does not show "old"
    And "Workspace root" has Cursor
    When the "archive" directory is expanded
    Then the File tree already shows "archive/new"
    When Grove receives "Escape"
    Then the old "old/background.txt" buffer is closed
    And Helix shows the "anchor.txt" document

  Scenario: Rename a dirty Active file through Helix
    Given a Workspace containing entries
      | kind | path       |
      | file | anchor.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And the editor inserts "dirty-" without saving and returns to Normal mode
    And Grove is focused
    And Grove receives "r"
    Then the native prompt is "Rename or move anchor.txt to"
    When the prompt receives "active-new.txt"
    Then "anchor.txt" no longer exists and "active-new.txt" exists
    And the File tree already does not show "anchor.txt"
    And the File tree already shows "active-new.txt"
    And Helix shows the "active-new.txt" document
    And the editor contains "dirty-"

  Scenario: Cancel and confirm file-link deletion
    Given a Workspace containing entries
      | kind      | path       | target     |
      | file      | anchor.txt |            |
      | file      | target.txt |            |
      | file link | link.txt   | target.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Down"
    And Grove receives "d"
    Then Helix shows the message "Permanently delete link.txt? y to confirm"
    When Grove receives "Ctrl-y"
    Then "link.txt" still exists
    And "link.txt" has Cursor
    When Grove receives "d"
    Then Helix shows the message "Permanently delete link.txt? y to confirm"
    When Grove receives "x"
    Then "link.txt" still exists
    And "link.txt" has Cursor
    When Grove receives "d"
    Then Helix shows the message "Permanently delete link.txt? y to confirm"
    When the editor is pressed
    Then "link.txt" still exists
    And "link.txt" has Cursor
    When Grove receives "d"
    Then Helix shows the message "Permanently delete link.txt? y to confirm"
    When the editor pastes "leaked"
    Then "link.txt" still exists
    And "link.txt" has Cursor
    And the editor does not contain "leaked"
    When Grove receives "d"
    Then Helix shows the message "Permanently delete link.txt? y to confirm" at terminal column 0
    And Helix keeps the message "Permanently delete link.txt? y to confirm" while idle
    When Grove receives "y"
    Then "link.txt" no longer exists
    And the File tree already does not show "link.txt"
    And "target.txt" still exists

  Scenario: Recursively delete a directory and close its clean buffers
    Given a Workspace containing entries
      | kind      | path                |
      | file      | anchor.txt          |
      | directory | docs                |
      | file      | docs/active.txt     |
      | file      | docs/background.txt |
    And "docs/active.txt" is Active
    When Helix starts with Grove in that Workspace
    And Helix opens "anchor.txt"
    And Helix opens "docs/background.txt"
    And Helix opens "docs/active.txt"
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "d"
    Then Helix shows the message "Permanently delete docs/ recursively? y to confirm"
    When Grove receives "y"
    Then "docs" no longer exists
    And the File tree already does not show "docs"
    And "Workspace root" has Cursor
    When Grove receives "Escape"
    Then the old "docs/background.txt" buffer is closed
    And the old "docs/active.txt" buffer is closed
    And Helix closed "docs/background.txt" before "docs/active.txt"
    And Helix shows the "anchor.txt" document

  Scenario: Refuse a dirty Active deletion, then delete after save
    Given a Workspace containing entries
      | kind | path         |
      | file | anchor.txt   |
      | file | fallback.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Helix opens "fallback.txt"
    And Helix opens "anchor.txt"
    And the editor inserts "dirty-" without saving and returns to Normal mode
    And Grove is focused
    And Grove receives "d"
    Then Helix shows the message "Permanently delete anchor.txt? y to confirm"
    When Grove receives "y"
    Then Helix shows the message "Cannot delete anchor.txt: anchor.txt has"
    And "anchor.txt" still exists
    When Grove receives "Escape"
    And the editor inserts "saved-" and saves
    And Grove is focused
    And Grove receives "d"
    Then Helix shows the message "Permanently delete anchor.txt? y to confirm"
    When Grove receives "y"
    Then "anchor.txt" no longer exists
    And the File tree already does not show "anchor.txt"
    And the old "anchor.txt" buffer is closed
    And Helix shows the "fallback.txt" document
    And "fallback.txt" already uses the Active file mark

  Scenario: Refuse directory deletion when a descendant is dirty
    Given a Workspace containing entries
      | kind | path           |
      | file | anchor.txt     |
      | file | docs/dirty.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Helix opens "docs/dirty.txt"
    And the editor inserts "dirty-" without saving and returns to Normal mode
    And Helix opens "anchor.txt"
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "d"
    Then Helix shows the message "Permanently delete docs/ recursively? y to confirm"
    When Grove receives "y"
    Then Helix shows the message "Cannot delete docs: docs/dirty.txt has unsaved changes"
    And "docs" still exists
    And "docs" has Cursor

  Rule: Protect file creation

    Background:
      Given a Workspace containing entries
        | path            |
        | anchor.txt      |
        | destination.txt |
      And "anchor.txt" is Active
      When Helix starts with Grove in that Workspace
      And the terminal width becomes 140 columns

    Scenario: Keep Cursor when the destination exists
      When Grove is focused
      And Grove receives "n"
      Then the native prompt is "New file in ./"
      When the prompt receives "destination.txt"
      Then Helix shows the message "Cannot create file destination.txt: destination already exists"
      And "anchor.txt" has Cursor

    Scenario: Refuse creation when the destination is open in Helix
      When Helix opens "destination.txt"
      And Helix opens "anchor.txt"
      And Grove is focused
      And Grove receives "n"
      Then the native prompt is "New file in ./"
      When the prompt receives "destination.txt"
      Then Helix shows the message "Cannot create file destination.txt: destination is open in Helix"
      And "anchor.txt" has Cursor

  Rule: Protect source and destination paths

    Background:
      Given a Workspace containing entries
        | kind | path            |
        | file | anchor.txt      |
        | file | destination.txt |
        | file | source.txt      |
      And "anchor.txt" is Active
      When Helix starts with Grove in that Workspace
      And the terminal width becomes 140 columns

    Scenario: Protect a dirty source path
      When Helix opens "source.txt"
      And the editor inserts "dirty-" without saving and returns to Normal mode
      And Helix opens "anchor.txt"
      And Grove is focused
      And Grove receives "PageDown"
      And Grove receives "r"
      Then the native prompt is "Rename or move source.txt to"
      When the prompt receives "renamed.txt"
      Then Helix shows the message "Cannot rename or move source.txt to renamed.txt: source.txt has unsaved changes"
      And "source.txt" still exists
      And "source.txt" has Cursor

    Scenario: Protect an open destination path
      When Helix opens "destination.txt"
      And Helix opens "anchor.txt"
      And Grove is focused
      And Grove receives "PageDown"
      And Grove receives "r"
      Then the native prompt is "Rename or move source.txt to"
      When the prompt receives "destination.txt"
      Then Helix shows the message "Cannot rename or move source.txt to destination.txt: destination is open in Helix"
      And "source.txt" still exists
      And "source.txt" has Cursor

    Scenario: Refuse a closed destination collision
      When Grove is focused
      And Grove receives "PageDown"
      And Grove receives "r"
      Then the native prompt is "Rename or move source.txt to"
      When the prompt receives "destination.txt"
      Then Helix shows the message "Cannot rename or move source.txt to destination.txt: destination already exists"
      And "source.txt" still exists
      And "source.txt" has Cursor

  Rule: Other file mutations

    Scenario: Move an entry outside the Workspace
      Given a Workspace containing entries
        | kind | path       |
        | file | anchor.txt |
        | file | source.txt |
      And "anchor.txt" is Active
      When Helix starts with Grove in that Workspace
      And the terminal width becomes 140 columns
      And Grove is focused
      And Grove receives "Down"
      And Grove receives "r"
      Then the native prompt is "Rename or move source.txt to"
      When the prompt receives "../escaped.txt"
      Then "source.txt" no longer exists and "../escaped.txt" exists
      And the File tree already does not show "source.txt"

    Scenario: Refuse rename after the source disappears
      Given a Workspace containing entries
        | kind | path       |
        | file | anchor.txt |
        | file | source.txt |
      And "anchor.txt" is Active
      When Helix starts with Grove in that Workspace
      And the terminal width becomes 140 columns
      And Grove is focused
      And Grove receives "Down"
      And Grove receives "r"
      Then the native prompt is "Rename or move source.txt to"
      When "source.txt" is deleted
      And the prompt receives "renamed.txt"
      Then Helix shows the message "Cannot rename or move source.txt to renamed.txt: source does not exist"
      And "source.txt" no longer exists
      And "renamed.txt" does not exist

    Scenario: Refuse deletion after the source disappears
      Given a Workspace containing entries
        | path       |
        | anchor.txt |
        | source.txt |
      And "anchor.txt" is Active
      When Helix starts with Grove in that Workspace
      And Grove is focused
      And Grove receives "Down"
      And Grove receives "d"
      Then Helix shows the message "Permanently delete source.txt? y to confirm"
      When "source.txt" is deleted
      And Grove receives "y"
      Then Helix shows the message "Cannot delete source.txt: source does not exist"
      And "source.txt" no longer exists

    Scenario: Report filesystem failure from refreshed truth
      Given a Workspace containing entries
        | kind      | path            |
        | file      | anchor.txt      |
        | directory | docs            |
        | file      | docs/nested.txt |
      And "anchor.txt" is Active
      When Helix starts with Grove in that Workspace
      And Grove is focused
      And Grove receives "Up"
      And Grove receives "r"
      Then the native prompt is "Rename or move docs to"
      When "arrived.txt" is created
      And the prompt receives "docs/inside"
      Then Helix shows the message "Cannot rename or move docs to docs/inside:"
      And the File tree already shows "arrived.txt"
      And "docs" still exists
      And "docs" has Cursor
