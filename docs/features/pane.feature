Feature: Size and place the Pane

  Scenario: Show the Pane only while Grove is focused
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
    Then Grove is Docked on the "left" at width 32
    And "anchor.txt" has Cursor
    When Grove receives "Escape"
    Then Grove yields the whole terminal to Helix
    When Grove is focused
    Then Grove is Docked on the "left" at width 32
    And "anchor.txt" has Cursor

  Scenario: Toggle Visibility between focused and always
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting    | value   |
      | visibility | focused |
    When Helix starts with Grove in that Workspace
    Then Grove yields the whole terminal to Helix
    When Grove Visibility is toggled
    Then Grove is Docked on the "left" at width 32
    And "anchor.txt" has no Cursor mark
    When Grove Visibility is toggled
    Then Grove yields the whole terminal to Helix
    When Grove Visibility is toggled
    Then Grove is Docked on the "left" at width 32
    And "anchor.txt" has no Cursor mark

  Scenario Outline: Start on either side at an explicit width
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting | value   |
      | side    | <side>  |
      | width   | <width> |
    When Helix starts with Grove in that Workspace
    Then Grove is Docked on the "<side>" at width <width>

    Examples:
      | side  | width |
      | left  | 16    |
      | right | 64    |

  Scenario Outline: Resize by one column with the keyboard
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting | value     |
      | side    | left      |
      | width   | <initial> |
    When Helix starts with Grove in that Workspace
    And the terminal width becomes <terminal> columns
    And Grove is focused
    And Grove receives "<key>"
    Then Grove has width <expected>
    When the terminal width becomes <after> columns
    Then Grove has width <expected>

    Examples:
      | initial | terminal | key | expected | after |
      | 24      | 100      | +   | 25       | 100   |
      | 24      | 100      | -   | 23       | 100   |
      | 16      | 100      | -   | 16       | 100   |
      | 64      | 100      | +   | 64       | 100   |
      | 24      | 25       | +   | 24       | 26    |

  Scenario Outline: Resize from the Rail on either side
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting | value  |
      | side    | <side> |
      | width   | 24     |
    When Helix starts with Grove in that Workspace
    And the terminal width becomes <terminal> columns
    And the "<side>" Rail is dragged toward width <requested>
    Then Grove is Docked on the "<side>" at width <expected>

    Examples:
      | side  | terminal | requested | expected |
      | left  | 100      | 1         | 16       |
      | right | 100      | 80        | 64       |
      | left  | 40       | 64        | 39       |

  Scenario: Retain adjusted width across Workspace replacement
    Given a Workspace named "first" containing entries
      | kind      | path                    |
      | file      | anchor.txt              |
      | directory | expanded-dir            |
      | file      | expanded-dir/inside.txt |
    And "anchor.txt" is Active in Workspace "first"
    And a Workspace named "second workspace" containing entries
      | path    |
      | new.txt |
    When Helix starts with Grove in Workspace "first"
    And the "left" Rail is dragged toward width 30
    Then Grove is Docked on the "left" at width 30
    When Helix runs "push-directory" for Workspace "second workspace"
    Then the File tree root is "second workspace"
    When Helix runs "cd" for Workspace "first"
    Then the File tree root is "first"
    And Grove has width 30

  Scenario Outline: Yield to terminal pressure and return intact
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    And Grove settings
      | setting | value  |
      | side    | <side> |
      | width   | 30     |
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And the terminal width becomes 31 columns
    Then Grove is Docked on the "<side>" at width 30
    When the terminal width becomes 30 columns
    Then Grove yields the whole terminal to Helix
    When the terminal width becomes 100 columns
    Then Grove is Docked on the "<side>" at width 30
    And "anchor.txt" has no Cursor mark
    When Grove is focused
    Then "anchor.txt" has Cursor

    Examples:
      | side  |
      | left  |
      | right |
