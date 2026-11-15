import SwiftUI

/// The room itself: its floor and its back wall, with the board, the clock and what hangs there.
/// Nothing here depends on the agents. The window is in `RoomPainter+Window`, what furnishes the
/// room in `RoomPainter+Decor`.
extension RoomPainter {

    /// What never moves: the floor, the walls and all that furnishes the room. Drawn once and
    /// kept as an image, since it is most of the room and none of it changes from one frame to
    /// the next. `week` is the tokens of the last seven days, each as a share of the busiest one.
    func stillBackdrop(title: String, week: [Double], isLit: Bool) {
        floorboards()
        walls()
        board(title: title, week: week)
        thermostat()
        clockFace()
        servers()
        dock()
        lowered(by: RoomGeometry.centreDrop).lounge(isLit: isLit)
        door()
        // Two plants under the back wall, clear of the vacuum's way and of the areas.
        bush(at: CGPoint(x: 346, y: 44))
        bush(at: CGPoint(x: 378, y: 44))
        tallPlant(at: CGPoint(x: 11, y: 241))
        bush(at: CGPoint(x: 24, y: 248))
        bush(at: CGPoint(x: 446, y: 248))
        tallPlant(at: CGPoint(x: 459, y: 241))
    }

    /// What moves in the backdrop, drawn over the still part on every frame: the day on the
    /// floor, the clock's hands, and the lights of the racks and of the dock. The window is a
    /// drawing of its own, laid over the room: it changes slowly, and the night must not dim it.
    func liveBackdrop(sky: RoomSky, weather: RoomWeather, step: Int, time: TimeInterval, date: Date, quota: Double) {
        sunlight(sky, strength: weather == .clear ? 1 : 0.3)
        clockHands(at: date)
        serverLights(step: step, quota: quota)
        dockLights(isCharging: RoomVacuum.state(at: time).isDocked, step: step)
    }

