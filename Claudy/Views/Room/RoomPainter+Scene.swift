import SwiftUI

/// What changes with the agents: the areas and their signs, Claudy's own desk, and the light.
extension RoomPainter {

    /// The colour of an area's rug and sign. The spare one is grey.
    static func tint(of family: WorkFamily?) -> UInt32 {
        switch family {
        case .writing: 0x3EC6BC
        case .commands: 0xE0B872
        case .research: 0x4FA8F7
        case nil: 0x8F8A86
        }
    }

    /// One area: its rug, and its sign. While the area changes work the new colour sweeps across
    /// the rug and the sign flips.
    func zone(_ zone: RoomZone, at origin: CGPoint) {
        let x = origin.x, y = origin.y
        let size = RoomGeometry.zoneSize
        let old = Self.tint(of: zone.family)
        let isSwitching = zone.incoming != zone.family && zone.progress > 0
        let new = isSwitching ? Self.tint(of: zone.incoming) : old
        // A rug has a thickness: it shades the floor along its lower and right edges.
        shadow(x + 1.5, y + size.height, size.width, 1.5, opacity: 0.3)
        shadow(x + size.width, y + 1.5, 1.5, size.height, opacity: 0.3)
        fill(old, x, y, size.width, size.height, opacity: 0.24)
        if isSwitching {
            let swept = (size.width * zone.progress).rounded()
            fill(Self.floor, x, y, swept, size.height)
            fill(new, x, y, swept, size.height, opacity: 0.24)
        }
        let shown = zone.progress > 0.5 ? new : old
        var weave = Path()
        var thread: CGFloat = 2
        while thread < size.height - 1 {
            weave.addRect(CGRect(x: (x + 1) * unit, y: (y + thread) * unit, width: (size.width - 2) * unit, height: 0.5 * unit))
            thread += 2
        }
        context.fill(weave, with: .color(Color.white.opacity(0.028)))
        for (edge, opacity) in [(CGFloat(0), 0.55), (CGFloat(2), 0.36)] {
            let thickness: CGFloat = edge == 0 ? 1 : 0.5
            let width = size.width - edge * 2, height = size.height - edge * 2
            fill(shown, x + edge, y + edge, width, thickness, opacity: opacity)
            fill(shown, x + edge, y + size.height - edge - thickness, width, thickness, opacity: opacity)
            fill(shown, x + edge, y + edge, thickness, height, opacity: opacity)
            fill(shown, x + size.width - edge - thickness, y + edge, thickness, height, opacity: opacity)
        }
        let flip = isSwitching ? abs(1 - 2 * zone.progress) : 1
        let height = max(1, (10 * flip).rounded())
        let top = y + 3 + ((10 - height) / 2).rounded(.down)
        shadow(x + 4.5, top + height, 70, 1, opacity: 0.25)
        fill(shown, x + 4, top, 70, height)
        fill(Color.white.opacity(0.25), x + 4, top, 70, 0.5)
        if height >= 8 {
            text(zone.title, x: x + 7.5, y: y + 8, size: 11, weight: .semibold, color: Color(hex: Self.ink), width: 64)
        }
    }

