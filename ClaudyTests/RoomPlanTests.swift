import XCTest
@testable import Claudy

/// Who sits where in the agent room, and the way between two desks.
final class RoomPlanTests: XCTestCase {

    private func agents(_ families: [WorkFamily?], prefix: String = "a") -> [(id: String, family: WorkFamily?)] {
        families.enumerated().map { ("\(prefix)\($0.offset)", $0.element) }
    }

    func testAnAgentSitsInTheAreaOfItsWork() {
        var plan = RoomPlan()
        plan.seat(agents([.writing, .commands, .research]))
        XCTAssertEqual(plan.seats["a0"], RoomSeat(zone: 0, index: 0))
        XCTAssertEqual(plan.seats["a1"], RoomSeat(zone: 1, index: 0))
        XCTAssertEqual(plan.seats["a2"], RoomSeat(zone: 2, index: 0))
        XCTAssertEqual(plan.families, RoomPlan.homes)
    }

    func testAnAgentKeepsItsDeskFromOnePassToTheNext() {
        var plan = RoomPlan()
        plan.seat(agents([.writing, .writing, .writing]))
        plan.seat([("a2", .writing), ("a0", .writing)])
        XCTAssertEqual(plan.seats["a2"], RoomSeat(zone: 0, index: 2))
        XCTAssertEqual(plan.seats["a0"], RoomSeat(zone: 0, index: 0))
        XCTAssertNil(plan.seats["a1"])
    }

    func testAnAgentWhoseWorkChangesMovesToTheOtherArea() {
        var plan = RoomPlan()
        plan.seat([("a", .research)])
        plan.seat([("a", .writing)])
        XCTAssertEqual(plan.seats["a"], RoomSeat(zone: 0, index: 0))
    }

    func testAnAgentWhoseWorkSaysNothingStaysWhereItIs() {
        var plan = RoomPlan()
        plan.seat([("a", .commands)])
        plan.seat([("a", nil)])
        XCTAssertEqual(plan.seats["a"], RoomSeat(zone: 1, index: 0))
    }

    func testANewAgentWithNoWorkYetStartsInResearch() {
        var plan = RoomPlan()
        plan.seat([("a", nil)])
        XCTAssertEqual(plan.seats["a"]?.zone, 2)
    }

    func testAFullAreaSpillsIntoTheSpareOne() {
        var plan = RoomPlan()
        plan.seat(agents(Array(repeating: .commands, count: 7)))
        XCTAssertEqual(plan.count(in: 1), 6)
        XCTAssertEqual(plan.seats["a6"], RoomSeat(zone: 3, index: 0))
        XCTAssertEqual(plan.families[3], .commands)
    }

    func testTheSpareAreaIsFreeAgainOnceEmpty() {
        var plan = RoomPlan()
        plan.seat(agents(Array(repeating: .commands, count: 7)))
        plan.seat(agents(Array(repeating: .commands, count: 6)))
        XCTAssertNil(plan.families[3])
    }

    func testWithTheSpareAreaTakenAnEmptyAreaIsBorrowed() {
        var plan = RoomPlan()
        plan.seat(agents(Array(repeating: .commands, count: 13)))
        XCTAssertEqual(plan.count(in: 1), 6)
        XCTAssertEqual(plan.count(in: 3), 6)
        XCTAssertEqual(plan.seats["a12"]?.zone, 0)
        XCTAssertEqual(plan.families[0], .commands)
    }

    func testAnAgentTheRoomHasNoDeskForIsCountedApart() {
        var plan = RoomPlan()
        plan.seat(agents(Array(repeating: .commands, count: 25)))
        XCTAssertEqual(plan.seats.count, 24)
        XCTAssertEqual(plan.unseated, ["a24"])
    }

    func testAnAgentWithNowhereToGoKeepsItsDesk() {
        var plan = RoomPlan()
        var everyone = agents(Array(repeating: .commands, count: 18))
        everyone += agents(Array(repeating: .writing, count: 6), prefix: "w")
        plan.seat(everyone)
        let before = plan.seats["w0"]
        everyone[18] = ("w0", .commands)
        plan.seat(everyone)
        XCTAssertEqual(plan.seats["w0"], before)
        XCTAssertTrue(plan.unseated.isEmpty)
    }

    // MARK: - Routes

    func testARouteStartsAndEndsAtTheDesksAndTurnsAtRightAngles() {
        let from = RoomSeat(zone: 0, index: 2), to = RoomSeat(zone: 3, index: 0)
        let route = RoomGeometry.route(from: from, to: to)
        XCTAssertEqual(route.first, RoomGeometry.feet(from))
        XCTAssertEqual(route.last, RoomGeometry.feet(to))
        for (a, b) in zip(route, route.dropFirst()) {
            XCTAssertTrue(a.x == b.x || a.y == b.y, "\(a) to \(b) is a diagonal")
        }
    }

    func testAWalkerLeavesItsDeskByTheAisleBehindIt() {
        let seat = RoomSeat(zone: 0, index: 1)
        let route = RoomGeometry.route(from: seat, to: RoomSeat(zone: 1, index: 4))
        XCTAssertEqual(route[1], CGPoint(x: RoomGeometry.feet(seat).x, y: RoomGeometry.aisle(of: seat)))
        // Along the aisle it is behind its row's chairs and in front of nobody's desk.
        XCTAssertLessThan(RoomGeometry.aisle(of: seat), RoomGeometry.desk(seat).y + 2.5)
    }

    func testTheWaysToTheSofaAndOutTurnAtRightAngles() {
        let routes = [RoomGeometry.route(from: RoomSeat(zone: 1, index: 5), toSofa: 3), RoomGeometry.route(fromSofa: 0),
                      RoomGeometry.route(fromSofa: 3), RoomGeometry.routeOut(from: RoomSeat(zone: 2, index: 0))]
        for route in routes {
            for (a, b) in zip(route, route.dropFirst()) {
                XCTAssertTrue(a.x == b.x || a.y == b.y, "\(a) to \(b) is a diagonal")
            }
        }
        XCTAssertEqual(routes[0].last, RoomGeometry.sofa(3))
        XCTAssertEqual(routes[1].last, RoomGeometry.door)
        XCTAssertEqual(routes[3].last, RoomGeometry.door)
    }

    func testANewcomerComesInByTheDoor() {
        let route = RoomGeometry.route(from: nil, to: RoomSeat(zone: 2, index: 4))
        XCTAssertEqual(route.first, RoomGeometry.door)
        XCTAssertEqual(route.last, RoomGeometry.feet(RoomSeat(zone: 2, index: 4)))
    }

    func testTwoAreasOnTheSameSideShareTheirCorridor() {
        let route = RoomGeometry.route(from: RoomSeat(zone: 2, index: 2), to: RoomSeat(zone: 0, index: 5))
        XCTAssertTrue(route.allSatisfy { $0.y != RoomGeometry.crossing })
    }

    func testAPointAlongARoute() {
        let route = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]
        XCTAssertEqual(RoomGeometry.length(of: route), 20)
        XCTAssertEqual(RoomGeometry.point(on: route, at: 5), CGPoint(x: 5, y: 0))
        XCTAssertEqual(RoomGeometry.point(on: route, at: 15), CGPoint(x: 10, y: 5))
        XCTAssertEqual(RoomGeometry.point(on: route, at: 99), CGPoint(x: 10, y: 10))
    }
}
