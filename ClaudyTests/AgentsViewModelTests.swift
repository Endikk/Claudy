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

    private func agent(_ id: String, lastActivity: Date, startedAt: Date = Date()) -> RunningAgent {
        RunningAgent(id: id, sessionID: "s1", sessionName: "claire-bb", title: "Benchmark", startedAt: startedAt,
                     lastActivity: lastActivity, isFinished: false, actionCount: 3, recent: [], lastAction: nil,
                     editedFiles: ["a.ts", "b.ts"])
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
}
