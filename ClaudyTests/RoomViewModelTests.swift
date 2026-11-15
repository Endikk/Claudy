import XCTest
@testable import Claudy

/// One activity per pass, then the last one again.
private final class SequenceActivity: AgentScanning, @unchecked Sendable {
    private var passes: [ClaudeActivity]
    init(_ passes: [ClaudeActivity]) { self.passes = passes }
    func scanActivity() async -> ClaudeActivity {
        passes.count > 1 ? passes.removeFirst() : passes[0]
    }
}

/// The agent room: one room per project, agents seated by their work, walking when it changes.
@MainActor
final class RoomViewModelTests: XCTestCase {

    private var now = Date(timeIntervalSince1970: 1_793_468_000)

    private func session(_ id: String, cwd: String, status: ClaudeSession.Status = .busy) -> ClaudeSession {
        ClaudeSession(id: id, pid: 4242, processStartedAt: now, name: id, cwd: cwd, openedAt: now,
                      status: status, statusSince: now, isBackground: false, host: nil, lastPrompt: "Add the room")
    }

    private func agent(_ id: String, session: String, calls: [(tool: String, command: String?)],
                       isFinished: Bool = false) -> RunningAgent {
        let actions = calls.map { call in
            let reading = AgentWork.read(tool: call.tool, command: call.command)
            return AgentAction(date: now, kind: AgentActionKind(tool: call.tool), tool: call.tool, file: nil,
                               work: reading.work, detail: reading.detail)
        }
        return RunningAgent(id: id, sessionID: session, sessionPID: 4242, sessionStartedAt: now, sessionName: session,
                            title: "Agent \(id)", startedAt: now, lastActivity: now, isFinished: isFinished,
                            actionCount: actions.count, recent: actions, lastAction: actions.last, editedFiles: [])
    }

    private func room(_ passes: [ClaudeActivity]) -> (RoomViewModel, AgentsViewModel) {
        let agents = AgentsViewModel(scanner: SequenceActivity(passes))
        let room = RoomViewModel(agents: agents, clock: { [unowned self] in self.now }, reducesMotion: { false })
        return (room, agents)
    }

    func testSessionsOfOneFolderShareARoom() async {
        let activity = ClaudeActivity(
            sessions: [session("a", cwd: "/me/Claudy"), session("b", cwd: "/me/Claudy"), session("c", cwd: "/me/Api")],
            agents: [agent("x", session: "a", calls: [("Read", nil)]), agent("y", session: "b", calls: [("Read", nil)])])
        let (room, agents) = room([activity])
        await agents.refresh()
        room.sync()
        XCTAssertEqual(Set(room.projects.map(\.id)), ["Claudy", "Api"])
        XCTAssertEqual(room.projects.first { $0.id == "Claudy" }?.agents.map(\.id), ["x", "y"])
    }