    /// Claudy's desk in the middle of the room: a wide desk on its own rug, two screens, a lamp
    /// and a name plate.
    func chief(_ chief: RoomChief, step: Int, isLit: Bool, isSummaryOpen: Bool) {
        fill(Self.floor, 182, 88, 116, 62)
        fill(0x9B4E45, 182, 88, 116, 62, opacity: 0.45)
        for (x, y, width, height) in [(182, 88, 116, 1), (182, 149, 116, 1), (182, 88, 1, 62), (297, 88, 1, 62)] {
            fill(0xB08462, CGFloat(x), CGFloat(y), CGFloat(width), CGFloat(height))
        }
        fill(0xD97757, 185, 91, 110, 0.5, opacity: 0.5)
        fill(0xD97757, 185, 146.5, 110, 0.5, opacity: 0.5)
        shadow(199, 138, 82, 2.5, opacity: 0.25)
        fill(0x4A2A22, 228, 94, 24, 24)
        fill(0x5A3328, 228.5, 94.5, 23, 23)
        fill(0x6E4032, 230, 96, 20, 20)
        fill(0x84503F, 230, 96, 20, 0.5)

        let coral = Theme.Accent.coral.color
        let isPresent = chief.state != .away
        if isPresent {
            claudy(step % 23 == 0 ? .sitBlink : .sit, feet: CGPoint(x: 240, y: 120), tint: coral)
        }
        top(x: 198, y: 117, width: 84, depth: 10, grain: [(6, 5, 16), (54, 8.5, 20)])
        front(x: 198, y: 127, width: 84, height: 10, dividers: [22, 62], handles: [9, 70])
        fill(0xCFC3AE, 225.5, 128.5, 29, 8)
        fill(Self.bubble, 226, 129, 28, 7)
        fill(0xFFFFFF, 226, 129, 28, 0.5)
        text("Claudy", x: 226, y: 132.5, size: 10, weight: .bold, color: Color(hex: 0x2A1418), width: 28, isCentred: true)

        chiefScreens(chief, step: step, isSummaryOpen: isSummaryOpen)
        keyboard(x: 232, y: 120, keys: 9, isLit: isPresent)
        if isPresent {
            arms(x: 232, y: 114, tint: coral, isTyping: chief.state == .working, beat: step)
        }
        fill(Self.bubble, 223, 121, 2.5, 3)
        fill(Self.bubble, 225.5, 121.5, 0.5, 1.5)
        fill(0xEDE3D3, 251, 121, 5, 3.5)
        fill(0xB5A898, 252, 122, 3, 0.5)
        fill(0xB5A898, 252, 123, 2.5, 0.5)
        fill(0x2B2F36, 279.5, 111, 0.5, 8)
        fill(0x2B2F36, 277, 118.5, 5, 1)
        fill(isLit ? 0xC98A2C : 0x6E655A, 276.5, 107, 6, 4)
        fill(isLit ? 0xF2A93B : 0x8A7F72, 277, 107, 5, 3)
        fill(isLit ? 0xFFE3B0 : 0x9A8E7E, 277.5, 110, 4, 0.5)
    }

    /// Where Claudy's second screen stands, and the middle of its glass.
    static let quotaScreen = CGPoint(x: 259, y: 102.5)
    static let quotaCentre = CGPoint(x: quotaScreen.x + 7.5, y: quotaScreen.y + 6.25)

    /// Claudy's two screens: what the session does on the left, the session quota as the card's
    /// ring on the right. The right one opens the summary, and says so with a coral frame while
    /// the summary is closed.
    func chiefScreens(_ chief: RoomChief, step: Int, isSummaryOpen: Bool) {
        let isWaiting = chief.state == .waiting
        monitor(x: 202, y: 102.5, screen: isWaiting ? (step % 4 >= 2 ? 0xC98A2C : 0xF2A93B) : 0x1E2B36,
                glyph: chief.glyph, color: isWaiting ? Self.ink : 0xC8E4FF)
        let screen = Self.quotaScreen
        monitor(x: screen.x, y: screen.y, screen: 0x1E2B36, glyph: nil)
        let middle = CGPoint(x: Self.quotaCentre.x * unit, y: Self.quotaCentre.y * unit)
        let stroke = StrokeStyle(lineWidth: 1.25 * unit, lineCap: .round)
        var rail = Path()
        rail.addArc(center: middle, radius: 3.5 * unit, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        context.stroke(rail, with: .color(Color(hex: 0x3A4A58)), style: stroke)
        if let quota = chief.quota, quota > 0 {
            var used = Path()
            used.addArc(center: middle, radius: 3.5 * unit, startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * min(quota, 1)), clockwise: false)
            context.stroke(used, with: .color(Theme.tint(.coral, at: quota)), style: stroke)
        }
        if !isSummaryOpen, step % 8 < 4 {
            fill(0xD97757, screen.x - 1, screen.y - 1, 17, 0.5)
            fill(0xD97757, screen.x - 1, screen.y + 13, 17, 0.5)
            fill(0xD97757, screen.x - 1, screen.y - 1, 0.5, 14.5)
            fill(0xD97757, screen.x + 15.5, screen.y - 1, 0.5, 14.5)
        }
    }

