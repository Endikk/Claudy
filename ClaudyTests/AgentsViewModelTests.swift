import XCTest
@testable import Claudy

private struct StubAgents: AgentScanning {
    let result: [RunningAgent]
    func scan() async -> [RunningAgent] { result }
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

    func testDetailsNameTheSessionAndEveryEditedFile() async {
        let model = AgentsViewModel(scanner: StubAgents(result: []))
        let details = model.details(agent("a1", lastActivity: Date(), startedAt: Date().addingTimeInterval(-750)))
        XCTAssertEqual(details, "claire-bb · 12 min · 3 actions\nEdited: a.ts, b.ts")
    }
}