    func testAnAgentSitsAtADeskWithItsWorkOnItsScreen() async {
        let activity = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                      agents: [agent("x", session: "a", calls: [("Bash", "swift test")])])
        let (room, agents) = room([activity])
        await agents.refresh()
        room.sync()
        let scene = room.scene(for: room.selected, at: now, quota: 0.4)
        let desk = scene.desks[RoomViewModel.deskIndex(of: RoomSeat(zone: 1, index: 0))]
        XCTAssertEqual(desk?.glyph, RoomGlyph.symbol(for: .tests))
        XCTAssertEqual(desk?.state, .working)
        XCTAssertEqual(scene.zones[1].title, "Commands · 1/6")
        XCTAssertEqual(scene.chief.state, .working)
        XCTAssertEqual(scene.chief.glyph, RoomGlyph.delegating)
        XCTAssertEqual(scene.chief.quota, 0.4)
    }

    func testAnAgentWhoseWorkChangesWalksToTheOtherArea() async {
        let reading = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                     agents: [agent("x", session: "a", calls: [("Read", nil)])])
        let writing = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                     agents: [agent("x", session: "a", calls: [("Edit", nil), ("Edit", nil)])])
        let (room, agents) = room([reading, writing])
        await agents.refresh()
        room.isVisible = true
        XCTAssertNotNil(room.scene(for: room.selected, at: now, quota: nil).desks[RoomViewModel.deskIndex(of: RoomSeat(zone: 2, index: 0))])

        now += 30
        await agents.refresh()
        room.sync()
        let onTheWay = room.scene(for: room.selected, at: now.addingTimeInterval(0.5), quota: nil)
        XCTAssertEqual(onTheWay.walkers.map(\.id), ["x"])
        XCTAssertTrue(onTheWay.desks.allSatisfy { $0 == nil })

        let arrived = room.scene(for: room.selected, at: now.addingTimeInterval(60), quota: nil)
        XCTAssertTrue(arrived.walkers.isEmpty)
        XCTAssertEqual(arrived.desks[RoomViewModel.deskIndex(of: RoomSeat(zone: 0, index: 0))]?.id, "x")
    }

    func testNobodyWalksInWhenTheRoomOpensOnAgentsAlreadyAtWork() async {
        let activity = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                      agents: [agent("x", session: "a", calls: [("Read", nil)])])
        let (room, agents) = room([activity])
        await agents.refresh()
        room.isVisible = true
        XCTAssertTrue(room.scene(for: room.selected, at: now, quota: nil).walkers.isEmpty)
    }

    func testANewAgentComesInByTheDoor() async {
        let one = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                 agents: [agent("x", session: "a", calls: [("Read", nil)])])
        let two = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                 agents: [agent("x", session: "a", calls: [("Read", nil)]),
                                          agent("y", session: "a", calls: [("Read", nil)])])
        let (room, agents) = room([one, two])
        await agents.refresh()
        room.isVisible = true
        await agents.refresh()
        room.sync()
        let scene = room.scene(for: room.selected, at: now, quota: nil)
        XCTAssertEqual(scene.walkers.map(\.id), ["y"])
        XCTAssertEqual(scene.walkers.first?.position, RoomGeometry.door)
    }

    func testAnAgentThatJustCrossedTheRoomStaysPutForAWhile() async {
        let reading = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                     agents: [agent("x", session: "a", calls: [("Read", nil)])])
        let writing = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                     agents: [agent("x", session: "a", calls: [("Edit", nil)])])
        let (room, agents) = room([reading, writing, reading])
        await agents.refresh()
        room.isVisible = true
        now += 30
        await agents.refresh()
        room.sync()
        now += 5
        await agents.refresh()
        room.sync()
        let scene = room.scene(for: room.selected, at: now.addingTimeInterval(60), quota: nil)
        XCTAssertEqual(scene.desks[RoomViewModel.deskIndex(of: RoomSeat(zone: 0, index: 0))]?.id, "x")
    }

    func testAnAgentThatIsDoneGoesToTheSofa() async {
        let working = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                     agents: [agent("x", session: "a", calls: [("Read", nil)])])
        let done = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                  agents: [agent("x", session: "a", calls: [("Read", nil)], isFinished: true)])
        let (room, agents) = room([working, done])
        await agents.refresh()
        room.isVisible = true
        await agents.refresh()
        room.sync()

        let onTheWay = room.scene(for: room.selected, at: now.addingTimeInterval(0.5), quota: nil)
        XCTAssertEqual(onTheWay.walkers.map(\.id), ["x"])
        XCTAssertEqual(onTheWay.walkers.first?.glyph, RoomGlyph.done)
        XCTAssertTrue(onTheWay.desks.allSatisfy { $0 == nil })

        let seated = room.scene(for: room.selected, at: now.addingTimeInterval(60), quota: nil)
        XCTAssertEqual(seated.loungers.map(\.id), ["x"])
        XCTAssertEqual(seated.loungers.map(\.slot), [0])
        XCTAssertTrue(seated.walkers.isEmpty)
        XCTAssertEqual(seated.zones[2].count, 0)
    }

    func testAnAgentAlreadyDoneWhenTheRoomOpensSitsOnTheSofaAtOnce() async {
        let done = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                  agents: [agent("x", session: "a", calls: [("Read", nil)], isFinished: true)])
        let (room, agents) = room([done])
        await agents.refresh()
        room.isVisible = true
        let scene = room.scene(for: room.selected, at: now, quota: nil)
        XCTAssertTrue(scene.walkers.isEmpty)
        XCTAssertEqual(scene.loungers.map(\.slot), [0])
    }

    func testAnAgentThatLeavesTheListGetsUpAndGoesOutByTheDoor() async {
        let done = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                  agents: [agent("x", session: "a", calls: [("Read", nil)], isFinished: true)])
        let gone = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")], agents: [])
        let (room, agents) = room([done, gone])
        await agents.refresh()
        room.isVisible = true
        await agents.refresh()
        room.sync()

        let leaving = room.scene(for: room.selected, at: now.addingTimeInterval(0.5), quota: nil)
        XCTAssertEqual(leaving.walkers.map(\.id), ["x"])
        XCTAssertTrue(leaving.loungers.isEmpty)
        XCTAssertTrue(room.scene(for: room.selected, at: now.addingTimeInterval(120), quota: nil).walkers.isEmpty)
    }

    func testWithTheSofaFullAnAgentThatIsDoneGoesStraightOut() async {
        let ids = ["a", "b", "c", "d", "e"]
        let working = ClaudeActivity(sessions: [session("s", cwd: "/me/Claudy")],
                                     agents: ids.map { agent($0, session: "s", calls: [("Read", nil)]) })
        let done = ClaudeActivity(sessions: [session("s", cwd: "/me/Claudy")],
                                  agents: ids.map { agent($0, session: "s", calls: [("Read", nil)], isFinished: true) })
        let (room, agents) = room([working, done])
        await agents.refresh()
        room.isVisible = true
        await agents.refresh()
        room.sync()
        let later = room.scene(for: room.selected, at: now.addingTimeInterval(120), quota: nil)
        XCTAssertEqual(later.loungers.count, RoomGeometry.sofaSeats)
        XCTAssertTrue(later.walkers.isEmpty)
        XCTAssertTrue(later.desks.allSatisfy { $0 == nil })
    }

    func testClaudysScreenShowsWhatTheSessionItselfDoes() async {
        var lead = session("a", cwd: "/me/Claudy")
        let reading = AgentWork.read(tool: "Bash", command: "swift test")
        lead.lastAction = AgentAction(date: now, kind: .run, tool: "Bash", file: nil, work: reading.work, detail: reading.detail)
        let (room, agents) = room([ClaudeActivity(sessions: [lead], agents: [])])
        await agents.refresh()
        room.sync()
        let chief = room.scene(for: room.selected, at: now, quota: nil).chief
        XCTAssertEqual(chief.glyph, RoomGlyph.symbol(for: .tests))
        XCTAssertEqual(chief.help, "a · tests · swift test")

        let stale = room.scene(for: room.selected, at: now.addingTimeInterval(600), quota: nil).chief
        XCTAssertEqual(stale.glyph, RoomGlyph.thinking)
    }

    func testAClickOnADeskChoosesItsAgentAndASecondOneLetsGo() async {
        let activity = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy")],
                                      agents: [agent("x", session: "a", calls: [("Bash", "swift test")])])
        let (room, agents) = room([activity])
        await agents.refresh()
        room.sync()
        room.toggleAgent("x")
        XCTAssertEqual(room.selectedAgent?.id, "x")
        XCTAssertEqual(room.scene(for: room.selected, at: now, quota: nil).selectedDesk,
                       RoomViewModel.deskIndex(of: RoomSeat(zone: 1, index: 0)))
        XCTAssertEqual(room.place(of: "x"), RoomGeometry.desk(RoomSeat(zone: 1, index: 0)))
        room.toggleAgent("x")
        XCTAssertNil(room.selectedAgent)
    }

    func testABannerAboutAnAgentLeadsToItsDeskInItsProject() async {
        let activity = ClaudeActivity(
            sessions: [session("a", cwd: "/me/Claudy"), session("b", cwd: "/me/Api")],
            agents: [agent("x", session: "a", calls: [("Read", nil)]), agent("y", session: "b", calls: [("Bash", "swift test")])])
        let (room, agents) = room([activity])
        await agents.refresh()
        room.sync()
        room.isOverview = true
        room.show(agent: "y")
        XCTAssertEqual(room.selected?.id, "Api")
        XCTAssertEqual(room.selectedAgent?.id, "y")
        XCTAssertFalse(room.isOverview)

        room.enter("Claudy")
        XCTAssertEqual(room.selected?.id, "Claudy")
        XCTAssertNil(room.selectedAgent)
    }

    func testAWaitingSessionShowsOnClaudysScreen() async {
        let activity = ClaudeActivity(sessions: [session("a", cwd: "/me/Claudy", status: .waiting(reason: "permission prompt"))],
                                      agents: [])
        let (room, agents) = room([activity])
        await agents.refresh()
        room.sync()
        let chief = room.scene(for: room.selected, at: now, quota: nil).chief
        XCTAssertEqual(chief.state, .waiting)
        XCTAssertEqual(chief.glyph, RoomGlyph.waiting)
    }

    func testAnEmptyRoomHasNobodyAtTheCentreDesk() {
        let (room, _) = room([ClaudeActivity()])
        XCTAssertEqual(room.scene(for: nil, at: now, quota: nil).chief.state, .away)
    }

    func testTheSummarySaysWhatNeedsTheUserFirst() {
        let waiting = session("a", cwd: "/me/Claudy", status: .waiting(reason: "permission prompt"))
        let project = RoomViewModel.Project(id: "Claudy", sessions: [waiting],
                                            agents: [agent("x", session: "a", calls: [("Read", nil)])])
        let lines = RoomSummary.sentences(RoomTally(project, at: now), lead: waiting).map(\.text)
        XCTAssertEqual(lines, ["Waiting for your answer: permission prompt", "1 agent is working"])
    }
}
