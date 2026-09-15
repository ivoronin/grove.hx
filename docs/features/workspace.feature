Feature: Follow Helix's current Workspace

  Scenario: Replace the Workspace and rebuild its File tree
    Given a Workspace named "first" containing entries
      | path    |
      | old.txt |
    And "old.txt" is Active in Workspace "first"
    And a Workspace named "second" containing entries
      | kind | path             | count |
      | file | aaa-scanned.txt  |       |
      | file | entry-{:04d}.txt | 8000  |
    When Helix starts with Grove in Workspace "first"
    And Helix runs "cd" for Workspace "second"
    Then the File tree root is "second"
    And the File tree shows "aaa-scanned.txt"
    But the File tree does not show "old.txt"

  Scenario: Scope Git status to the current Workspace
    Given a Workspace named "first" containing entries
      | path       |
      | shared.txt |
    And "shared.txt" is Active in Workspace "first"
    And Git tracks "shared.txt" as modified in Workspace "first"
    And a Workspace named "second" containing entries
      | path       |
      | shared.txt |
    And Git tracks "shared.txt" as clean in Workspace "second"
    When Helix starts with Grove in Workspace "first"
    Then "shared.txt" uses the modified Git foreground
    When Helix runs "cd" for Workspace "second"
    Then the File tree root is "second"
    And "shared.txt" uses the theme text foreground

  Scenario: Replace the Workspace with push-directory and return with pop-directory
    Given a Workspace named "first" containing entries
      | path    |
      | old.txt |
    And "old.txt" is Active in Workspace "first"
    And a Workspace named "second" containing entries
      | path    |
      | new.txt |
    When Helix starts with Grove in Workspace "first"
    And Helix runs "push-directory" for Workspace "second"
    Then the File tree root is "second"
    And the File tree shows "new.txt"
    But the File tree does not show "old.txt"
    When Helix runs "pop-directory" for Workspace "first"
    Then the File tree root is "first"
    And the File tree shows "old.txt"
    But the File tree does not show "new.txt"

  Scenario: Start a fresh File tree session after returning
    Given a Workspace named "first" containing entries
      | kind      | path                    | count |
      | file      | anchor.txt              |       |
      | directory | expanded-dir            |       |
      | file      | expanded-dir/inside.txt |       |
      | file      | tail-{:02d}.txt          | 40    |
    And "anchor.txt" is Active in Workspace "first"
    And a Workspace named "second" containing entries
      | path    |
      | new.txt |
    When Helix starts with Grove in Workspace "first"
    And the "expanded-dir" directory is expanded
    And the terminal height becomes 8 rows
    And the Wheel scrolls down 20 times over Grove
    Then the File tree ends with "tail-39.txt"
    When Helix runs "cd" for Workspace "second"
    Then the File tree root is "second"
    When Helix runs "cd" for Workspace "first"
    Then "expanded-dir" remains collapsed
    And Pane row 2 is "expanded-dir"