    /// A Claudy that is done, sitting on the sofa.
    func lounger(_ lounger: RoomLounger, step: Int) {
        let seat = RoomGeometry.sofa(lounger.slot)
        claudy((step + lounger.slot * 7) % 23 == 0 ? .blink : .rest, feet: seat, tint: lounger.tint)
    }

    /// Coral corners round the desk whose agent is being looked at.
    func selection(at desk: CGPoint) {
        let size = RoomGeometry.deskSize
        let left = desk.x - 2, right = desk.x + size.width + 1, top = desk.y - 1.5, bottom = desk.y + size.height + 0.5
        for (x, y, across, down) in [(left, top, 5, 1), (left, top, 1, 5), (right - 4, top, 5, 1), (right, top, 1, 5),
                                     (left, bottom, 5, 1), (left, bottom - 4, 1, 5), (right - 4, bottom, 5, 1),
                                     (right, bottom - 4, 1, 5)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            fill(0xD97757, x, y, across, down)
        }
    }

    /// Past nine tenths of the session quota the room says so, as the card does: a red glow
    /// breathes at its edges.
    func strain(_ quota: Double, time: TimeInterval) {
        guard quota >= RoomPainter.strainedFrom else { return }
        let size = RoomGeometry.size
        let breath = 0.5 + 0.5 * sin(time * 2.5)
        let red = Color(hex: 0xF0604D)
        let rect = CGRect(x: 0, y: 0, width: size.width * unit, height: size.height * unit)
        let middle = CGPoint(x: size.width / 2 * unit, y: size.height / 2 * unit)
        context.fill(Path(rect), with: .radialGradient(Gradient(colors: [red.opacity(0), red.opacity(0), red.opacity(0.1 + 0.1 * breath)]),
                                                       center: middle, startRadius: 0, endRadius: size.width * 0.6 * unit))
    }

    /// The shares of the session quota at which the room warns, the card's own thresholds.
    static let warnedFrom = 0.75
    static let strainedFrom = 0.9

    /// The corners of the room fall away a little: the eye stays on the desks.
    func vignette() {
        let size = RoomGeometry.size
        let middle = CGPoint(x: size.width / 2 * unit, y: size.height * 0.52 * unit)
        let rect = CGRect(x: 0, y: 0, width: size.width * unit, height: size.height * unit)
        context.fill(Path(rect), with: .radialGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0), .black.opacity(0.3)]),
                                                       center: middle, startRadius: 0, endRadius: size.width * 0.62 * unit))
    }

    /// Dims the room for the hour, then lets every lamp and every lit screen shine through.
    mutating func light(_ sky: RoomSky, screens: [CGPoint]) {
        guard let dim = sky.dim else { return }
        let drop = RoomGeometry.centreDrop
        context.blendMode = .multiply
        fill(dim, 0, 0, RoomGeometry.size.width, RoomGeometry.size.height)
        context.blendMode = .screen
        if sky.hasLamps {
            let warm = Color(hex: 0xFFC878)
            glow(CGPoint(x: 279.5, y: 110 + drop), radius: 52, color: warm.opacity(0.5))
            glow(CGPoint(x: 191, y: 194 + drop), radius: 50, color: warm.opacity(0.45))
            glow(CGPoint(x: 435, y: 30), radius: 46, color: Color(hex: 0x4FA8F7).opacity(0.22))
            let cool = Color(hex: 0xA0C8FF).opacity(0.22)
            let own = [CGPoint(x: 209.5, y: 109 + drop), CGPoint(x: Self.quotaCentre.x, y: Self.quotaCentre.y + drop)]
            for screen in screens + own {
                glow(screen, radius: 20, color: cool)
            }
        }
        context.blendMode = .normal
    }

    private func glow(_ centre: CGPoint, radius: CGFloat, color: Color) {
        let middle = CGPoint(x: centre.x * unit, y: centre.y * unit)
        let rect = CGRect(x: middle.x - radius * unit, y: middle.y - radius * unit,
                          width: radius * 2 * unit, height: radius * 2 * unit)
        context.fill(Path(rect), with: .radialGradient(Gradient(colors: [color, .black.opacity(0)]), center: middle,
                                                       startRadius: 0, endRadius: radius * unit))
    }
}
