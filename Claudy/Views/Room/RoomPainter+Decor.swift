import SwiftUI

/// What furnishes the room. In a niche of the back wall, where racks are seen as they stand: the
/// server room behind its glass. In the middle of the floor, clear of the corridors the agents
/// walk: the lounge. By the front wall: the door.
extension RoomPainter {

    // MARK: - Robot vacuum

    /// The vacuum's dock against the back wall: a tower, the ramp the vacuum parks on with its
    /// two contacts, and the cable to its socket.
    func dock() {
        let x = RoomVacuum.dock.x
        // Socket and cable.
        fill(0xEDE3D3, x + 9, 29.5, 3.5, 4.5)
        fill(0xCFC3AE, x + 9, 33.5, 3.5, 0.5)
        fill(0x2A1418, x + 10, 31, 0.5, 1.25)
        fill(0x2A1418, x + 11.25, 31, 0.5, 1.25)
        fill(0x16181C, x + 10.5, 34, 0.5, 9.5)
        fill(0x16181C, x + 5, 43, 6, 0.5)
        // Ramp.
        shadow(x - 6.5, 51.5, 13, 1.5, opacity: 0.3)
        shape([CGPoint(x: x - 5, y: 45.5), CGPoint(x: x + 5, y: 45.5), CGPoint(x: x + 6.5, y: 52), CGPoint(x: x - 6.5, y: 52)],
              color: Color(hex: 0x2B2F36))
        fill(0x3A3F48, x - 5, 45.5, 10, 0.5)
        for rib in 0..<3 { fill(0x23262C, x - 5.25 - CGFloat(rib) * 0.3, 47.75 + CGFloat(rib) * 1.4, 10.5 + CGFloat(rib) * 0.6, 0.5) }
        fill(0xC6C8D0, x - 2.75, 46.5, 1.5, 1)
        fill(0xC6C8D0, x + 1.25, 46.5, 1.5, 1)
        fill(0x16181C, x - 6.5, 51.5, 13, 0.5)
        // Tower.
        fill(0x16181C, x - 5.5, 29.5, 11, 16.5)
        fill(0x2B2F36, x - 5, 30, 10, 15.5)
        fill(0x3A3F48, x - 5, 30, 10, 2)
        fill(0x4A505B, x - 5, 30, 10, 0.5)
        fill(0x16181C, x - 5, 32, 10, 0.5)
        fill(Color.white.opacity(0.06), x - 5, 32.5, 1, 13)
        fill(Color.black.opacity(0.25), x + 3.5, 32.5, 1.5, 13)
        fill(0x23262C, x - 3.5, 34, 7, 8)
        fill(0x16181C, x - 3.5, 34, 7, 0.5)
        fill(0x4A505B, x - 2.5, 38, 5, 0.5)
        for slot in 0..<3 { fill(0x16181C, x - 2.5, 39.5 + CGFloat(slot), 5, 0.5) }
        fill(0x111316, x - 2, 43.5, 4, 1.5)
        fill(0xF0604D, x - 0.5, 44, 1, 0.5, opacity: 0.7)
    }

    /// The dock's three lights: they climb in green while the vacuum charges; one amber light
    /// waits while it is out.
    func dockLights(isCharging: Bool, step: Int) {
        let x = RoomVacuum.dock.x
        let lit = isCharging ? (step / 3) % 4 : 1
        for light in 0..<3 {
            let color: UInt32 = light < lit ? (isCharging ? 0x4CC38A : 0xF2A93B) : 0x16181C
            fill(color, x - 2.75 + CGFloat(light) * 2, 35.5, 1.5, 1)
        }
    }

    /// The floor the vacuum just went over: a faint, clean strip that follows the corners it
    /// took and fades behind it.
    func vacuumTrail(_ points: [CGPoint]) {
        guard points.count > 1 else { return }
        let count = Double(points.count - 1)
        for (index, (from, to)) in zip(points, points.dropFirst()).enumerated() {
            var path = Path()
            path.move(to: CGPoint(x: from.x * unit, y: from.y * unit))
            path.addLine(to: CGPoint(x: to.x * unit, y: to.y * unit))
            let fade = 1 - Double(index) / count
            context.stroke(path, with: .color(Color.white.opacity(0.07 * fade * fade)),
                           style: StrokeStyle(lineWidth: 7 * unit, lineCap: .butt))
        }
    }

