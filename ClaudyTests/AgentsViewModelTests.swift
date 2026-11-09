import XCTest
@testable import Claudy

private struct StubAgents: AgentScanning {
    let result: [RunningAgent]
    func scan() async -> [RunningAgent] { result }
}

/// One list per pass, then the last one again.
private final class SequenceAgents: AgentScanning, @unchecked Sendable {
    private var passes: [[RunningAgent]]
    init(_ passes: [[RunningAgent]]) { self.passes = passes }
    func scan() async -> [RunningAgent] { passes.count > 1 ? passes.removeFirst() : passes[0] }
}

@MainActor
final class AgentsViewModelTests: XCTestCase {

    private func agent(_ id: String, lastActivity: Date, startedAt: Date = Date(), session: String = "s1",
                       isFinished: Bool = false, last: AgentAction? = nil, recent: [AgentAction] = [],
                       edited: [String] = ["a.ts", "b.ts"]) -> RunningAgent {
        RunningAgent(id: id, sessionID: session, sessionPID: 4242, sessionName: "claire-bb", title: "Benchmark",
                     startedAt: startedAt, lastActivity: lastActivity, isFinished: isFinished, actionCount: 3,
                     recent: recent, lastAction: last, editedFiles: edited)
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

    /// Rows name their session only when agents of several sessions share the list.
    func testSpansSessionsWhenMoreThanOneSessionIsListed() async {
        let one = AgentsViewModel(scanner: StubAgents(result: [agent("a", lastActivity: Date()),
                                                                agent("b", lastActivity: Date())]))
        await one.refresh()
        XCTAssertFalse(one.spansSessions)
        let two = AgentsViewModel(scanner: StubAgents(result: [agent("a", lastActivity: Date()),
                                                                agent("b", lastActivity: Date(), session: "s2")]))
        await two.refresh()
        XCTAssertTrue(two.spansSessions)
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

    /// The interrupt is asked first, then sends Ctrl+C's signal to the agent's session.
    func testInterruptSendsSIGINTToTheSessionAfterConfirmation() async {
        final class Sent: @unchecked Sendable { var calls: [(Int32, Int32)] = [] }
        let sent = Sent()
        let a = agent("a", lastActivity: Date())
        let model = AgentsViewModel(scanner: StubAgents(result: [a]),
                                    signal: { pid, signal in sent.calls.append((pid, signal)); return true })
        await model.refresh()

        model.askToInterrupt(a)
        XCTAssertEqual(model.interruptPending, "s1")
        XCTAssertTrue(sent.calls.isEmpty)
        model.cancelInterrupt()
        XCTAssertNil(model.interruptPending)

        model.askToInterrupt(a)
        model.interrupt(a)
        XCTAssertEqual(sent.calls.count, 1)
        XCTAssertEqual(sent.calls.first?.0, 4242)
        XCTAssertEqual(sent.calls.first?.1, SIGINT)
        XCTAssertNil(model.interruptPending)
        XCTAssertEqual(model.notice, "Ctrl+C sent to claire-bb.")
    }

    func testFailedInterruptSaysSo() async {
        let a = agent("a", lastActivity: Date())
        let model = AgentsViewModel(scanner: StubAgents(result: [a]), signal: { _, _ in false })
        await model.refresh()
        model.interrupt(a)
        XCTAssertEqual(model.notice, "Could not reach claire-bb: the session may have closed.")
    }
}
