import XCTest
@testable import Claudy

/// Records which environments the scan asked for, to prove the expensive read stays behind the
/// cheap checks.
private final class EnvironmentReads {
    var pids: [pid_t] = []
}

final class McpScannerTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_788_000_000)

    private let claudeEnvironment = ProcessEnvironment.Markers(
        isClaude: true, projectDirectory: "/Users/x/Dev/GoodFood", sessionID: "s-dead"
    )

    private func process(_ pid: pid_t, parent: pid_t, _ arguments: String) -> RunningProcess {
        RunningProcess(pid: pid, parent: parent, startedAt: epoch, arguments: arguments)
    }

    private func table(_ processes: [RunningProcess]) -> ProcessTable {
        ProcessTable(processes: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) }))
    }

    /// A machine where every process is the user's and runs a Homebrew binary, unless told
    /// otherwise.
    private func probe(
        markers: [pid_t: ProcessEnvironment.Markers],
        memory: [pid_t: UInt64] = [:],
        strangers: Set<pid_t> = [],
        executables: [pid_t: String] = [:],
        reads: EnvironmentReads = EnvironmentReads()
    ) -> ProcessProbe {
        ProcessProbe(
            isOwnedByUser: { !strangers.contains($0) },
            executablePath: { executables[$0] ?? "/opt/homebrew/bin/node" },
            markers: { pid in
                reads.pids.append(pid)
                return markers[pid]
            },
            residentBytes: { memory[$0] }
        )
    }

    private func orphans(
        _ processes: [RunningProcess],
        probe: ProcessProbe,
        ports: Set<pid_t> = [],
        liveSessions: Set<String> = []
    ) -> [McpOrphan] {
        McpScanner.orphans(table: table(processes), excluding: ports, probe: probe,
                           liveSessionIDs: { liveSessions })
    }

    // MARK: - The orphan rule

    func testListsAServerWhoseSessionIsGone() {
        let result = orphans(
            [process(4100, parent: 1, "npm exec chrome-devtools-mcp@latest")],
            probe: probe(markers: [4100: claudeEnvironment], memory: [4100: 52 << 20])
        )
        XCTAssertEqual(result, [
            McpOrphan(id: "mcp-4100", pid: 4100, startedAt: epoch, name: "chrome-devtools-mcp",
                      projectName: "GoodFood", residentBytes: 52 << 20),
        ])
    }

    /// The claude-mem worker is reparented to launchd and carries `CLAUDE_PROJECT_DIR`, but it
    /// is a daemon on purpose: nothing in its command line says MCP, so it is never listed.
    func testSkipsTheClaudeMemDaemon() {
        let daemon = process(
            5200, parent: 1,
            "bun /Users/x/.claude/plugins/marketplaces/thedotmack/plugin/scripts/worker-service.cjs --daemon"
        )
        let reads = EnvironmentReads()
        let result = orphans([daemon], probe: probe(markers: [5200: claudeEnvironment], reads: reads))
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(reads.pids.isEmpty)
    }

    /// The claude-mem daemon runs its own `chroma-mcp` and passes it its Claude markers. The
    /// server is not left behind while the daemon that manages it lives: only a process launchd
    /// adopted is.
    func testSkipsAServerADaemonStillManages() {
        let daemonEnvironment = ProcessEnvironment.Markers(isClaude: true, projectDirectory: "/Users/x/Dev/Claudy",
                                                           sessionID: nil)
        let result = orphans(
            [
                process(21077, parent: 1, "/Users/x/.bun/bin/bun /Users/x/.claude/plugins/scripts/worker-service.cjs --daemon"),
                process(21624, parent: 21077, "/opt/homebrew/bin/uv tool uvx --from chroma-mcp==0.2.6 chroma-mcp --client-type persistent"),
                process(21627, parent: 21624, "/Users/x/.cache/uv/bin/python /Users/x/.cache/uv/bin/chroma-mcp"),
            ],
            probe: probe(markers: [21077: daemonEnvironment, 21624: daemonEnvironment, 21627: daemonEnvironment])
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// A session can be alive without being an ancestor of the server it launched. Its id is
    /// then the only thing that says the server is still in use.
    func testSkipsAServerWhoseSessionIsStillLive() {
        let live = ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil, sessionID: "s-live")
        let result = orphans(
            [
                process(4100, parent: 1, "npm exec chrome-devtools-mcp@latest"),
                process(4200, parent: 1, "uvx mcp-server-fetch"),
            ],
            probe: probe(markers: [4100: live, 4200: claudeEnvironment]),
            liveSessions: ["s-live"]
        )
        XCTAssertEqual(result.map(\.pid), [4200])
    }

    func testAServerWithoutSessionIDIsAnOrphan() {
        let anonymous = ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil, sessionID: nil)
        let result = orphans([process(4200, parent: 1, "uvx mcp-server-fetch")],
                             probe: probe(markers: [4200: anonymous]),
                             liveSessions: ["s-live"])
        XCTAssertEqual(result.map(\.pid), [4200])
        XCTAssertNil(result.first?.projectName)
    }

    func testSkipsAServerUnderALiveClaudeSession() {
        let reads = EnvironmentReads()
        let result = orphans(
            [
                process(8859, parent: 1, "/Users/x/.claude/local/claude"),
                process(4100, parent: 8859, "npm exec chrome-devtools-mcp@latest"),
            ],
            probe: probe(markers: [4100: claudeEnvironment], reads: reads)
        )
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(reads.pids.isEmpty)
    }

    /// `npm exec` spawns the package's binary, which spawns `node`: three processes that all
    /// look like the server. Only the top one is a row, and it weighs what the whole tree
    /// holds, including the browser the server drives.
    func testListsOneRowPerTreeAndSumsItsMemory() {
        let result = orphans(
            [
                process(4100, parent: 1, "npm exec chrome-devtools-mcp@latest"),
                process(4101, parent: 4100, "chrome-devtools-mcp"),
                process(4102, parent: 4101, "node /Users/x/.npm/_npx/1a2b/node_modules/chrome-devtools-mcp/build/src/index.js"),
                process(4103, parent: 4102, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless"),
            ],
            probe: probe(
                markers: [4100: claudeEnvironment, 4101: claudeEnvironment, 4102: claudeEnvironment],
                memory: [4100: 40 << 20, 4101: 30 << 20, 4102: 120 << 20, 4103: 222 << 20]
            )
        )
        XCTAssertEqual(result.map(\.pid), [4100])
        XCTAssertEqual(result.first?.residentBytes, 412 << 20)
    }

    func testSkipsProcessesWithoutClaudeMarkers() {
        let foreign = ProcessEnvironment.Markers(isClaude: false, projectDirectory: nil, sessionID: nil)
        let result = orphans([process(4200, parent: 1, "uvx mcp-server-fetch")],
                             probe: probe(markers: [4200: foreign]))
        XCTAssertTrue(result.isEmpty)
    }

    func testSkipsUnreadableEnvironments() {
        let result = orphans([process(4200, parent: 1, "uvx mcp-server-fetch")], probe: probe(markers: [:]))
        XCTAssertTrue(result.isEmpty)
    }

    /// A server that also listens on a port is already a row in the ports list.
    func testSkipsPidsListedAsPorts() {
        let result = orphans([process(4200, parent: 1, "uvx mcp-server-fetch")],
                             probe: probe(markers: [4200: claudeEnvironment]),
                             ports: [4200])
        XCTAssertTrue(result.isEmpty)
    }

    func testSkipsAnotherUsersProcesses() {
        let result = orphans([process(4200, parent: 1, "uvx mcp-server-fetch")],
                             probe: probe(markers: [4200: claudeEnvironment], strangers: [4200]))
        XCTAssertTrue(result.isEmpty)
    }

    /// An app ships its own MCP helpers and manages their lifetime itself.
    func testSkipsExecutablesInsideAnAppBundle() {
        let result = orphans(
            [process(4300, parent: 1, "/Applications/Cursor.app/Contents/Resources/mcp-helper")],
            probe: probe(markers: [4300: claudeEnvironment],
                         executables: [4300: "/Applications/Cursor.app/Contents/Resources/mcp-helper"])
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// `claude mcp serve` is Claude Code itself, which the reaper never kills.
    func testSkipsClaudeCodeServingMcp() {
        let result = orphans([process(4400, parent: 1, "/Users/x/.claude/local/claude mcp serve")],
                             probe: probe(markers: [4400: claudeEnvironment]))
        XCTAssertTrue(result.isEmpty)
    }

    /// Reading an environment costs a `kern.argmax` buffer: only the processes that already
    /// look like an orphaned MCP server get one.
    func testReadsEnvironmentsOnlyAfterTheCheapChecks() {
        let reads = EnvironmentReads()
        _ = orphans(
            [
                process(8859, parent: 1, "/Users/x/.claude/local/claude"),
                process(4100, parent: 8859, "npm exec chrome-devtools-mcp@latest"),
                process(4200, parent: 1, "uvx mcp-server-fetch"),
                process(4300, parent: 1, "python3 -m http.server"),
                process(4400, parent: 1, "node /x/mcp-server.js"),
            ],
            probe: probe(markers: [4200: claudeEnvironment], reads: reads),
            ports: [4400]
        )
        XCTAssertEqual(reads.pids, [4200])
    }

    func testReadsLiveSessionsOnlyWhenSomethingIsAttributed() {
        var asked = false
        _ = McpScanner.orphans(
            table: table([process(4300, parent: 1, "python3 -m http.server")]),
            excluding: [],
            probe: probe(markers: [:]),
            liveSessionIDs: { asked = true; return [] }
        )
        XCTAssertFalse(asked)
    }

    func testSortsTheHeaviestFirst() {
        let result = orphans(
            [
                process(4100, parent: 1, "uvx mcp-server-fetch"),
                process(4200, parent: 1, "npx figma-mcp"),
            ],
            probe: probe(markers: [4100: claudeEnvironment, 4200: claudeEnvironment],
                         memory: [4100: 10 << 20, 4200: 301 << 20])
        )
        XCTAssertEqual(result.map(\.name), ["figma-mcp", "mcp-server-fetch"])
    }

    // MARK: - Command line

    func testFlagsDoNotMakeAnMcpServer() {
        XCTAssertFalse(McpScanner.looksLikeMcpServer("node build/cli.js --mcp-config=/x/servers.json"))
        XCTAssertTrue(McpScanner.looksLikeMcpServer("python -m mcp_server_git"))
        XCTAssertTrue(McpScanner.looksLikeMcpServer("npx -y @modelcontextprotocol/server-filesystem /Users/x"))
        XCTAssertFalse(McpScanner.looksLikeMcpServer("bun worker-service.cjs --daemon"))
    }

    func testNamesTheServerAfterItsPackage() {
        XCTAssertEqual(McpScanner.displayName(arguments: "npm exec chrome-devtools-mcp@latest"), "chrome-devtools-mcp")
        XCTAssertEqual(
            McpScanner.displayName(arguments: "node /x/node_modules/chrome-devtools-mcp/build/src/index.js"),
            "chrome-devtools-mcp"
        )
        XCTAssertEqual(McpScanner.displayName(arguments: "uvx mcp-server-fetch"), "mcp-server-fetch")
        XCTAssertEqual(McpScanner.displayName(arguments: "python -m mcp_server_git"), "mcp_server_git")
    }

    /// uvx pins a version the Python way, and claude-mem launches its server from an inline
    /// script: the name is the run of name characters that holds the signature.
    func testCutsTheNameOutOfPinsAndInlineScripts() {
        XCTAssertEqual(
            McpScanner.displayName(arguments: "/opt/homebrew/bin/uv tool uvx --from chroma-mcp==0.2.6 chroma-mcp"),
            "chroma-mcp"
        )
        XCTAssertEqual(
            McpScanner.displayName(
                arguments: #"node -e const R=1;c.spawn(process.execPath,[p.join(R,'scripts',"mcp-server.cjs")],{stdio:'inherit'})"#
            ),
            "mcp-server"
        )
    }

    func testDropsScriptExtensions() {
        XCTAssertEqual(McpScanner.displayName(arguments: "bun /x/plugin/scripts/mcp-server.cjs"), "mcp-server")
        XCTAssertEqual(McpScanner.displayName(arguments: "node /x/figma-mcp.mjs"), "figma-mcp")
        XCTAssertEqual(McpScanner.displayName(arguments: "python3 /x/notes_mcp.py --stdio"), "notes_mcp")
    }

    /// A scope alone names no server, and a package alone can be as bare as `mcp`: a scoped
    /// package keeps both halves.
    func testKeepsTheScopeOfAScopedPackage() {
        XCTAssertEqual(McpScanner.displayName(arguments: "npx -y @playwright/mcp@latest"), "@playwright/mcp")
        XCTAssertEqual(
            McpScanner.displayName(arguments: "npx -y @modelcontextprotocol/server-filesystem@2025.1.0 /Users/x"),
            "@modelcontextprotocol/server-filesystem"
        )
    }

    func testFallsBackToTheExecutableName() {
        XCTAssertEqual(McpScanner.displayName(arguments: "/opt/homebrew/bin/python3 server.py"), "python3")
    }

    // MARK: - Process tree

    func testDescendantsCoverTheWholeTree() {
        let tree = table([
            process(4100, parent: 1, "npm exec chrome-devtools-mcp@latest"),
            process(4101, parent: 4100, "chrome-devtools-mcp"),
            process(4102, parent: 4101, "node index.js"),
            process(4103, parent: 4100, "sh"),
            process(4200, parent: 1, "uvx mcp-server-fetch"),
        ])
        XCTAssertEqual(Set(tree.descendants(of: 4100).map(\.pid)), [4101, 4102, 4103])
        XCTAssertTrue(tree.descendants(of: 1).isEmpty)
    }

    // MARK: - Live sessions

    private func sessionFile(pid: Int32, id: String, procStart: String?) -> Data {
        let start = procStart.map { ", \"procStart\": \"\($0)\"" } ?? ""
        return Data("{\"pid\": \(pid), \"sessionId\": \"\(id)\", \"cwd\": \"/Users/x\"\(start)}".utf8)
    }

    func testReadsTheIdOfALiveSession() {
        var asked: (Int32, Date?)?
        let id = LiveSessions.id(
            from: sessionFile(pid: 43920, id: "s-live", procStart: "Tue Nov 10 13:33:34 2026"),
            isLive: { pid, startedAt in
                asked = (pid, startedAt)
                return true
            }
        )
        XCTAssertEqual(id, "s-live")
        XCTAssertEqual(asked?.0, 43920)
        XCTAssertEqual(asked?.1, ProcessIdentity.date(fromProcStart: "Tue Nov 10 13:33:34 2026"))
    }

    func testIgnoresASessionWhoseProcessIsGone() {
        let id = LiveSessions.id(from: sessionFile(pid: 43920, id: "s-dead", procStart: nil),
                                 isLive: { _, _ in false })
        XCTAssertNil(id)
    }

    func testIgnoresAMalformedSessionFile() {
        XCTAssertNil(LiveSessions.id(from: Data("{\"pid\": \"x\"}".utf8), isLive: { _, _ in true }))
    }
}
