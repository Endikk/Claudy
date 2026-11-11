import XCTest
@testable import Claudy

private struct StubAgents: AgentScanning {
    let result: [RunningAgent]
    func scanActivity() async -> ClaudeActivity { ClaudeActivity(agents: result) }
}

private struct StubActivity: AgentScanning {
    let activity: ClaudeActivity
    func scanActivity() async -> ClaudeActivity { activity }
}

/// One list per pass, then the last one again.
private final class SequenceAgents: AgentScanning, @unchecked Sendable {
    private var passes: [[RunningAgent]]
    init(_ passes: [[RunningAgent]]) { self.passes = passes }
    func scanActivity() async -> ClaudeActivity {
        ClaudeActivity(agents: passes.count > 1 ? passes.removeFirst() : passes[0])
    }
}

@MainActor
final class AgentsViewModelTests: XCTestCase {

    private func agent(_ id: String, lastActivity: Date, startedAt: Date = Date(), session: String = "s1",
                       pid: Int32 = 4242, isFinished: Bool = false, last: AgentAction? = nil,
                       recent: [AgentAction] = [], edited: [String] = ["a.ts", "b.ts"]) -> RunningAgent {
        RunningAgent(id: id, sessionID: session, sessionPID: pid, sessionStartedAt: nil, sessionName: "claire-bb", title: "Benchmark",
                     startedAt: startedAt, lastActivity: lastActivity, isFinished: isFinished, actionCount: 3,
                     recent: recent, lastAction: last, editedFiles: edited)
    }

    private func session(_ id: String = "s1", pid: Int32 = 4242, status: ClaudeSession.Status = .busy,
                         since: Date? = nil, opened: Date? = nil, background: Bool = false,
                         host: HostApp? = nil, name: String = "claire-bb", cwd: String? = nil) -> ClaudeSession {
        ClaudeSession(id: id, pid: pid, processStartedAt: Date(), name: name, cwd: cwd, openedAt: opened,
                      status: status, statusSince: since, isBackground: background, host: host, lastPrompt: nil)
    }

    private func action(_ tool: String, file: String? = nil, secondsAgo: TimeInterval = 0) -> AgentAction {
        AgentAction(date: Date().addingTimeInterval(-secondsAgo), kind: AgentActionKind(tool: tool), tool: tool, file: file)
    }

    func testPublishesScannedAgents() async {
        let found = [agent("a1", lastActivity: Date())]
        let model = AgentsViewModel(scanner: StubAgents(result: found))
        await model.refresh()
        XCTAssertEqual(model.agents, found)
    }

    /// The small Claudy in the menu bar and the notch stands for one at work rather than one at rest.
    func testLeadIsAnAgentAtWork() async {
        let resting = agent("resting", lastActivity: Date().addingTimeInterval(-600))
        let working = agent("working", lastActivity: Date())
        let model = AgentsViewModel(scanner: StubAgents(result: [resting, working]))
        await model.refresh()
        XCTAssertEqual(model.lead?.id, "working")
    }

    /// With nothing running, a pass publishes nothing: the card is not redrawn every few seconds.
    func testQuietPassLeavesTheClockAlone() async {
        let model = AgentsViewModel(scanner: StubAgents(result: []))
        let before = model.now
        await model.refresh()
        XCTAssertEqual(model.now, before)
    }

    /// Each agent has its own colour and keeps it while it runs; a colour freed by an agent that
    /// left goes to the next one launched.
    func testEachAgentKeepsItsOwnColour() async {
        let a1 = agent("a1", lastActivity: Date()), a2 = agent("a2", lastActivity: Date())
        let a3 = agent("a3", lastActivity: Date())
        let scanner = SequenceAgents([[a1, a2], [a2, a3]])
        let model = AgentsViewModel(scanner: scanner)

        await model.refresh()
        let first = model.colourIndex(of: a1), second = model.colourIndex(of: a2)
        await model.refresh()

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(model.colourIndex(of: a2), second)
        XCTAssertEqual(model.colourIndex(of: a3), first)
    }

    /// Never the main Claudy's coral, nor the amber that warns.
    func testAgentColoursLeaveCoralAndAmberToClaudy() {
        for colour in Theme.agentTints {
            XCTAssertNotEqual(colour, Theme.Accent.coral.color)
            XCTAssertNotEqual(colour, Theme.Accent.amber.color)
        }
    }

    func testDetailsNameTheSessionAndEveryEditedFile() async {
        let model = AgentsViewModel(scanner: StubAgents(result: []))
        let details = model.details(agent("a1", lastActivity: Date(), startedAt: Date().addingTimeInterval(-750)))
        XCTAssertEqual(details, "claire-bb · 12 min · 3 actions\nEdited: a.ts, b.ts")
    }

