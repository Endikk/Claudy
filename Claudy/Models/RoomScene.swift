import SwiftUI

/// Who sits at a desk of the agent room, as the scene draws it.
struct RoomOccupant: Identifiable, Equatable {
    enum State: Equatable {
        case working, idle, stalled, done, waiting
    }

    let id: String
    let tint: Color
    let state: State
    /// The glyph on its screen, `nil` for a dark one.
    let glyph: String?
    /// Sets its typing and its blinks apart from its neighbours'.
    let phase: Int
    /// Its work just changed: the screen lights up for a moment.
    let isFlashing: Bool
    /// What a pointer resting on the desk is told.
    let help: String
}

/// A Claudy on its way to a desk.
struct RoomWalker: Identifiable, Equatable {
    let id: String
    let position: CGPoint
    let tint: Color
    /// The work it goes to, in a bubble over its head.
    let glyph: String?
}

/// A Claudy that is done, sitting on the sofa until it leaves.
struct RoomLounger: Identifiable, Equatable {
    let id: String
    /// Its place on the sofa, from the left.
    let slot: Int
    let tint: Color
    let help: String
}

/// One area of the room: what it is for, what it is turning into, and how far along.
struct RoomZone: Equatable {
    let family: WorkFamily?
    /// The work the area is switching to, while its sign flips.
    let incoming: WorkFamily?
    /// 0…1 along that switch.
    let progress: Double
    let count: Int

    /// The words on its sign.
    var title: String {
        let shown = progress > 0.5 ? incoming : family
        return "\(shown?.title ?? "Free") · \(count)/\(RoomPlan.seatsPerZone)"
    }
}

/// Claudy at the centre desk: the project's session.
struct RoomChief: Equatable {
    enum State: Equatable {
        case working, waiting, idle, away
    }

    let state: State
    let glyph: String?
    /// 0…1 of the session quota, for the ring on its second screen. `nil` with no measurement.
    let quota: Double?
    /// What a pointer resting on its first screen is told: the session, and what it does.
    var help = ""
}

/// Everything the room shows at one instant.
struct RoomScene: Equatable {
    var zones: [RoomZone]
    /// One entry per desk, in `RoomSeat` order: area by area, six each.
    var desks: [RoomOccupant?]
    var walkers: [RoomWalker]
    var chief: RoomChief
    /// The Claudys that are done, on the sofa.
    var loungers: [RoomLounger] = []
    /// The desk whose agent is being looked at, as an index in `desks`.
    var selectedDesk: Int?

    /// How fast what the room shows moves, which sets how often it is redrawn.
    enum Pace: Equatable {
        /// Nobody works: a slow vacuum, a clock, an agent dozing.
        case quiet
        /// Hands on a keyboard.
        case typing
        /// A Claudy crosses the room.
        case walking

        var framesPerSecond: Double {
            switch self {
            case .quiet: return 2
            case .typing: return 6
            case .walking: return 20
            }
        }
    }

    var pace: Pace {
        if !walkers.isEmpty { return .walking }
        let isSomeoneTyping = chief.state == .working || desks.contains { $0?.state == .working }
        return isSomeoneTyping ? .typing : .quiet
    }
}
