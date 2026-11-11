import XCTest
@testable import Claudy

private final class FakeSignals: SignalSending {
    var alive: Set<pid_t>
    var groups: [pid_t: pid_t]
    var sent: [(Int32, pid_t)] = []
    var diesOnTerm: Bool

    init(alive: Set<pid_t>, groups: [pid_t: pid_t] = [:], diesOnTerm: Bool = true) {
        self.alive = alive
        self.groups = groups
        self.diesOnTerm = diesOnTerm
    }

    func send(_ signal: Int32, to pid: pid_t) -> Bool {
        sent.append((signal, pid))
        if signal == SIGKILL || (signal == SIGTERM && diesOnTerm) { alive.remove(pid) }
        return true
    }

    func sendToGroup(_ signal: Int32, pgid: pid_t) -> Bool {
        sent.append((signal, -pgid))
        if signal == SIGKILL || (signal == SIGTERM && diesOnTerm) {
            alive = alive.filter { groups[$0] != pgid }
        }
        return true
    }

    func processGroup(of pid: pid_t) -> pid_t? { groups[pid] }
    func isRunning(_ pid: pid_t) -> Bool { alive.contains(pid) }
}

/// `Result<Void, _>` is not Equatable — Void is not — so refusals are compared on their own.
private extension Result where Success == Void, Failure == KillRefusal {
    var refusal: KillRefusal? {
        guard case .failure(let refusal) = self else { return nil }
        return refusal
    }
}