    /// A filled shape through points given in units: what a rectangle cannot draw.
    func shape(_ points: [CGPoint], color: Color) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.x * unit, y: first.y * unit))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x * unit, y: point.y * unit)) }
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    /// A filled ellipse, centre and radii in units.
    func ellipse(_ centre: CGPoint, _ across: CGFloat, _ down: CGFloat, color: Color) {
        let rect = CGRect(x: (centre.x - across) * unit, y: (centre.y - down) * unit,
                          width: across * 2 * unit, height: down * 2 * unit)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    /// A filled disc, centre and radius in units.
    func disc(_ centre: CGPoint, radius: CGFloat, color: Color) {
        let rect = CGRect(x: (centre.x - radius) * unit, y: (centre.y - radius) * unit,
                          width: radius * 2 * unit, height: radius * 2 * unit)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    private func floorboards() {
        for row in 0..<29 {
            let y = 44 + CGFloat(row) * 8
            fill(row % 2 == 0 ? 0x382A22 : 0x3B2D25, 0, y, 480, 8)
            fill(0x2F231C, 0, y, 480, 0.5)
            var x = CGFloat(row % 3) * 22 + 10
            var plank = 0
            while x < 480 + 62 {
                // No two planks are the same wood: each has its own tone and its own grain.
                let wood = (row * 31 + plank * 17) % 5
                let left = max(0, x - 62)
                if wood == 1 || wood == 3 { fill(Color.white.opacity(wood == 1 ? 0.03 : 0.015), left, y + 0.5, x - left, 7.5) }
                if wood == 0 || wood == 4 { fill(Color.black.opacity(wood == 0 ? 0.05 : 0.025), left, y + 0.5, x - left, 7.5) }
                fill(Color.black.opacity(0.07), left + 6 + CGFloat((row * 7 + plank * 13) % 24), y + 2.5 + CGFloat(wood % 3) * 1.5, 16, 0.5)
                fill(0x2F231C, x, y, 0.5, 8)
                fill(0x43342B, x + 0.5, y + 0.5, 0.5, 7.5)
                x += 62
                plank += 1
            }
        }
    }

    /// The light the window's three panes throw on the floor, leaning away from the sun.
    private func sunlight(_ sky: RoomSky, strength: Double) {
        guard let sun = sky.sun, sun.height > 0.15 else { return }
        let lean = CGFloat(0.5 - sun.across) * 22
        // The day spreads from the window over the floor, before the panes draw their shapes.
        let warm = Color(hex: 0xFFE9B8)
        let source = CGPoint(x: (87 + lean) * unit, y: 44 * unit)
        let reach = CGRect(x: max(6 * unit, source.x - 150 * unit), y: 46.5 * unit, width: 300 * unit, height: 108 * unit)
        context.fill(Path(reach), with: .radialGradient(Gradient(colors: [warm.opacity(0.13 * sun.height * strength), warm.opacity(0)]),
                                                        center: source, startRadius: 0, endRadius: 110 * unit))
        let color = warm.opacity(0.07 * sun.height * strength)
        for (left, right) in [(17, 62), (65, 109.5), (112.5, 157)] as [(CGFloat, CGFloat)] {
            shape([CGPoint(x: left, y: 46.5), CGPoint(x: right, y: 46.5),
                   CGPoint(x: max(7, right + lean), y: 58.5), CGPoint(x: max(7, left + lean), y: 58.5)], color: color)
        }
    }

    private func walls() {
        fill(0x2C231F, 6, 4, 468, 40)
        fill(0x3A2F29, 6, 4, 468, 0.5)
        fill(0x251D19, 6, 34, 468, 10)
        fill(0x3A2F29, 6, 33.5, 468, 0.5)
        var panel: CGFloat = 18
        while panel < 474 {
            fill(0x1F1815, panel, 35, 0.5, 6.5)
            panel += 24
        }
        // The wall is darker towards the ceiling.
        let wall = CGRect(x: 6 * unit, y: 4 * unit, width: 468 * unit, height: 30 * unit)
        context.fill(Path(wall), with: .linearGradient(Gradient(colors: [.black.opacity(0.28), .black.opacity(0)]),
                                                       startPoint: CGPoint(x: 0, y: wall.minY), endPoint: CGPoint(x: 0, y: wall.maxY)))
        fill(0x191310, 6, 42, 468, 2)
        fill(0x33291F, 6, 42, 468, 0.5)
        shadow(6, 44, 468, 2.5, opacity: 0.28)
        shadow(6, 46.5, 468, 2, opacity: 0.12)
        fill(0x1A1411, 0, 0, 480, 4)
        fill(0x1F1815, 0, 0, 6, 270)
        fill(0x1F1815, 474, 0, 6, 270)
        fill(0x2E2520, 5.5, 44, 0.5, 220)
        fill(0x2E2520, 474, 44, 0.5, 220)
    }

    /// The whiteboard: the project's name, a few lines, three notes, and the week as the card
    /// draws it, one bar a day, today last. No bar for a day with nothing.
    private func board(title: String, week: [Double]) {
        shadow(174, 38.5, 134, 1.5, opacity: 0.25)
        fill(0x5E4D42, 173, 6, 134, 32)
        fill(0x7A6556, 173, 6, 134, 0.5)
        fill(Self.bubble, 175, 8, 130, 27)
        fill(0xFFFFFF, 175, 8, 130, 0.5)
        text(title, x: 182, y: 14.5, size: 14, weight: .bold, color: Color(hex: 0x2A1418), width: 50)
        fill(0xD97757, 182, 21, 34, 1)
        fill(0xCFC3AE, 182, 25, 40, 0.5)
        fill(0xCFC3AE, 182, 28, 30, 0.5)
        fill(0xCFC3AE, 182, 31, 36, 0.5)
        for (index, share) in week.suffix(7).enumerated() where share > 0 {
            let x = 232 + CGFloat(index) * 7
            let height = max(1, (CGFloat(min(share, 1)) * 14 * 2).rounded() / 2)
            fill(0xD97757, x, 31 - height, 5, height)
            fill(0xE9A07C, x, 31 - height, 5, 0.5)
        }
        fill(0xB5A898, 230, 31, 51, 0.5)
        let notes: [(CGFloat, CGFloat, UInt32)] = [(286, 11, 0xE0B872), (293, 12, 0x9CCBF7), (288, 19, 0xE9A07C)]
        for (x, y, color) in notes {
            shadow(x + 0.5, y + 0.5, 6, 6, opacity: 0.15)
            fill(color, x, y, 6, 6)
            fill(0x2A1418, x + 1, y + 2, 3.5, 0.5, opacity: 0.5)
            fill(0x2A1418, x + 1, y + 3.5, 2.5, 0.5, opacity: 0.5)
        }
        fill(0x6E5B4E, 173, 38, 134, 1.5)
        fill(0x8A7363, 173, 38, 134, 0.5)
        fill(0xD97757, 190, 37, 5, 1)
        fill(0x4FA8F7, 198, 37, 5, 1)
        fill(0x2A1418, 206, 37, 5, 1)
        fill(0x3A3F48, 288, 36.5, 8, 1.5)
        fill(0xEDE3D3, 288, 37.5, 8, 0.5)
    }

    /// A thermostat on the wall between the window and the board.
    private func thermostat() {
        fill(0x4A3C34, 164, 17.5, 5, 6)
        fill(0xEDE3D3, 164.5, 18, 4, 5)
        fill(0x2B2F36, 165, 18.5, 3, 2)
        fill(0x4CC38A, 165.5, 19, 1, 1)
        fill(0xB5A898, 165, 21.5, 3, 0.5)
    }

    private static let clockCentre = CGPoint(x: 366.5, y: 17)

    /// The wall clock without its hands: its frame and its twelve marks.
    private func clockFace() {
        let centre = Self.clockCentre
        let left = centre.x - 7.5
        shadow(left + 0.5, 10, 15, 15, opacity: 0.25)
        fill(0x5E4D42, left, 9, 15, 16)
        fill(0x4A3C34, left - 0.5, 9.5, 16, 15)
        fill(0x7A6556, left, 9, 15, 0.5)
        fill(Self.bubble, left + 1, 10.5, 13, 13)
        for mark in 0..<12 {
            let angle = Double(mark) / 12 * 2 * .pi
            let size: CGFloat = mark % 3 == 0 ? 1 : 0.5
            fill(0x8A7363, centre.x + 5.25 * sin(angle) - size / 2, centre.y - 5.25 * cos(angle) - size / 2, size, size)
        }
    }

    /// The clock's hands, at the Mac's time.
    private func clockHands(at date: Date) {
        let centre = Self.clockCentre
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = Double(parts.minute ?? 0)
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
        hand(from: centre, angle: hours / 12 * 2 * .pi, length: 3, width: 1, color: 0x2A1418)
        hand(from: centre, angle: minutes / 60 * 2 * .pi, length: 4.5, width: 0.75, color: 0x2A1418)
        fill(0xD97757, centre.x - 0.5, centre.y - 0.5, 1, 1)
    }

    private func hand(from centre: CGPoint, angle: Double, length: CGFloat, width: CGFloat, color: UInt32) {
        var path = Path()
        path.move(to: CGPoint(x: centre.x * unit, y: centre.y * unit))
        path.addLine(to: CGPoint(x: (centre.x + length * sin(angle)) * unit, y: (centre.y - length * cos(angle)) * unit))
        context.stroke(path, with: .color(Color(hex: color)), style: StrokeStyle(lineWidth: width * unit, lineCap: .round))
    }

    /// A line of text in the app's rounded face, in a box `width` wide from `x`, its middle at
    /// `y`. `size` is in points at the room's usual scale.
    func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: Font.Weight, color: Color,
              width: CGFloat, isCentred: Bool = false) {
        let label = Text(string).font(Theme.Font.label(size * unit / 2, weight)).foregroundColor(color)
        let resolved = context.resolve(label)
        let measured = resolved.measure(in: CGSize(width: width * unit, height: 100))
        let left = isCentred ? x * unit + (width * unit - measured.width) / 2 : x * unit
        context.draw(resolved, in: CGRect(x: left, y: y * unit - measured.height / 2,
                                          width: measured.width, height: measured.height))
    }
}
