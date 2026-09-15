Feature: Navigate the File tree with the keyboard

  Scenario: Leave editor movement to Helix while Grove is unfocused
    Given a Workspace containing entries
      | kind | path       | lines |
      | file | active.txt | 100   |
      | file | other.txt  | 100   |
    And "active.txt" is Active
    When Helix starts with Grove in that Workspace
    And the editor receives "j" while Grove is unfocused
    Then the editor cursor is on line 2
    When Grove is focused
    And Grove receives "Enter"
    Then Helix shows the "active.txt" document

  Scenario Outline: Refuse Workspace-root actions and reveal the Cursor
    Given a Workspace containing entries
      | kind | path            | count |
      | file | item-{:02d}.txt | 40    |
    And an Active file outside the Workspace
    When Helix starts with Grove in that Workspace
    And the terminal height becomes 8 rows
    And Grove is focused
    Then "Workspace root" has Cursor
    When the Wheel scrolls down 20 times over Grove
    Then the File tree does not show "item-00.txt"
    When Grove receives "<key>"
    Then the editor still shows the outside file
    And the File tree shows "item-00.txt"
    And "Workspace root" has Cursor
    When Grove receives "Down"
    And Grove receives "Enter"
    Then Helix shows the "item-00.txt" document

    Examples:
      | key   |
      | Enter |
      | Left  |
      | Right |
      | r     |
      | d     |

  Scenario: Keep Cursor independent from Helix's Active file
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
      | target.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove ready for an Active file change to "target.txt"
    And Grove is focused
    Then "anchor.txt" has Cursor
    When Helix changes the Active file to "target.txt"
    Then Helix shows the "target.txt" document
    When Grove receives "Enter"
    Then Helix shows the "anchor.txt" document

  Scenario: Pass an unbound key to Helix
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
      | target.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives Helix's file-picker chord and searches for "target"
    Then Helix shows the "target.txt" document

  Scenario Outline: Pass modified plain keys to Helix
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "<key>"
    Then Helix receives the modified key
    And "anchor.txt" has no Cursor mark

    Examples:
      | key    |
      | Ctrl-n |
      | Ctrl-r |
      | Ctrl-d |
      | Ctrl-j |
      | Ctrl-y |

  Scenario Outline: Move Cursor down and clamp at the File tree end
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
      | target.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "<key>"
    And Grove receives "<key>"
    Then Helix shows the "anchor.txt" document
    When Grove receives "Enter"
    Then Helix shows the "target.txt" document

    Examples:
      | key  |
      | Down |
      | j    |

  Scenario Outline: Move Cursor up and clamp at the File tree start
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
      | target.txt |
    And "target.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "<key>"
    And Grove receives "<key>"
    Then Helix shows the "target.txt" document
    When Grove receives "Down"
    And Grove receives "Enter"
    And the editor inserts "start-" and saves
    Then the content of "anchor.txt" starts with "start-"

    Examples:
      | key |
      | Up  |
      | k   |

  Scenario: Clamp page movement at the File tree end
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
      | target.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "PageDown"
    And Grove receives "Enter"
    Then Helix shows the "target.txt" document

  Scenario Outline: Move Cursor down by the visible Grove height
    Given a Workspace containing entries
      | kind | path            | count |
      | file | anchor.txt      |       |
      | file | page-{:02d}.txt | 40    |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And the terminal height becomes <height> rows
    And Grove is focused
    And Grove receives "PageDown"
    Then Helix shows the "anchor.txt" document
    When Grove receives "Enter"
    Then Helix shows the "<expected>" document

    Examples:
      | height | expected    |
      | 20     | page-19.txt |
      | 30     | page-29.txt |

  Scenario: Clamp page movement at the File tree start
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
      | target.txt |
    And "target.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "PageUp"
    Then Helix shows the "target.txt" document
    When Grove receives "Down"
    And Grove receives "Enter"
    And the editor inserts "paged-" and saves
    Then the content of "anchor.txt" starts with "paged-"

  Scenario Outline: Move Cursor up by ordinary capacity
    Given a Workspace containing entries
      | kind | path            | count |
      | file | anchor.txt      |       |
      | file | page-{:02d}.txt | 40    |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And the terminal height becomes <height> rows
    And Grove is focused
    And Grove receives Helix's file-picker chord and searches for "page-39"
    And Grove is focused
    And Grove receives "PageUp"
    Then Helix shows the "page-39.txt" document
    When Grove receives "Enter"
    Then Helix shows the "<expected>" document

    Examples:
      | height | expected    |
      | 20     | page-20.txt |
      | 30     | page-10.txt |

  Scenario Outline: Expand and collapse a directory with the keyboard
    Given a Workspace containing entries
      | kind      | path              |
      | file      | anchor.txt        |
      | directory | folder            |
      | file      | folder/inside.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "<expand>"
    Then the File tree shows "folder/inside.txt"
    And "folder" has Cursor
    When Grove receives "<collapse>"
    Then the File tree does not show "folder/inside.txt"
    And "folder" has Cursor

    Examples:
      | expand | collapse |
      | Right  | Left     |
      | l      | h        |
      | Enter  | Enter    |

  Scenario: Leave a collapsed directory unchanged with Left
    Given a Workspace containing entries
      | kind      | path              |
      | file      | anchor.txt        |
      | directory | folder            |
      | file      | folder/inside.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "Right"
    Then the File tree shows "folder/inside.txt"
    When Grove receives "Left"
    And Grove receives "Left"
    Then the File tree does not show "folder/inside.txt"
    And "folder" has Cursor

  Scenario: Return control to Helix with Escape
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Escape"
    And the editor inserts "escaped-" and saves
    Then the content of "anchor.txt" starts with "escaped-"

  Scenario: Keep a surviving Cursor on the same file after refresh
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
      | target.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Down"
    And "aardvark.txt" is created
    Then the File tree shows "aardvark.txt"
    When Grove receives "Enter"
    Then Helix shows the "target.txt" document

  Scenario: Reset a missing Cursor to the Workspace root after refresh
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
      | target.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Down"
    And "target.txt" is deleted
    Then the File tree does not show "target.txt"
    When Grove receives "Down"
    And Grove receives "Enter"
    And the editor inserts "reset-" and saves
    Then the content of "anchor.txt" starts with "reset-"
