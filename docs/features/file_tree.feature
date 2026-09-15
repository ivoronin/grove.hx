Feature: Keep the File tree current

  Scenario: Discover a directory's contents when it expands
    Given a Workspace containing entries
      | kind      | path   |
      | directory | folder |
    When Helix starts with Grove in that Workspace
    And "folder/appeared.txt" is created
    And the "folder" directory is expanded
    Then the File tree shows "folder/appeared.txt"

  Scenario: Forget expanded descendants when their parent closes
    Given a Workspace containing entries
      | path                   |
      | outer/inner/before.txt |
    When Helix starts with Grove in that Workspace
    And the "outer" directory is expanded
    And the "outer/inner" directory is expanded
    And the "outer" directory is collapsed
    And "outer/inner/after.txt" is created
    Then the File tree does not show "outer/inner/after.txt"
    When the "outer" directory is expanded
    Then the File tree does not show "outer/inner/after.txt"
    When the "outer/inner" directory is expanded
    Then the File tree shows "outer/inner/after.txt"

  Scenario: Discover new Workspace entries during refresh
    Given a Workspace containing entries
      | path       |
      | anchor.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And "appeared.txt" is created
    Then the File tree shows "appeared.txt"

  Scenario: Show supported entries without following links
    Given a Workspace containing entries
      | kind                      | path            | target    |
      | file                      | file2.txt       |           |
      | file                      | file02.txt      |           |
      | file                      | file10.txt      |           |
      | file                      | .env            |           |
      | directory                 | adir            |           |
      | directory                 | .git            |           |
      | file                      | .git/hidden.txt |           |
      | file link                 | file-link       | file2.txt |
      | unfollowed directory link | directory-link  | adir      |
      | broken link               | broken-link     | missing   |
      | fifo                      | named-pipe      |           |
    And "file2.txt" is Active
    When Helix starts with Grove in that Workspace
    Then File tree rows appear in order
      | name           |
      | adir           |
      | directory-link |
      | .env           |
      | file2.txt      |
      | file02.txt     |
      | file10.txt     |
      | file-link      |
      | broken-link    |
    And "directory-link" cannot expand
    And "broken-link" cannot expand
    And the File tree does not show ".git"
    And the File tree does not show "named-pipe"
    And "file-link" uses the File link icon
    And "directory-link" uses the directory icon
    And "broken-link" uses the Broken link icon
    And "file-link" uses 1 Leaf mark
    And "directory-link" uses 1 Leaf mark
    And "broken-link" uses 1 Leaf mark

  Scenario: Reclassify a link when its external target appears
    Given a Workspace containing entries
      | kind        | path          | target                |
      | file        | anchor.txt    |                       |
      | broken link | changing-link | ../outside/target.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    Then "changing-link" uses the Broken link icon
    When "../outside/target.txt" appears as a file
    Then "changing-link" uses the File link icon
    When "changing-link" is activated
    Then Helix shows the "changing-link" document

  Scenario: Mark a directory that cannot be read
    Given a Workspace containing entries
      | kind      | path              |
      | file      | anchor.txt        |
      | directory | locked            |
      | file      | locked/hidden.txt |
    And "anchor.txt" is Active
    And "locked" is unreadable
    When Helix starts with Grove in that Workspace
    And Grove is focused
    And Grove receives "Up"
    And Grove receives "Enter"
    Then "locked" remains expanded
    When the editor receives "i" while Grove is unfocused
    Then the active Editor view is in Insert mode

  Scenario: Recover an expanded directory after it becomes readable
    Given a Workspace containing entries
      | kind      | path              |
      | file      | anchor.txt        |
      | directory | locked            |
      | file      | locked/inside.txt |
    And "anchor.txt" is Active
    When Helix starts with Grove in that Workspace
    And the "locked" directory is expanded
    Then the File tree shows "locked/inside.txt"
    When "locked" becomes unreadable
    Then "locked" remains expanded
    And the File tree does not show "locked/inside.txt"
    When "locked" becomes readable
    Then the File tree shows "locked/inside.txt"
