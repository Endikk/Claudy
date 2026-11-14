import XCTest
@testable import Claudy

/// The robot vacuum of the agent room: where it is, from the time alone.
final class RoomVacuumTests: XCTestCase {

    func testARoundLeavesTheDockAndComesBackToIt() {
        XCTAssertEqual(RoomVacuum.round.first, RoomVacuum.dock)
        XCTAssertEqual(RoomVacuum.round.last, RoomVacuum.dock)
        XCTAssertEqual(RoomVacuum.state(at: 0).position, RoomVacuum.dock)
    }

    func testItTurnsAtRightAngles() {
        for (from, to) in zip(RoomVacuum.round, RoomVacuum.round.dropFirst()) {
            XCTAssertTrue(from.x == to.x || from.y == to.y, "\(from) to \(to) is a diagonal")
        }
    }

    func testItIsOutDuringARoundAndFacesWhereItGoes() {
        let leaving = RoomVacuum.state(at: 0.5)
        XCTAssertFalse(leaving.isDocked)
        XCTAssertEqual(leaving.heading, CGVector(dx: 0, dy: 1))
        XCTAssertEqual(leaving.position.y, RoomVacuum.dock.y + 0.5 * RoomVacuum.pace, accuracy: 0.001)

        let underTheWall = RoomVacuum.state(at: 5)
        XCTAssertEqual(underTheWall.heading, CGVector(dx: -1, dy: 0))
    }

    func testItChargesOnItsDockBetweenTwoRounds() {
        let charging = RoomVacuum.state(at: RoomVacuum.travelTime + 1)
        XCTAssertTrue(charging.isDocked)
        XCTAssertEqual(charging.position, RoomVacuum.dock)
        XCTAssertFalse(RoomVacuum.state(at: RoomVacuum.period + 1).isDocked)
    }

    func testItsTrailStartsUnderItAndFollowsTheCornersItTook() {
        let time: TimeInterval = 3
        let trail = RoomVacuum.trail(at: time)
        XCTAssertEqual(trail.first, RoomVacuum.state(at: time).position)
        // Three seconds in, it has left the dock and turned left under the wall: both legs show.
        XCTAssertTrue(trail.contains { $0.x == RoomVacuum.dock.x && $0.y < 56 })
        XCTAssertTrue(trail.contains { $0.y == 56 && $0.x < RoomVacuum.dock.x })
        XCTAssertTrue(RoomVacuum.trail(at: RoomVacuum.travelTime + 1).isEmpty)
    }

    func testItStaysClearOfTheDesks() {
        let zones = RoomGeometry.zoneOrigins.map { CGRect(origin: $0, size: RoomGeometry.zoneSize) }
        var time: TimeInterval = 0
        while time < RoomVacuum.travelTime {
            let position = RoomVacuum.state(at: time).position
            XCTAssertFalse(zones.contains { $0.insetBy(dx: -3, dy: -3).contains(position) }, "in an area at \(position)")
            time += 0.5
        }
    }
}
