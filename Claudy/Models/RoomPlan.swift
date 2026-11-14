import CoreGraphics
import Foundation

/// One desk of the agent room: its area, and its place among the area's six.
struct RoomSeat: Hashable, Sendable {
    let zone: Int
    let index: Int
}

/// Who sits where in the agent room. Four areas of six desks: three have a kind of work of their
/// own, the fourth is spare. An agent sits in the area of its work; when that area is full, an
/// empty one takes the same work until it empties again.
struct RoomPlan: Equatable, Sendable {

    static let seatsPerZone = 6
    /// What each area is for when nobody borrows it. `nil` is the spare one.
    static let homes: [WorkFamily?] = [.writing, .commands, .research, nil]

    /// What each area is for now.
    private(set) var families: [WorkFamily?] = RoomPlan.homes
    private(set) var seats: [String: RoomSeat] = [:]
    /// Agents the room has no desk for.
    private(set) var unseated: [String] = []

    /// Seats the agents listed, oldest first, each with the area its work belongs to. An agent
    /// whose work says nothing (`nil`) keeps its desk, or starts in research: agents begin by
    /// reading.
    mutating func seat(_ agents: [(id: String, family: WorkFamily?)]) {
        let listed = Set(agents.map(\.id))
        let previous = seats
        seats = seats.filter { listed.contains($0.key) }
        unseated = []

        var movers: [(id: String, family: WorkFamily)] = []
        for agent in agents {
            if let seat = seats[agent.id] {
                guard let family = agent.family, families[seat.zone] != family else { continue }
                seats[agent.id] = nil
                movers.append((agent.id, family))
            } else {
                movers.append((agent.id, agent.family ?? .research))
            }
        }
        returnEmptyZones()

        for mover in movers {
            if let seat = freeSeat(for: mover.family) {
                seats[mover.id] = seat
            } else if let old = previous[mover.id], !seats.values.contains(old), listed.contains(mover.id) {
                // Nowhere to go: it keeps the desk it had, its screen says what it does.
                seats[mover.id] = old
                if families[old.zone] == nil { families[old.zone] = mover.family }
            } else {
                unseated.append(mover.id)
            }
        }
        returnEmptyZones()
    }

    /// How many sit in an area.
    func count(in zone: Int) -> Int {
        seats.values.filter { $0.zone == zone }.count
    }

    /// A desk in an area of this family, or in an empty area that takes the family: the spare
    /// one first.
    private mutating func freeSeat(for family: WorkFamily) -> RoomSeat? {
        for zone in families.indices where families[zone] == family {
            if let index = freeIndex(in: zone) { return RoomSeat(zone: zone, index: index) }
        }
        let empty = families.indices.filter { count(in: $0) == 0 }
        guard let zone = empty.first(where: { Self.homes[$0] == nil }) ?? empty.first else { return nil }
        families[zone] = family
        return RoomSeat(zone: zone, index: 0)
    }

    private func freeIndex(in zone: Int) -> Int? {
        let taken = Set(seats.values.filter { $0.zone == zone }.map(\.index))
        return (0..<Self.seatsPerZone).first { !taken.contains($0) }
    }

    /// An area nobody sits in goes back to its own work.
    private mutating func returnEmptyZones() {
        for zone in families.indices where count(in: zone) == 0 {
            families[zone] = Self.homes[zone]
        }
    }
}

/// Where things stand in the agent room, in the scene's own units (480 by 270), and the way from
/// one desk to another along its corridors.
enum RoomGeometry {

    static let size = CGSize(width: 480, height: 270)
    static let zoneOrigins: [CGPoint] = [
        CGPoint(x: 12, y: 60), CGPoint(x: 344, y: 60), CGPoint(x: 12, y: 156), CGPoint(x: 344, y: 156),
    ]
    static let zoneSize = CGSize(width: 124, height: 84)
    static let deskSize = CGSize(width: 36, height: 31)
    static let door = CGPoint(x: 240, y: 268)
    /// The corridor that runs between the upper and the lower areas.
    static let crossing: CGFloat = 152
    /// The corridor along the front wall, from the door to the two side corridors: it keeps a
    /// newcomer out of the lounge.
    static let entrance: CGFloat = 258
    /// How far below their own coordinates Claudy's desk and the lounge are drawn: both moved down
    /// with the areas, to leave more floor under the back wall.
    static let centreDrop: CGFloat = 6
    /// Units a Claudy walks in a second.
    static let pace: CGFloat = 50

