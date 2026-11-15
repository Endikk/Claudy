import CoreGraphics
import Foundation

/// The robot vacuum of the agent room: it leaves its dock by the back wall, goes round every
/// corridor of the room, comes back to charge, and starts again. Where it is depends on the time
/// alone, so nothing has to remember it.
enum RoomVacuum {

    /// Where it charges, against the back wall between the board and the clock.
    static let dock = CGPoint(x: 333, y: 49)
    /// Units it covers in a second.
    static let pace: CGFloat = 9
    /// How long it stays on its dock between two rounds.
    static let charge: TimeInterval = 25

    /// One round, corner by corner, from the dock and back to it: under the back wall, down the
    /// left corridor, along the front wall and back across the lounge rug's edge, up the right
    /// corridor, across the room in front of Claudy's desk, and between that desk and the lounge.
    static let round: [CGPoint] = [
        dock,
        CGPoint(x: 333, y: 56), CGPoint(x: 146, y: 56), CGPoint(x: 146, y: 254), CGPoint(x: 44, y: 254),
        CGPoint(x: 44, y: 246), CGPoint(x: 436, y: 246), CGPoint(x: 436, y: 254), CGPoint(x: 333, y: 254),
        CGPoint(x: 333, y: 152), CGPoint(x: 160, y: 152), CGPoint(x: 160, y: 166), CGPoint(x: 320, y: 166),
        CGPoint(x: 320, y: 178), CGPoint(x: 333, y: 178), CGPoint(x: 333, y: 56),
        dock,
    ]

    struct State: Equatable {
        let position: CGPoint
        /// The way it faces: one of the four directions, as a unit step.
        let heading: CGVector
        let isDocked: Bool
    }

    static var travelTime: TimeInterval { TimeInterval(RoomGeometry.length(of: round) / pace) }
    static var period: TimeInterval { travelTime + charge }

    /// The floor it went over in the last `length` units, newest point first, following the
    /// corners it took. Empty on the dock.
    static func trail(at time: TimeInterval, length: CGFloat = 44, spacing: CGFloat = 2) -> [CGPoint] {
        let moment = time.truncatingRemainder(dividingBy: period)
        let elapsed = moment < 0 ? moment + period : moment
        guard elapsed < travelTime else { return [] }
        let head = CGFloat(elapsed) * pace
        return stride(from: head, through: max(0, head - length), by: -spacing).map { RoomGeometry.point(on: round, at: $0) }
    }

    /// Where the vacuum is `time` seconds into its day.
    static func state(at time: TimeInterval) -> State {
        let moment = time.truncatingRemainder(dividingBy: period)
        let elapsed = moment < 0 ? moment + period : moment
        guard elapsed < travelTime else {
            return State(position: dock, heading: CGVector(dx: 0, dy: 1), isDocked: true)
        }
        let distance = CGFloat(elapsed) * pace
        var left = distance
        for (from, to) in zip(round, round.dropFirst()) {
            let leg = abs(to.x - from.x) + abs(to.y - from.y)
            if left <= leg, leg > 0 {
                let heading = CGVector(dx: (to.x - from.x) / leg, dy: (to.y - from.y) / leg)
                return State(position: RoomGeometry.point(on: round, at: distance), heading: heading, isDocked: false)
            }
            left -= leg
        }
        return State(position: dock, heading: CGVector(dx: 0, dy: 1), isDocked: true)
    }
}