    /// The right of a row: the file while it works, its silence once it stalls, its output once done.
    func testStateSaysWhereTheAgentIs() async {
        let model = AgentsViewModel(scanner: StubAgents(result: []))
        XCTAssertEqual(model.state(agent("a", lastActivity: Date(), last: action("Edit", file: "banc.ts"))), "banc.ts")
        XCTAssertEqual(model.state(agent("a", lastActivity: Date().addingTimeInterval(-90))), "waiting")
        XCTAssertEqual(model.state(agent("a", lastActivity: Date().addingTimeInterval(-250))), "silent 4 min")
        XCTAssertEqual(model.state(agent("a", lastActivity: Date(), isFinished: true)), "done · 2 files")
        XCTAssertEqual(model.state(agent("a", lastActivity: Date(), isFinished: true, edited: [])), "done")
    }

    /// A silent agent loses its colour, a finished one keeps it.
    func testSilentAgentTurnsGrey() async {
        let working = agent("w", lastActivity: Date()), stalled = agent("s", lastActivity: Date().addingTimeInterval(-300))
        let done = agent("d", lastActivity: Date(), isFinished: true)
        let model = AgentsViewModel(scanner: StubAgents(result: [working, stalled, done]))
        await model.refresh()
        XCTAssertEqual(model.tint(of: stalled), Theme.idle)
        XCTAssertNotEqual(model.tint(of: working), Theme.idle)
        XCTAssertNotEqual(model.tint(of: done), Theme.idle)
    }

    func testLastCallsReadNewestFirst() {
        let model = AgentsViewModel(scanner: StubAgents(result: []))
        let recent = [action("Read", file: "a.ts", secondsAgo: 30), action("Bash", secondsAgo: 20),
                      action("Edit", file: "b.ts", secondsAgo: 10), action("Write", file: "c.ts", secondsAgo: 5)]
        XCTAssertEqual(model.lastCalls(agent("a", lastActivity: Date(), recent: recent)),
                       ["Write c.ts", "Edit b.ts", "Bash"])
    }

    /// One row unfolded at a time; an agent that leaves the list folds with it.
    func testExpandsOneRowAndFoldsItWhenTheAgentLeaves() async {
        let a = agent("a", lastActivity: Date()), b = agent("b", lastActivity: Date())
        let model = AgentsViewModel(scanner: SequenceAgents([[a, b], [b]]))
        await model.refresh()
        model.toggleExpanded(a)
        XCTAssertEqual(model.expandedID, "a")
        model.toggleExpanded(b)
        XCTAssertEqual(model.expandedID, "b")
        model.toggleExpanded(b)
        XCTAssertNil(model.expandedID)
        model.toggleExpanded(a)
        await model.refresh()
        XCTAssertNil(model.expandedID)
    }

    /// The interrupt is asked first, then sends Ctrl+C's signal to the session.
    func testInterruptSendsSIGINTToTheSessionAfterConfirmation() async {
        let sent = Sent()
        let model = AgentsViewModel(scanner: StubActivity(activity: ClaudeActivity(sessions: [session()])),
                                    isLive: { _, _ in true },
                                    signal: { pid, signal in sent.record(pid, signal); return 0 })
        await model.refresh()
        let session = try! XCTUnwrap(model.groups.first?.session)

        model.askToInterrupt(session)
        XCTAssertEqual(model.interruptPending, "s1")
        XCTAssertTrue(sent.calls.isEmpty)
        model.cancelInterrupt()
        XCTAssertNil(model.interruptPending)

        model.askToInterrupt(session)
        model.interrupt(session)
        XCTAssertEqual(sent.calls.count, 1)
        XCTAssertEqual(sent.calls.first?.0, 4242)
        XCTAssertEqual(sent.calls.first?.1, SIGINT)
        XCTAssertNil(model.interruptPending)
        XCTAssertEqual(model.notice, "Ctrl+C sent to claire-bb.")
    }

    /// `kill` failing names the reason it can: gone, or someone else's.
    func testFailedInterruptSaysWhy() async {
        let gone = AgentsViewModel(scanner: StubAgents(result: []), isLive: { _, _ in true }, signal: { _, _ in ESRCH })
        gone.interrupt(session())
        XCTAssertEqual(gone.notice, "Not sent: claire-bb has closed.")
        let other = AgentsViewModel(scanner: StubAgents(result: []), isLive: { _, _ in true }, signal: { _, _ in EPERM })
        other.interrupt(session())
        XCTAssertEqual(other.notice, "Not sent: claire-bb runs under another user.")
    }

