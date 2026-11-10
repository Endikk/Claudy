import XCTest
@testable import Claudy

final class AgentModelsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_793_468_000)

    private func action(_ tool: String, file: String? = nil, secondsAgo: TimeInterval = 0) -> AgentAction {
        AgentAction(date: now.addingTimeInterval(-secondsAgo), kind: AgentActionKind(tool: tool), tool: tool, file: file)
    }

    private func agent(session: String = "s1", last: AgentAction?, recent: [AgentAction] = [],
                       lastActivity: TimeInterval = 0, isFinished: Bool = false) -> RunningAgent {
        RunningAgent(id: "a1", sessionID: session, sessionPID: 4242, sessionStartedAt: nil, sessionName: "claire-bb", title: "Benchmark",
                     startedAt: now.addingTimeInterval(-600), lastActivity: now.addingTimeInterval(-lastActivity),
                     isFinished: isFinished, actionCount: recent.count, recent: recent, lastAction: last,
                     editedFiles: [])
    }

    func testToolNamesSortIntoKinds() {
        XCTAssertEqual(AgentActionKind(tool: "Read"), .read)
        XCTAssertEqual(AgentActionKind(tool: "Grep"), .read)
        XCTAssertEqual(AgentActionKind(tool: "Write"), .edit)
        XCTAssertEqual(AgentActionKind(tool: "Edit"), .edit)
        XCTAssertEqual(AgentActionKind(tool: "Bash"), .run)
        XCTAssertEqual(AgentActionKind(tool: "WebFetch"), .web)
        XCTAssertEqual(AgentActionKind(tool: "mcp__plugin_ecc_chrome-devtools__click"), .web)
        XCTAssertEqual(AgentActionKind(tool: "Agent"), .other)
    }

    /// The file when the last call had one, otherwise the kind of work in one word.
    func testTouchingNamesTheFileOrTheKindOfWork() {
        XCTAssertEqual(agent(last: action("Write", file: "banc.ts")).touching, "banc.ts")
        XCTAssertTrue(agent(last: action("Write", file: "banc.ts")).isWriting)
        XCTAssertFalse(agent(last: action("Read", file: "a.ts")).isWriting)
        XCTAssertEqual(agent(last: action("Bash")).touching, "terminal")
        XCTAssertEqual(agent(last: action("WebSearch")).touching, "web")
        XCTAssertEqual(agent(last: action("Grep")).touching, "search")
        XCTAssertEqual(agent(last: nil).touching, "starting")
    }

    /// A minute of silence is a pause; three minutes are worth a look; finished is finished.
    func testStatusFollowsTheLastActivity() {
        XCTAssertEqual(agent(last: nil, lastActivity: 10).status(at: now), .working)
        XCTAssertEqual(agent(last: nil, lastActivity: 59).status(at: now), .working)
        XCTAssertEqual(agent(last: nil, lastActivity: 60).status(at: now), .idle)
        XCTAssertEqual(agent(last: nil, lastActivity: 90).status(at: now), .idle)
        XCTAssertEqual(agent(last: nil, lastActivity: 179).status(at: now), .idle)
        XCTAssertEqual(agent(last: nil, lastActivity: 180).status(at: now), .stalled)
        XCTAssertEqual(agent(last: nil, lastActivity: 200).status(at: now), .stalled)
        XCTAssertEqual(agent(last: nil, lastActivity: 10, isFinished: true).status(at: now), .done)
        XCTAssertEqual(agent(last: nil, lastActivity: 200, isFinished: true).status(at: now), .done)
    }

    func testSilenceCountsFromTheLastWrite() {
        XCTAssertEqual(agent(last: nil, lastActivity: 200).silence(at: now), 200, accuracy: 0.001)
        XCTAssertEqual(agent(last: nil, lastActivity: -5).silence(at: now), 0)
    }

    /// Ten minutes in forty slots of fifteen seconds, the newest last; anything older is left out.
    func testTrackCountsEditsApartFromTheRest() {
        let recent = [action("Write", file: "a.ts", secondsAgo: 5), action("Read", file: "b.ts", secondsAgo: 7),
                      action("Bash", secondsAgo: 20), action("Edit", file: "c.ts", secondsAgo: 620)]
        let track = agent(last: nil, recent: recent).track(at: now)

        XCTAssertEqual(track.count, RunningAgent.trackSlots)
        XCTAssertEqual(track.last, AgentTrackSlot(edits: 1, others: 1))
        XCTAssertEqual(track[track.count - 2], AgentTrackSlot(edits: 0, others: 1))
        XCTAssertEqual(track.dropLast(2).reduce(0) { $0 + $1.edits + $1.others }, 0)
    }
}