final class PortReaperTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_788_000_000)

    private func port(pid: pid_t, attribution: PortAttribution = .orphan, session: pid_t? = nil) -> ListeningPort {
        ListeningPort(id: "\(pid)-4000", pid: pid, port: 4000, command: "Python",
                      projectName: nil, startedAt: epoch, attribution: attribution, sessionRootPID: session)
    }

    private func table(_ processes: [RunningProcess]) -> ProcessTable {
        ProcessTable(processes: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) }))
    }

    func testTerminatesTheProcessGroup() {
        let signals = FakeSignals(alive: [500], groups: [500: 500])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(port(pid: 500),
                                 table: table([RunningProcess(pid: 500, parent: 1, startedAt: epoch, arguments: "python3")]))
        XCTAssertNil(result.refusal)
        XCTAssertEqual(signals.sent.map(\.0), [SIGTERM])
        XCTAssertEqual(signals.sent.first?.1, -500)
    }

    func testEscalatesToKillWhenTermIsIgnored() {
        let signals = FakeSignals(alive: [500], groups: [500: 500], diesOnTerm: false)
        let reaper = PortReaper(signals: signals, ownPID: 99)
        _ = reaper.kill(port(pid: 500),
                        table: table([RunningProcess(pid: 500, parent: 1, startedAt: epoch, arguments: "python3")]))
        XCTAssertEqual(signals.sent.map(\.0), [SIGTERM, SIGKILL])
    }

    /// Between the render and the click, the process may have died and its PID been reissued
    /// to something else. The start time is what tells the two apart.
    func testRefusesWhenStartTimeNoLongerMatches() {
        let signals = FakeSignals(alive: [500], groups: [500: 500])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            port(pid: 500),
            table: table([RunningProcess(pid: 500, parent: 1, startedAt: epoch.addingTimeInterval(60), arguments: "python3")])
        )
        XCTAssertEqual(result.refusal, .identityChanged)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesWhenTheProcessIsGone() {
        let signals = FakeSignals(alive: [], groups: [:])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(port(pid: 500), table: table([]))
        XCTAssertEqual(result.refusal, .identityChanged)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesToKillItself() {
        let signals = FakeSignals(alive: [99], groups: [99: 99])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(port(pid: 99),
                                 table: table([RunningProcess(pid: 99, parent: 1, startedAt: epoch, arguments: "Claudy")]))
        XCTAssertEqual(result.refusal, .protectedProcess)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesToKillItsOwnAncestor() {
        let signals = FakeSignals(alive: [42], groups: [42: 42])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            port(pid: 42),
            table: table([
                RunningProcess(pid: 99, parent: 42, startedAt: epoch, arguments: "Claudy"),
                RunningProcess(pid: 42, parent: 1, startedAt: epoch, arguments: "launcher"),
            ])
        )
        XCTAssertEqual(result.refusal, .protectedProcess)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    /// Killing the port would be one thing; killing the Claude session that owns it is another.
    func testRefusesToKillALiveClaudeSessionRoot() {
        let signals = FakeSignals(alive: [8859], groups: [8859: 8859])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            port(pid: 8859, attribution: .live, session: 8859),
            table: table([RunningProcess(pid: 8859, parent: 1, startedAt: epoch, arguments: "/Users/x/.claude/local/claude")])
        )
        XCTAssertEqual(result.refusal, .liveClaudeSession)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesPidOne() {
        let signals = FakeSignals(alive: [1], groups: [1: 1])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(port(pid: 1),
                                 table: table([RunningProcess(pid: 1, parent: 0, startedAt: epoch, arguments: "launchd")]))
        XCTAssertEqual(result.refusal, .protectedProcess)
    }

    /// A process group shared with Claudy itself must never be signalled as a group.
    func testFallsBackToSinglePidWhenGroupIsShared() {
        let signals = FakeSignals(alive: [500], groups: [500: 99, 99: 99])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        _ = reaper.kill(port(pid: 500),
                        table: table([RunningProcess(pid: 500, parent: 1, startedAt: epoch, arguments: "python3")]))
        XCTAssertEqual(signals.sent.first?.1, 500)
    }

    func testKillsByPidWithTheSameGuardrails() {
        let signals = FakeSignals(alive: [99], groups: [99: 99])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(pid: 99, startedAt: epoch,
                                 table: table([RunningProcess(pid: 99, parent: 1, startedAt: epoch, arguments: "Claudy")]))
        XCTAssertEqual(result.refusal, .protectedProcess)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    // MARK: - MCP servers left behind

    private func server(pid: pid_t, startedAt: Date? = nil) -> McpOrphan {
        McpOrphan(id: "mcp-\(pid)", pid: pid, startedAt: startedAt ?? epoch, name: "chrome-devtools-mcp",
                  projectName: nil, residentBytes: 0)
    }

    /// `npm exec` above the package's binary above `node`: the tree an MCP server runs as.
    private func serverTree(root: pid_t = 600, parent: pid_t = 1) -> [RunningProcess] {
        [
            RunningProcess(pid: root, parent: parent, startedAt: epoch, arguments: "npm exec chrome-devtools-mcp@latest"),
            RunningProcess(pid: root + 1, parent: root, startedAt: epoch, arguments: "chrome-devtools-mcp"),
            RunningProcess(pid: root + 2, parent: root + 1, startedAt: epoch, arguments: "node index.js"),
        ]
    }

    func testKillsAServerThatLeadsItsOwnGroupThroughTheGroup() {
        let signals = FakeSignals(alive: [600, 601, 602], groups: [600: 600, 601: 600, 602: 600])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(server(pid: 600), table: table(serverTree()))
        XCTAssertNil(result.refusal)
        XCTAssertEqual(signals.sent.map(\.1), [-600])
    }

    /// Claude Code does not detach the servers it spawns: they keep the group of the session
    /// that died, which still holds everything else that session left behind. Signalling that
    /// group would reach far beyond the row the user clicked, so the tree is signalled process
    /// by process instead.
    func testSignalsTheTreeOneByOneWhenTheGroupIsTheDeadSessions() {
        let signals = FakeSignals(alive: [600, 601, 602, 700], groups: [600: 300, 601: 300, 602: 300, 700: 300])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(server(pid: 600), table: table(serverTree()))
        XCTAssertNil(result.refusal)
        XCTAssertEqual(signals.sent.map(\.0), [SIGTERM, SIGTERM, SIGTERM])
        XCTAssertEqual(Set(signals.sent.map(\.1)), [600, 601, 602])
        XCTAssertEqual(signals.sent.first?.1, 600)
        XCTAssertTrue(signals.alive.contains(700))
    }

    func testSignalsTheTreeOneByOneWhenTheGroupIsClaudys() {
        let signals = FakeSignals(alive: [600, 601, 602], groups: [600: 99, 601: 99, 602: 99, 99: 99])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        _ = reaper.kill(server(pid: 600), table: table(serverTree()))
        XCTAssertFalse(signals.sent.contains { $0.1 < 0 })
        XCTAssertEqual(Set(signals.sent.map(\.1)), [600, 601, 602])
    }

    func testEscalatesTheWholeTreeToKill() {
        let signals = FakeSignals(alive: [600, 601, 602], groups: [600: 300, 601: 300, 602: 300], diesOnTerm: false)
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(server(pid: 600), table: table(serverTree()))
        XCTAssertNil(result.refusal)
        XCTAssertEqual(signals.sent.filter { $0.0 == SIGKILL }.map(\.1).sorted(), [600, 601, 602])
    }

    /// Between the scan and the click, the pid may have gone to a process a live session owns.
    func testRefusesAServerThatHasALiveClaudeAncestorAgain() {
        let signals = FakeSignals(alive: [600, 8859], groups: [600: 600])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            server(pid: 600),
            table: table(serverTree(parent: 8859)
                         + [RunningProcess(pid: 8859, parent: 1, startedAt: epoch, arguments: "/Users/x/.claude/local/claude")])
        )
        XCTAssertEqual(result.refusal, .liveClaudeSession)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesAServerWhoseStartTimeChanged() {
        let signals = FakeSignals(alive: [600], groups: [600: 600])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(server(pid: 600, startedAt: epoch.addingTimeInterval(-60)), table: table(serverTree()))
        XCTAssertEqual(result.refusal, .identityChanged)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesAServerAboveClaudy() {
        let signals = FakeSignals(alive: [600, 99], groups: [600: 600, 99: 600])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            server(pid: 600),
            table: table(serverTree() + [RunningProcess(pid: 99, parent: 602, startedAt: epoch, arguments: "Claudy")])
        )
        XCTAssertEqual(result.refusal, .protectedProcess)
        XCTAssertTrue(signals.sent.isEmpty)
    }

    /// A server that drives Claude Code holds a live session in its tree: killing the tree
    /// would kill that session.
    func testRefusesATreeThatHoldsALiveClaudeSession() {
        let signals = FakeSignals(alive: [600, 601, 602, 603], groups: [600: 600])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            server(pid: 600),
            table: table(serverTree() + [RunningProcess(pid: 603, parent: 602, startedAt: epoch,
                                                        arguments: "/Users/x/.claude/local/claude -p")])
        )
        XCTAssertEqual(result.refusal, .liveClaudeSession)
        XCTAssertTrue(signals.sent.isEmpty)
    }
}
