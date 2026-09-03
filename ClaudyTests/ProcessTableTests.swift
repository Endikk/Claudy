import XCTest
@testable import Claudy

final class ProcessTableTests: XCTestCase {

    /// Real `ps -Ao pid=,ppid=,lstart=,args=` output, captured on 2026-09-03.
    private let output = """
      46694 46686 Thu Sep  3 19:31:02 2026 /opt/homebrew/bin/python3 -m http.server 4000
      46686  8859 Thu Sep  3 19:31:02 2026 /bin/zsh -c source /Users/x/.claude/shell-snapshots/snap.sh
       8859  6172 Wed Sep  2 09:12:44 2026 /Users/x/.vscode/extensions/anthropic.claude-code-2.1.257-darwin-arm64/resources/native-binary/claude --output-format stream-json
       6172 21476 Wed Sep  2 09:12:40 2026 /Applications/Visual Studio Code.app/Contents/MacOS/Code Helper (Plugin)
      21476     1 Wed Sep  2 09:12:31 2026 /Applications/Visual Studio Code.app/Contents/MacOS/Code
       5771 49296 Thu Sep  3 19:10:26 2026 next-server (v16.2.12)
    """

    func testParsesPidParentAndArguments() {
        let table = ProcessTable.parse(output)
        XCTAssertEqual(table.processes.count, 6)
        XCTAssertEqual(table.processes[46694]?.parent, 46686)
        XCTAssertEqual(table.processes[46694]?.arguments, "/opt/homebrew/bin/python3 -m http.server 4000")
    }

    /// `lstart` is five whitespace-separated tokens with a padded day number; the argument
    /// string starts only after them.
    func testParsesStartDate() {
        let table = ProcessTable.parse(output)
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone.current, from: try! XCTUnwrap(table.processes[46694]?.startedAt)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 3)
        XCTAssertEqual(components.hour, 19)
        XCTAssertEqual(components.minute, 31)
    }

    func testWalksAncestorsUpToTheRoot() {
        let table = ProcessTable.parse(output)
        XCTAssertEqual(table.ancestors(of: 46694).map(\.pid), [46686, 8859, 6172, 21476])
    }

    func testFindsClaudeSessionRoot() {
        let table = ProcessTable.parse(output)
        XCTAssertEqual(table.claudeSessionRoot(of: 46694)?.pid, 8859)
    }

    func testProcessWithoutClaudeAncestorHasNoSessionRoot() {
        let table = ProcessTable.parse(output)
        XCTAssertNil(table.claudeSessionRoot(of: 5771))
    }

    func testRecognisesClaudeBinaryPaths() {
        XCTAssertTrue(ProcessTable.isClaudeBinary("/Users/x/.claude/local/claude"))
        XCTAssertTrue(ProcessTable.isClaudeBinary("/Users/x/.vscode/extensions/anthropic.claude-code-2.1.257/native-binary/claude --debug"))
        XCTAssertTrue(ProcessTable.isClaudeBinary("/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"))
        XCTAssertFalse(ProcessTable.isClaudeBinary("/usr/bin/claudia"))
        XCTAssertFalse(ProcessTable.isClaudeBinary("/bin/zsh -c echo claude"))
    }

    /// A malformed table must not hang the scan.
    func testCyclicParentDoesNotLoop() {
        let cyclic = """
          10 11 Thu Sep  3 19:31:02 2026 /bin/a
          11 10 Thu Sep  3 19:31:02 2026 /bin/b
        """
        XCTAssertLessThan(ProcessTable.parse(cyclic).ancestors(of: 10).count, 70)
    }
}