    /// The pid is checked again as the signal goes out: never pid 0 or 1, never a pid that no
    /// longer belongs to the session, even if the list still shows it.
    func testInterruptNeverSignalsAPidThatIsNotTheSession() async {
        let sent = Sent()
        let dead = AgentsViewModel(scanner: StubAgents(result: []), isLive: { _, _ in false },
                                   signal: { pid, signal in sent.record(pid, signal); return 0 })
        dead.interrupt(session())
        XCTAssertEqual(dead.notice, "Not sent: claire-bb has closed.")

        for pid: Int32 in [0, 1, -1] {
            let model = AgentsViewModel(scanner: StubAgents(result: []), isLive: { _, _ in true },
                                        signal: { pid, signal in sent.record(pid, signal); return 0 })
            model.interrupt(session(pid: pid))
            XCTAssertEqual(model.notice, "Not sent: claire-bb has closed.")
        }
        XCTAssertTrue(sent.calls.isEmpty)
    }

    /// Without the start time its file records, nothing proves the pid is still the session: no
    /// signal, and no button offering one.
    func testInterruptNeedsTheSessionsStartTime() {
        let sent = Sent()
        let unknown = ClaudeSession(id: "s1", pid: 4242, processStartedAt: nil, name: "claire-bb", cwd: nil,
                                    openedAt: nil, status: .busy, statusSince: nil, isBackground: false,
                                    host: nil, lastPrompt: nil)
        let model = AgentsViewModel(scanner: StubAgents(result: []), isLive: { _, _ in true },
                                    signal: { pid, signal in sent.record(pid, signal); return 0 })
        XCTAssertFalse(unknown.canBeInterrupted)
        model.interrupt(unknown)
        XCTAssertTrue(sent.calls.isEmpty)
        XCTAssertEqual(model.notice, "Not sent: claire-bb has closed.")
    }

    /// Unfolding another row, or the session leaving the list, drops the confirmation: it must
    /// never greet the next row armed.
    func testPendingInterruptIsDroppedWhenTheRowOrTheSessionChanges() async {
        let a = agent("a", lastActivity: Date()), b = agent("b", lastActivity: Date())
        let model = AgentsViewModel(scanner: SequenceAgents([[a, b], []]), isLive: { _, _ in true },
                                    signal: { _, _ in 0 })
        await model.refresh()
        let session = try! XCTUnwrap(model.groups.first?.session)

        model.toggleExpanded(session)
        model.askToInterrupt(session)
        model.toggleExpanded(b)
        XCTAssertNil(model.interruptPending)

        model.askToInterrupt(session)
        await model.refresh()
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertNil(model.interruptPending)
        XCTAssertNil(model.expandedSessionID)
    }

    /// Finished agents stay listed but are not counted as running, nor made the lead.
    func testRunningCountLeavesFinishedAgentsOut() async {
        let done = agent("d", lastActivity: Date(), startedAt: Date().addingTimeInterval(-900), isFinished: true)
        let working = agent("w", lastActivity: Date())
        let model = AgentsViewModel(scanner: StubAgents(result: [done, working]), isLive: { _, _ in true },
                                    signal: { _, _ in 0 })
        await model.refresh()
        XCTAssertEqual(model.agents.count, 2)
        XCTAssertEqual(model.runningCount, 1)
        XCTAssertEqual(model.lead?.id, "w")

        let onlyDone = AgentsViewModel(scanner: StubAgents(result: [done]))
        await onlyDone.refresh()
        XCTAssertEqual(onlyDone.runningCount, 0)
        XCTAssertNil(onlyDone.lead)
    }

    // MARK: - Sessions

    /// Waiting first, the longest wait on top; then at work; then at rest. A program's own session
    /// shows only while it runs agents.
    func testGroupsPutWaitingSessionsFirstAndHideBackgroundOnes() async {
        let now = Date()
        let activity = ClaudeActivity(sessions: [
            session("idle", status: .idle, since: now.addingTimeInterval(-60), name: "a-idle"),
            session("busy", status: .busy, name: "b-busy"),
            session("late", status: .waiting(reason: "permission prompt"), since: now.addingTimeInterval(-30), name: "c-late"),
            session("early", status: .waiting(reason: nil), since: now.addingTimeInterval(-300), name: "d-early"),
            session("sdk", status: .busy, background: true, name: "observer"),
            session("sdk-agents", status: .busy, background: true, name: "worker"),
        ], agents: [agent("x", lastActivity: now, session: "sdk-agents")])
        let model = AgentsViewModel(scanner: StubActivity(activity: activity))
        await model.refresh()

        XCTAssertEqual(model.groups.map(\.session.id), ["early", "late", "busy", "sdk-agents", "idle"])
        XCTAssertEqual(model.groups.first { $0.session.id == "sdk-agents" }?.agents.map(\.id), ["x"])
        XCTAssertEqual(model.waiting.map(\.id), ["early", "late"])
    }

