import XCTest
import SwiftUI
@testable import Claudy

/// How often the agent room has to be redrawn for what it shows.
final class RoomSceneTests: XCTestCase {

    private func occupant(_ state: RoomOccupant.State) -> RoomOccupant {
        RoomOccupant(id: "a", tint: .red, state: state, glyph: nil, phase: 0, isFlashing: false, help: "")
    }

    private func scene(desks: [RoomOccupant?] = [], walkers: [RoomWalker] = [],
                       chief: RoomChief.State = .away) -> RoomScene {
        RoomScene(zones: [], desks: desks, walkers: walkers, chief: RoomChief(state: chief, glyph: nil, quota: nil))
    }

    func testARoomWhereNobodyWorksIsQuiet() {
        XCTAssertEqual(scene().pace, .quiet)
        XCTAssertEqual(scene(desks: [nil, occupant(.idle), occupant(.stalled), occupant(.done)], chief: .waiting).pace, .quiet)
    }

    func testAnAgentAtWorkHasTheRoomKeepUpWithItsHands() {
        XCTAssertEqual(scene(desks: [occupant(.idle), occupant(.working)]).pace, .typing)
    }

    func testClaudyAtWorkCountsToo() {
        XCTAssertEqual(scene(chief: .working).pace, .typing)
    }

    func testAClaudyCrossingTheRoomWinsOverTheRest() {
        let walker = RoomWalker(id: "w", position: .zero, tint: .red, glyph: nil)
        XCTAssertEqual(scene(walkers: [walker]).pace, .walking)
        XCTAssertEqual(scene(desks: [occupant(.working)], walkers: [walker]).pace, .walking)
    }

    func testAQuieterRoomIsRedrawnLessOften() {
        XCTAssertLessThan(RoomScene.Pace.quiet.framesPerSecond, RoomScene.Pace.typing.framesPerSecond)
        XCTAssertLessThan(RoomScene.Pace.typing.framesPerSecond, RoomScene.Pace.walking.framesPerSecond)
    }
}