    /// The vacuum, seen a little from above: a low round body, its lid and its turret, a bumper
    /// on the side it is heading to, a light, and two side brushes that turn while it works.
    func vacuum(_ state: RoomVacuum.State, time: TimeInterval) {
        let x = state.position.x, y = state.position.y
        let ahead = state.heading
        ellipse(CGPoint(x: x, y: y + 2.4), 5.6, 2.6, color: Color.black.opacity(0.3))
        if !state.isDocked {
            // Side brushes, at the two front corners.
            let side = CGVector(dx: -ahead.dy, dy: ahead.dx)
            for sign: CGFloat in [-1, 1] {
                let hub = CGPoint(x: x + ahead.dx * 4 + side.dx * sign * 3.6, y: y + (ahead.dy * 4 + side.dy * sign * 3.6) * 0.7)
                for spoke in 0..<3 {
                    let angle = time * 9 * Double(sign) + Double(spoke) * 2 * .pi / 3
                    var path = Path()
                    path.move(to: CGPoint(x: hub.x * unit, y: hub.y * unit))
                    path.addLine(to: CGPoint(x: (hub.x + 1.7 * cos(angle)) * unit, y: (hub.y + 1.2 * sin(angle)) * unit))
                    context.stroke(path, with: .color(Color(hex: 0x9A9CA6)), lineWidth: 0.4 * unit)
                }
            }
        }
        let centre = CGPoint(x: x, y: y)
        ellipse(CGPoint(x: x, y: y + 1.1), 5, 3.5, color: Color(hex: 0x111316))
        ellipse(centre, 5, 3.5, color: Color(hex: 0x23262C))
        ellipse(CGPoint(x: x, y: y - 0.1), 4.4, 3, color: Color(hex: 0x363B44))
        ellipse(CGPoint(x: x - 1, y: y - 0.9), 2.6, 1.3, color: Color.white.opacity(0.07))
        ellipse(CGPoint(x: x, y: y + 0.3), 2.7, 1.8, color: Color(hex: 0x23262C))
        ellipse(CGPoint(x: x, y: y - 0.3), 1.6, 1.1, color: Color(hex: 0x16181C))
        ellipse(CGPoint(x: x, y: y - 0.6), 1.5, 1, color: Color(hex: 0x4A505B))
        fill(0x9A9CA6, x - 0.75, y - 1.2, 1, 0.5)

        // The bumper: a quarter of the rim, on the side it is heading to.
        let quarter: CGFloat = ahead.dx > 0 ? 0 : ahead.dy > 0 ? 0.25 : ahead.dx < 0 ? 0.5 : 0.75
        let rim = Path(ellipseIn: CGRect(x: (x - 5) * unit, y: (y - 3.5) * unit, width: 10 * unit, height: 7 * unit))
        let style = StrokeStyle(lineWidth: 0.7 * unit, lineCap: .round)
        let grey = GraphicsContext.Shading.color(Color(hex: 0x9A9CA6))
        if quarter == 0 {
            context.stroke(rim.trimmedPath(from: 0.89, to: 1), with: grey, style: style)
            context.stroke(rim.trimmedPath(from: 0, to: 0.11), with: grey, style: style)
        } else {
            context.stroke(rim.trimmedPath(from: quarter - 0.11, to: quarter + 0.11), with: grey, style: style)
        }

        let isBlinking = Int(time * 2) % 2 == 0
        let light: UInt32 = state.isDocked ? 0x4CC38A : (isBlinking ? 0x4FA8F7 : 0x1E3A56)
        fill(light, x + ahead.dx * 2.6 - 0.5, y + ahead.dy * 1.7 - 0.1, 1, 0.5)
    }

    // MARK: - Server room

