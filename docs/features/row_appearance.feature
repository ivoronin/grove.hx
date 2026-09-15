Feature: Present File tree rows

  Scenario: Choose icons and indentation from entry kind
    Given a Workspace containing entries
      | kind      | path              |
      | file      | anchor.txt        |
      | directory | folder            |
      | file      | folder/inside.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    Then the Workspace root uses one File tree icon
    And "folder" uses the directory icon
    And "anchor.txt" uses the file icon
    And "anchor.txt" aligns with "folder" in icon mode
    And the Workspace label starts in column 4 and "folder" and "anchor.txt" labels start in column 6
    And "folder" can expand
    When the "folder" directory is expanded
    Then "folder/inside.txt" is indented two columns from "folder"

  Scenario: Show Guides
    Given a Workspace containing entries
      | kind      | path                   |
      | file      | anchor.txt             |
      | directory | outer                  |
      | directory | outer/inner            |
      | file      | outer/inner/inside.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    Then the Workspace root has neither an Ancestor trace nor a Leaf mark
    And "anchor.txt" uses 0 Ancestor traces
    And "anchor.txt" uses 0 Leaf marks
    And "anchor.txt" uses the Active file mark
    And "anchor.txt" uses the file icon
    When the "outer" directory is expanded
    And the "outer/inner" directory is expanded
    Then "outer/inner" uses 1 Ancestor trace
    And "outer/inner/inside.txt" uses 2 Ancestor traces
    And "outer/inner/inside.txt" uses 1 Leaf mark
    And the Ancestor traces and Leaf mark on "outer/inner/inside.txt" use the theme Guides foreground

  Scenario: Disable guides
    Given a Workspace containing entries
      | kind      | path             |
      | file      | anchor.txt       |
      | directory | outer            |
      | file      | outer/inside.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting | value    |
      | side    | left     |
      | width   | 24       |
      | icons   | disabled |
      | guides  | disabled |
    When Helix starts with Grove in that Workspace
    Then "anchor.txt" uses 0 Leaf marks
    And "anchor.txt" uses the Active file mark
    When the "outer" directory is expanded
    Then "outer/inside.txt" uses 0 Ancestor traces
    And "outer/inside.txt" uses 0 Leaf marks

  Scenario: Present Cursor and Active file marks without shifting rows
    Given a Workspace containing entries
      | path       |
      | active.txt |
      | plain.txt  |
    And "active.txt" is Active
    And Git reports statuses
      | path       | status   |
      | active.txt | modified |
    When Helix starts with Grove in that Workspace
    Then "active.txt" uses the Active file mark
    And "active.txt" uses the modified Git foreground
    And "active.txt" has no Cursor mark
    And "plain.txt" has no Cursor mark
    When Grove is focused
    Then "active.txt" uses the Cursor mark in the first cell
    And "active.txt" keeps the Active file mark
    And the Cursor mark uses the Cursor row colors
    And the Active file mark uses the theme info foreground and Cursor row background
    And "plain.txt" has no Cursor mark
    And "active.txt" aligns with "plain.txt" in icon mode

  Scenario: Present an unreadable directory as failed
    Given a Workspace containing entries
      | kind      | path              |
      | file      | anchor.txt        |
      | directory | locked            |
      | file      | locked/inside.txt |
    And "anchor.txt" is Active
    And Git reports statuses
      | path              | status   |
      | anchor.txt        | modified |
      | locked/inside.txt | modified |
    When Helix starts with Grove in that Workspace
    Then "locked" uses the modified Git foreground
    And "anchor.txt" uses the modified Git foreground
    When the "locked" directory is expanded
    Then the File tree shows "locked/inside.txt"
    When "locked" becomes unreadable
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "Enter"
    And Grove receives "Enter"
    Then "locked" uses the unreadable-directory icon and error foreground

  Scenario: Align rows with icons disabled
    Given a Workspace containing entries
      | kind      | path              |
      | file      | anchor.txt        |
      | directory | folder            |
      | file      | folder/inside.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting | value    |
      | side    | left     |
      | width   | 24       |
      | icons   | disabled |
    When Helix starts with Grove in that Workspace
    Then "folder" can expand
    And Workspace, "folder", and "anchor.txt" labels occupy reclaimed icon columns
    And "anchor.txt" uses the Active file mark
