import Foundation

/// Claudy seen from the front for the agent room, in the inks of the app's own sprite
/// (`ClaudyTyping`): `C` body, `T` lit top, `D` shade, `o` outline, `E` eyes. 16 by 14. Seated
/// poses have no arms: the desk draws them on the keyboard.
enum RoomSprite {

    enum Pose: CaseIterable {
        case rest, blink, stepA, stepB, sit, sitBlink
    }

    static let columns = 16
    static let rows = 14

    private static let body = [
        "..oooooooooooo..",
        ".oTTTTTTTTTTTTo.",
        ".oTTTTTTTTTTTTo.",
        ".oCCCCCCCCCCCCo.",
        ".oCCECCCCCCECCo.",
        ".oCCECCCCCCECCo.",
        ".oCCCCCCCCCCCCo.",
        ".oCCCCCCCCCCCDo.",
        ".oCCCCCCCCCCCDo.",
        ".oDDDDDDDDDDDDo.",
        ".oooooooooooooo.",
    ]
    /// Rows 6 to 8 of a standing Claudy: an arm on each side.
    private static let arms = [
        "ooCCCCCCCCCCCCoo",
        "oCCCCCCCCCCCCDDo",
        "ooCCCCCCCCCCCDoo",
    ]
    private static let legsAtRest = [".oCooCo..oDooDo.", ".oCooCo..oDooDo.", ".oooooo..oooooo."]
    private static let legsStepA = [".oCooCo..oDooDo.", ".oCo.oo..oDo.oo.", ".ooo.....ooo...."]
    private static let legsStepB = [".oCooCo..oDooDo.", ".oo.oCo..oo.oDo.", "....ooo.....ooo."]

    private static let frames: [Pose: [String]] = Dictionary(uniqueKeysWithValues: Pose.allCases.map { ($0, build($0)) })

    static func frame(_ pose: Pose) -> [String] { frames[pose] ?? [] }

    private static func build(_ pose: Pose) -> [String] {
        var rows = body
        let isSeated = pose == .sit || pose == .sitBlink
        if !isSeated { rows.replaceSubrange(6...8, with: arms) }
        if pose == .blink || pose == .sitBlink {
            rows[4] = rows[4].replacingOccurrences(of: "E", with: "C")
        }
        switch pose {
        case .stepA: return rows + legsStepA
        case .stepB: return rows + legsStepB
        default: return rows + legsAtRest
        }
    }
}

/// The symbol on a screen of the agent room: one per kind of work, and one per state a screen
/// can be in. System symbols, as everywhere else in the app.
enum RoomGlyph {

    static let waiting = "hand.raised.fill"
    static let stalled = "pause.fill"
    static let done = "checkmark"
    static let thinking = "ellipsis"
    static let delegating = "person.2.fill"

    static func symbol(for work: AgentWork) -> String {
        switch work {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .docs: "doc.text.fill"
        case .plan: "checklist"
        case .design: "paintbrush.pointed.fill"
        case .search: "magnifyingglass"
        case .review: "eye.fill"
        case .web: "globe"
        case .terminal: "terminal.fill"
        case .tests: "testtube.2"
        case .build: "hammer.fill"
        case .benchmark: "speedometer"
        case .install: "shippingbox.fill"
        case .git: "arrow.triangle.branch"
        case .data: "cylinder.split.1x2.fill"
        case .infra: "cloud.fill"
        case .deploy: "paperplane.fill"
        case .security: "lock.shield.fill"
        case .delegating: delegating
        case .skill: "book.closed.fill"
        case .mcp: "powerplug.fill"
        case .other: thinking
        }
    }
}