    /// Three racks in a niche of the back wall, behind a glass front, on a raised floor.
    func servers() {
        fill(0x111316, 398, 5, 74, 41)
        fill(0x1A1D22, 400, 6, 70, 40)
        fill(0x2B2F36, 398, 46, 74, 6)
        fill(0x3A3F48, 398, 46, 74, 0.5)
        var tile: CGFloat = 398
        while tile < 472 {
            fill(0x3A3F48, tile, 46, 0.5, 6)
            tile += 9.25
        }
        fill(0x191310, 398, 51.5, 74, 0.5)
        // The cable tray overhead.
        fill(0x3A3F48, 400, 6.5, 70, 1)
        fill(0x4A505B, 400, 6.5, 70, 0.5)
        for (x, color) in [(411, 0x4FA8F7), (433.5, 0xE0B872), (456, 0xD97757)] as [(CGFloat, UInt32)] {
            fill(color, x, 7.5, 0.5, 2)
            fill(color, x + 1.5, 7.5, 0.5, 2)
        }
        for index in 0..<3 {
            rack(x: Self.rackLeft + CGFloat(index) * Self.rackPitch, y: Self.rackTop)
        }
        fill(0x4FA8F7, 398, 44, 74, 2, opacity: 0.1)
        // The glass front: its frame and two sheens.
        let sheen = Color.white.opacity(0.05)
        shape([CGPoint(x: 412, y: 5.5), CGPoint(x: 421, y: 5.5), CGPoint(x: 408, y: 46), CGPoint(x: 399, y: 46)], color: sheen)
        shape([CGPoint(x: 458, y: 5.5), CGPoint(x: 462, y: 5.5), CGPoint(x: 449, y: 46), CGPoint(x: 445, y: 46)], color: sheen)
        fill(0x70727E, 397, 4, 76, 1.5)
        fill(0x9A9CA6, 397, 4, 76, 0.5)
        fill(0x70727E, 397, 4, 1.5, 48)
        fill(0x70727E, 471.5, 4, 1.5, 48)
        fill(0x9A9CA6, 397, 4, 0.5, 48)
        // The keypad by the door.
        fill(0x2B2F36, 392.5, 24, 3, 5)
        fill(0x4A505B, 392.5, 24, 3, 0.5)
        fill(0x4CC38A, 393.5, 25, 1, 1)
        fill(0x70727E, 393, 27, 0.75, 0.75)
        fill(0x70727E, 394.25, 27, 0.75, 0.75)
    }

    private static let rackLeft: CGFloat = 402
    private static let rackPitch: CGFloat = 22.5
    private static let rackTop: CGFloat = 9.5

    /// The racks' lights, blinking: the only thing that moves in the server room. They follow
    /// the session quota: green, then amber from three quarters, then red from nine tenths, with
    /// a red bar flashing over the door.
    func serverLights(step: Int, quota: Double) {
        let busy: UInt32 = quota >= Self.strainedFrom ? 0xF0604D : quota >= Self.warnedFrom ? 0xF2A93B : 0x4CC38A
        let idle: UInt32 = quota >= Self.strainedFrom ? 0x3A1E1B : quota >= Self.warnedFrom ? 0x3A2C1A : 0x1F3A2C
        if quota >= Self.strainedFrom {
            fill(step % 4 < 2 ? 0xF0604D : 0x3A1E1B, 399, 5.5, 72, 1)
        }
        for index in 0..<3 {
            let x = Self.rackLeft + CGFloat(index) * Self.rackPitch
            for row in 0..<7 {
                let top = Self.rackTop + 3 + CGFloat(row) * 4.5
                let beat = step + index * 3 + row * 2
                fill(beat % 5 < 3 ? busy : idle, x + 3.5, top + 1.5, 1, 1)
                fill((beat + row) % 9 < 2 ? 0xF2A93B : 0x3A2C1A, x + 5.5, top + 1.5, 1, 1)
            }
        }
    }

