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
}