    /// The top left corner of a desk.
    static func desk(_ seat: RoomSeat) -> CGPoint {
        let origin = zoneOrigins[seat.zone]
        return CGPoint(x: origin.x + 6 + CGFloat(seat.index % 3) * 38,
                       y: origin.y + 16 + CGFloat(seat.index / 3) * 33)
    }

    /// Where the feet of the Claudy at this desk are.
    static func feet(_ seat: RoomSeat) -> CGPoint {
        let desk = desk(seat)
        return CGPoint(x: desk.x + 25, y: desk.y + 18)
    }

    /// The corridor beside an area: left areas open to the right, right ones to the left.
    static func corridor(of zone: Int) -> CGFloat {
        zoneOrigins[zone].x < size.width / 2 ? 152 : 330
    }

    /// The aisle behind a desk's row, where a Claudy walks without passing through anyone: above
    /// the first row it runs under the area's sign, above the second between the two rows.
    static func aisle(of seat: RoomSeat) -> CGFloat {
        desk(seat).y + 1
    }

    /// From a desk out to its corridor: back from the chair to the aisle, then along it.
    private static func exit(of seat: RoomSeat) -> [CGPoint] {
        let feet = feet(seat)
        let aisle = aisle(of: seat)
        return [feet, CGPoint(x: feet.x, y: aisle), CGPoint(x: corridor(of: seat.zone), y: aisle)]
    }

    /// The way to a desk, corner by corner: from another desk, or from the door.
    static func route(from start: RoomSeat?, to end: RoomSeat) -> [CGPoint] {
        let arrival = Array(exit(of: end).reversed())
        let lane = corridor(of: end.zone)
        guard let start else {
            return [door, CGPoint(x: door.x, y: entrance), CGPoint(x: lane, y: entrance)] + arrival
        }
        var points = exit(of: start)
        let own = corridor(of: start.zone)
        if own != lane {
            points += [CGPoint(x: own, y: crossing), CGPoint(x: lane, y: crossing)]
        }
        return points + arrival
    }

    // MARK: - The lounge

    /// How many can sit on the sofa.
    static let sofaSeats = 4

    /// Where the feet of the Claudy sitting at a place of the sofa are.
    static func sofa(_ slot: Int) -> CGPoint {
        let across: [CGFloat] = [217, 232, 248, 263]
        return CGPoint(x: across[min(max(slot, 0), across.count - 1)], y: 210 + centreDrop)
    }

    /// The strip of rug between the sofa and the low table: the way in and out of the sofa.
    private static var sofaFront: CGFloat { 218 + centreDrop }

    /// From a desk to a place on the sofa: out by the corridor, in by the front of the sofa.
    static func route(from start: RoomSeat, toSofa slot: Int) -> [CGPoint] {
        let seat = sofa(slot)
        let own = corridor(of: start.zone)
        return exit(of: start) + [CGPoint(x: own, y: sofaFront), CGPoint(x: seat.x, y: sofaFront), seat]
    }

    /// From the sofa to the door, round the low table.
    static func route(fromSofa slot: Int) -> [CGPoint] {
        let seat = sofa(slot)
        let side: CGFloat = slot < sofaSeats / 2 ? 204 : 276
        return [seat, CGPoint(x: seat.x, y: sofaFront), CGPoint(x: side, y: sofaFront), CGPoint(x: side, y: entrance),
                CGPoint(x: door.x, y: entrance), door]
    }

    /// From a desk straight to the door: for an agent that is done when the sofa is full.
    static func routeOut(from start: RoomSeat) -> [CGPoint] {
        let own = corridor(of: start.zone)
        return exit(of: start) + [CGPoint(x: own, y: entrance), CGPoint(x: door.x, y: entrance), door]
    }

    static func length(of route: [CGPoint]) -> CGFloat {
        zip(route, route.dropFirst()).reduce(0) { $0 + abs($1.1.x - $1.0.x) + abs($1.1.y - $1.0.y) }
    }

    /// The point `distance` units along a route, its end past its length.
    static func point(on route: [CGPoint], at distance: CGFloat) -> CGPoint {
        var left = max(0, distance)
        for (from, to) in zip(route, route.dropFirst()) {
            let leg = abs(to.x - from.x) + abs(to.y - from.y)
            if left <= leg, leg > 0 {
                let part = left / leg
                return CGPoint(x: from.x + (to.x - from.x) * part, y: from.y + (to.y - from.y) * part)
            }
            left -= leg
        }
        return route.last ?? .zero
    }
}
