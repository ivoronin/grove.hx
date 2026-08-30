Feature: Start Grove

  Scenario: Start in an empty Workspace
    Given a Workspace containing entries
      | path |
    When Helix starts with Grove in that Workspace
    Then the File tree shows "Workspace root"
    When Grove is focused
    Then "Workspace root" has Cursor
    When Grove receives "n"
    Then the native prompt is "New file in ./"
    When the prompt receives "first.txt"
    Then "first.txt" exists as an empty file
    And the File tree already shows "first.txt"

  Scenario Outline: Reject invalid Grove settings
    Given Grove settings
      | setting   | value   |
      | <setting> | <value> |
    When Grove startup is attempted
    Then Grove startup reports "<message>"

    Examples:
      | setting    | value       | message                        |
      | side       | middle      | invalid Grove side             |
      | width      | 15          | invalid Grove width            |
      | width      | wide text   | invalid Grove width            |
      | icons      | non-boolean | Grove icons must be a boolean  |
      | guides     | non-boolean | Grove guides must be a boolean |
      | visibility | middle      | invalid Grove visibility       |

  Scenario: Reject a second start
    Given Grove starts twice
    When Grove startup is attempted
    Then Grove startup reports "Grove has already started"

  Scenario Outline: Accept an action before deferred startup completes
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting    | value   |
      | visibility | focused |
    And Grove calls "<action>" during Helix initialization
    When Helix starts with Grove in that Workspace
    Then Grove is Docked on the "left" at width 32
    And "anchor.txt" <cursor>

    Examples:
      | action                    | cursor             |
      | grove-focus!              | has Cursor         |
      | grove-visibility-toggle!  | has no Cursor mark |

  Scenario: Start without an Active file
    Given a Workspace containing entries
      | kind | path       |
      | file | anchor.txt |
    When Helix starts with Grove in that Workspace
    Then the File tree shows "anchor.txt"
    When the editor receives "i" while Grove is unfocused
    Then the active Editor view is in Insert mode

  Scenario: Start Docked without taking editor focus
    Given a Workspace containing entries
      | kind      | path              |
      | file      | anchor.txt        |
      | directory | folder            |
      | file      | folder/inside.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    Then the File tree shows "anchor.txt"
    When the editor receives "i" while Grove is unfocused
    Then the active Editor view is in Insert mode

  Scenario: Exit with Grove running
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    When Helix starts with Grove in that Workspace
    And Helix exits
    Then Helix exits normally