    private func rack(x: CGFloat, y: CGFloat) {
        shadow(x, y + 37, 20, 1.5, opacity: 0.35)
        fill(0x23262C, x, y, 20, 37)
        fill(0x3A3F48, x, y, 20, 0.5)
        fill(0x2F333B, x, y, 0.5, 37)
        fill(0x16181C, x + 19.5, y, 0.5, 37)
        fill(0x1C1F24, x + 1.5, y + 2, 17, 33.5)
        for row in 0..<7 {
            let top = y + 3 + CGFloat(row) * 4.5
            fill(0x2B2F36, x + 2.5, top, 15, 3.5)
            fill(0x3A3F48, x + 2.5, top, 15, 0.5)
            fill(0x1F3A2C, x + 3.5, top + 1.5, 1, 1)
            fill(0x3A2C1A, x + 5.5, top + 1.5, 1, 1)
            for bay in 0..<4 { fill(0x3A3F48, x + 9 + CGFloat(bay) * 2, top + 1, 1.25, 1.75) }
        }
        fill(0x111316, x + 1, y + 37, 2, 1)
        fill(0x111316, x + 17, y + 37, 2, 1)
    }

    // MARK: - Lounge

    /// A rug in the middle of the floor, a sofa, a low table and a lamp.
    func lounge(isLit: Bool) {
        let cream = Color(hex: 0xEDE3D3)
        fill(cream.opacity(0.13), 178, 184, 124, 60)
        for (x, y, width, height) in [(178, 184, 124, 1), (178, 243, 124, 1), (178, 184, 1, 60), (301, 184, 1, 60)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            fill(cream.opacity(0.4), x, y, width, height)
        }
        for (x, y, width, height) in [(181, 187, 118, 0.5), (181, 240.5, 118, 0.5), (181, 187, 0.5, 54), (298.5, 187, 0.5, 54)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            fill(0xD97757, x, y, width, height, opacity: 0.55)
        }
        var fringe: CGFloat = 185
        while fringe < 243 {
            fill(cream.opacity(0.35), 176.5, fringe, 1.5, 0.5)
            fill(cream.opacity(0.35), 302, fringe, 1.5, 0.5)
            fringe += 2
        }

        // Lamp.
        shadow(187.5, 219, 8, 1.5)
        fill(0x2B2F36, 190.5, 197, 1, 21)
        fill(0x3A3F48, 190.5, 197, 0.5, 21)
        fill(0x2B2F36, 187, 217.5, 8, 1.5)
        fill(isLit ? 0xF2A93B : 0xD8CDB8, 186, 189, 10, 8)
        fill(isLit ? 0xC98A2C : 0xB5A898, 186, 189, 10, 1)
        fill(isLit ? 0xFFE3B0 : 0xEDE3D3, 186, 196, 10, 1)
        fill(Color.white.opacity(0.18), 186, 190, 1.5, 6)

        // Sofa.
        shadow(205, 213.5, 70, 2.5)
        fill(0x7A3D36, 208, 190, 64, 10)
        fill(0x9B4E45, 208, 190.5, 64, 3.5)
        fill(0xB5604F, 208, 190, 64, 0.5)
        for x: CGFloat in [204, 270] {
            fill(0x9B4E45, x, 194, 6, 18)
            fill(0xB5604F, x, 194, 6, 0.5)
            fill(0x7A3D36, x, 211.5, 6, 0.5)
        }
        for x: CGFloat in [210, 240.5] {
            fill(0xD97757, x, 199, 29.5, 9)
            fill(0xE9A07C, x, 199, 29.5, 1.5)
            fill(0xC0644A, x, 207, 29.5, 1)
        }
        fill(0x9B4E45, 239.5, 199, 1, 9)
        fill(0x9B4E45, 210, 208, 60, 4)
        fill(0x7A3D36, 210, 211.5, 60, 0.5)
        fill(0x4A332B, 206, 212, 2, 1.5)
        fill(0x4A332B, 272, 212, 2, 1.5)
        for (x, color, light) in [(212, 0xE0B872, 0xEDD29C), (260, 0x6FAE8F, 0x8FC7A8)] as [(CGFloat, UInt32, UInt32)] {
            fill(color, x, 194.5, 8, 6.5)
            fill(light, x, 194.5, 8, 1)
            shadow(x, 200.5, 8, 0.5, opacity: 0.2)
        }

        // Low table.
        shadow(223, 231.5, 34, 2)
        fill(0xB98D69, 222, 220, 36, 7)
        fill(0xC9A07B, 222, 220, 36, 0.5)
        fill(0xAD815F, 226, 224, 14, 0.5)
        fill(0x8C6248, 222, 227, 36, 2.5)
        fill(0x68463C, 222, 229, 36, 0.5)
        fill(0x4A332B, 223.5, 229.5, 1.5, 2.5)
        fill(0x4A332B, 255, 229.5, 1.5, 2.5)
        fill(0x4FA8F7, 227, 222, 8, 3.5)
        fill(0x9CCBF7, 227, 222, 8, 0.5)
        fill(Self.bubble, 227, 225.5, 8, 0.5)
        fill(Self.bubble, 240, 222.5, 3, 3)
        fill(Self.bubble, 243, 223.25, 0.75, 1.5)
        fill(0x8C6248, 240.5, 223, 2, 0.5)
        fill(0x9B4E45, 249.5, 223.5, 4, 2.5)
        fill(0x4F8A6D, 248.5, 221, 6, 3)
        fill(0x8FC7A8, 250.5, 220, 2, 2)

        tallPlant(at: CGPoint(x: 286, y: 197))
    }