    /// The words of a session row: what it does, how long it has waited, what it waits for.
    func testSessionWords() async {
        let model = AgentsViewModel(scanner: StubAgents(result: []))
        let now = model.now
        XCTAssertEqual(model.state(session(status: .busy)), "working")
        XCTAssertEqual(model.state(session(status: .idle, since: now.addingTimeInterval(-12 * 60))), "idle 12 min")
        XCTAssertEqual(model.state(session(status: .unknown)), "open")
        let waiting = session(status: .waiting(reason: "permission prompt"), since: now.addingTimeInterval(-90),
                              host: HostApp(name: "Visual Studio Code", bundleURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")),
                              cwd: "/Users/me/EVAN")
        XCTAssertEqual(model.waited(waiting), "1 min")
        XCTAssertEqual(model.waitingDetail(waiting), "Permission prompt · EVAN · VS Code")
        XCTAssertEqual(AgentsViewModel.abbreviated("/Users/me/EVAN", home: "/Users/me"), "~/EVAN")
        XCTAssertEqual(AgentsViewModel.abbreviated("/Users/meme/EVAN", home: "/Users/me"), "/Users/meme/EVAN")
    }

    /// "Open" brings the session's app forward, and says so when there is none to bring.
    func testFocusOpensTheSessionsApp() async {
        let opened = Opened()
        let host = HostApp(name: "Terminal", bundleURL: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        let model = AgentsViewModel(scanner: StubActivity(activity: ClaudeActivity(sessions: [session(host: host)])),
                                    open: { opened.hosts.append($0); return true })
        await model.refresh()
        model.focus(sessionID: "s1")
        XCTAssertEqual(opened.hosts, [host])
        XCTAssertNil(model.notice)

        model.focus(session(host: nil))
        XCTAssertEqual(model.notice, "Claudy cannot tell which app runs claire-bb.")
    }

    /// A session at its prompt has no turn to stop: no confirmation survives it going idle.
    func testIdleSessionCannotBeInterrupted() async {
        XCTAssertTrue(session(status: .busy).canBeInterrupted)
        XCTAssertTrue(session(status: .waiting(reason: nil)).canBeInterrupted)
        XCTAssertFalse(session(status: .idle).canBeInterrupted)
    }

    func testStatusReadsTheSessionFilesWords() {
        XCTAssertEqual(ClaudeSession.Status(raw: "busy", waitingFor: nil), .busy)
        XCTAssertEqual(ClaudeSession.Status(raw: "idle", waitingFor: nil), .idle)
        XCTAssertEqual(ClaudeSession.Status(raw: "waiting", waitingFor: "input needed"), .waiting(reason: "input needed"))
        XCTAssertEqual(ClaudeSession.Status(raw: nil, waitingFor: nil), .unknown)
        XCTAssertEqual(ClaudeSession.Status(raw: "compacting", waitingFor: nil), .busy)
        XCTAssertTrue(ClaudeSession.isBackground(entrypoint: "sdk-cli"))
        XCTAssertFalse(ClaudeSession.isBackground(entrypoint: "claude-vscode"))
        XCTAssertFalse(ClaudeSession.isBackground(entrypoint: nil))
    }

    /// A pass that finishes after a newer one changes nothing.
    func testStalePassDoesNotOverwriteANewerOne() async {
        let slow = SlowAgents()
        let model = AgentsViewModel(scanner: slow)
        async let first: Void = model.refresh()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await slow.release(with: [agent("new", lastActivity: Date())])
        _ = await first
        XCTAssertEqual(model.agents.map(\.id), ["new"])
    }
}

/// Records the apps a view model brings forward.
@MainActor
private final class Opened {
    var hosts: [HostApp] = []
}

/// Records the signals a view model sends.
@MainActor
private final class Sent {
    private(set) var calls: [(Int32, Int32)] = []
    nonisolated func record(_ pid: Int32, _ signal: Int32) {
        MainActor.assumeIsolated { calls.append((pid, signal)) }
    }
}

/// Two passes: the first waits until released, the second answers at once with the released list.
private actor SlowAgents: AgentScanning {
    private var released: [RunningAgent]?
    private var waiters: [CheckedContinuation<[RunningAgent], Never>] = []

    func release(with agents: [RunningAgent]) {
        released = agents
        for waiter in waiters { waiter.resume(returning: agents) }
        waiters = []
    }

    func scanActivity() async -> ClaudeActivity {
        if let released { return ClaudeActivity(agents: released) }
        return ClaudeActivity(agents: await withCheckedContinuation { waiters.append($0) })
    }
}