    // MARK: - Door and plants

    /// The way in, in the front wall, and its mat.
    func door() {
        fill(0x1F1815, 0, 264, 480, 6)
        fill(0x2E2520, 6, 264, 468, 0.5)
        fill(0x382A22, 222, 264, 36, 6)
        fill(0x5E4D42, 220, 263, 2, 7)
        fill(0x5E4D42, 258, 263, 2, 7)
        fill(0x7A6556, 220, 263, 2, 0.5)
        fill(0x7A6556, 258, 263, 2, 0.5)
        shadow(224.5, 262, 32, 1, opacity: 0.2)
        fill(0x68463C, 224, 253, 32, 9)
        fill(0xB08462, 225, 254, 30, 7)
        for line in 0..<4 { fill(0x8C6248, 227, 255.5 + CGFloat(line) * 1.5, 26, 0.5) }
    }

    /// A round, leafy plant in a clay pot, 10 by 15 from its top left corner.
    func bush(at spot: CGPoint) {
        let x = spot.x, y = spot.y
        shadow(x + 1, y + 13.5, 8, 1.5)
        fill(0x7A3D36, x + 2.5, y + 13, 5, 1)
        fill(0x9B4E45, x + 2, y + 9, 6, 4.5)
        fill(0xB5604F, x + 1.5, y + 8.5, 7, 1.5)
        fill(0xC97A66, x + 1.5, y + 8.5, 7, 0.5)
        fill(0x4F8A6D, x, y + 3.5, 4, 5)
        fill(0x4F8A6D, x + 6.5, y + 4.5, 3.5, 4)
        fill(0x6FAE8F, x + 1, y + 1.5, 8, 7)
        fill(0x8FC7A8, x + 5, y, 3, 4)
        fill(0x8FC7A8, x + 2, y + 2.5, 2, 2)
        fill(0x4F8A6D, x + 4, y + 5, 0.5, 3.5)
        fill(0x4F8A6D, x + 6.5, y + 3, 0.5, 2)
    }

    /// A tall plant with upright leaves, 10 by 22 from its top left corner.
    func tallPlant(at spot: CGPoint) {
        let x = spot.x, y = spot.y
        shadow(x + 1, y + 20.5, 8, 1.5)
        for (offset, top, color) in [(1.5, 6, 0x4F8A6D), (3, 1, 0x6FAE8F), (4.75, 3.5, 0x8FC7A8), (6.25, 0, 0x6FAE8F), (7.75, 7, 0x4F8A6D)] as [(CGFloat, CGFloat, UInt32)] {
            fill(color, x + offset, y + top, 1.5, 16 - top)
            fill(Color.white.opacity(0.15), x + offset, y + top, 0.5, 16 - top)
        }
        fill(0x7A3D36, x + 2.5, y + 20, 5, 1)
        fill(0x9B4E45, x + 2, y + 16, 6, 4.5)
        fill(0xB5604F, x + 1.5, y + 15.5, 7, 1.5)
        fill(0xC97A66, x + 1.5, y + 15.5, 7, 0.5)
    }
}
