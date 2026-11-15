import SwiftUI

/// Draws the agent room in its own units, 480 by 270: one unit is `unit` points. Claudy is pixel
/// art, one unit a pixel; the furniture uses half units for its detail.
struct RoomPainter {
    var context: GraphicsContext
    let unit: CGFloat
    /// The symbols the canvas made into images once, by `RoomGlyph.tag`.
    var stamps: [String: Image] = [:]

    static let ink: UInt32 = 0x1F1A17
    static let bubble: UInt32 = 0xF1E6D2
    static let floor: UInt32 = 0x3A2C24

    func fill(_ hex: UInt32, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, opacity: Double = 1) {
        fill(Color(hex: hex).opacity(opacity), x, y, width, height)
    }

    func fill(_ color: Color, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        let rect = CGRect(x: x * unit, y: y * unit, width: width * unit, height: height * unit)
        context.fill(Path(rect), with: .color(color))
    }

    /// The same painter, drawing `drop` units lower.
    func lowered(by drop: CGFloat) -> RoomPainter {
        var copy = self
        copy.context.translateBy(x: 0, y: drop * unit)
        return copy
    }

    /// A shadow on the floor, feathered: three layers, each half a unit inside the last.
    func shadow(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, opacity: Double = 0.22) {
        let layer = Color.black.opacity(opacity / 3)
        fill(layer, x - 0.5, y - 0.5, width + 1, height + 1)
        fill(layer, x, y, width, height)
        fill(layer, x + min(0.5, width / 4), y + min(0.5, height / 4), max(width - 1, width / 2), max(height - 1, height / 2))
    }

    // MARK: - Claudy

    /// A frame of rows of inks, one unit a cell, each ink painted as the app's sprite paints it.
    func sprite(_ rows: [String], x: CGFloat, y: CGFloat, tint: Color) {
        var paths: [Character: Path] = [:]
        for (row, line) in rows.enumerated() {
            for (column, ink) in line.enumerated() where ink != "." {
                paths[ink, default: Path()].addRect(CGRect(x: (x + CGFloat(column)) * unit, y: (y + CGFloat(row)) * unit,
                                                           width: unit, height: unit))
            }
        }
        for (ink, path) in paths {
            for color in ClaudyTyping.colors(for: ink, tint: tint) {
                context.fill(path, with: .color(color))
            }
        }
    }

    /// A standing or walking Claudy, placed by the middle of its feet.
    func claudy(_ pose: RoomSprite.Pose, feet: CGPoint, tint: Color) {
        sprite(RoomSprite.frame(pose), x: feet.x - 8, y: feet.y - CGFloat(RoomSprite.rows), tint: tint)
    }

    /// Two arms from a seated Claudy's body down to its keyboard, alternating when it types.
    /// `x` is the left edge of the body, `y` the top of the arms.
    func arms(x: CGFloat, y: CGFloat, tint: Color, isTyping: Bool, beat: Int) {
        let left: CGFloat = isTyping ? (beat % 2 == 0 ? 5 : 6) : 5
        let right: CGFloat = isTyping ? (beat % 2 == 0 ? 6 : 5) : 5
        for (offset, length) in [(CGFloat(2), left), (CGFloat(10), right)] {
            fill(tint, x + offset, y, 4, length + 1)
            fill(Theme.Pixel.outline, x + offset, y, 4, length + 1)
        }
        fill(tint, x + 3, y, 2, left)
        fill(tint, x + 11, y, 2, right)
        fill(Theme.Pixel.shade, x + 11, y, 2, right)
    }

    // MARK: - Screens

    /// A system symbol centred on a point of the scene. `points` is its size at the room's
    /// usual scale. The canvas hands over the symbols it made into images once; one it does not
    /// have is resolved here, on every frame.
    func symbol(_ name: String, centre: CGPoint, points: CGFloat, color: UInt32) {
        let place = CGPoint(x: centre.x * unit, y: centre.y * unit)
        if let stamp = stamps[RoomGlyph.tag(name, color: color, points: points)] {
            context.draw(stamp, at: place, anchor: .center)
            return
        }
        let image = Text(Image(systemName: name))
            .font(.system(size: points * unit / 2, weight: .semibold))
            .foregroundColor(Color(hex: color))
        context.draw(context.resolve(image), at: place, anchor: .center)
    }

    /// The work a walking Claudy goes to, in a bubble over its head.
    func bubble(_ name: String, x: CGFloat, y: CGFloat) {
        fill(Self.ink, x + 0.5, y - 0.5, 10, 12)
        fill(Self.ink, x - 0.5, y + 0.5, 12, 10)
        fill(Self.bubble, x + 1, y, 9, 11)
        fill(Self.bubble, x, y + 1, 11, 9)
        fill(Self.bubble, x + 4, y + 11, 3, 1)
        fill(Self.bubble, x + 5, y + 12, 1, 1)
        symbol(name, centre: CGPoint(x: x + 5.5, y: y + 5.5), points: 12, color: Self.ink)
    }

    /// A monitor facing the viewer, 15 by 13 plus its stand, a glyph on its screen.
    func monitor(x: CGFloat, y: CGFloat, screen: UInt32, glyph name: String?, color: UInt32 = 0xC8E4FF) {
        fill(0x1C1F24, x + 6.5, y + 13, 2, 2.5)
        fill(0x2B2F36, x + 4, y + 15, 7, 1)
        fill(0x3A3F48, x + 4, y + 15, 7, 0.5)
        fill(0x23262C, x + 0.5, y, 14, 13)
        fill(0x23262C, x, y + 0.5, 15, 12)
        fill(0x111316, x + 0.5, y + 0.5, 14, 12)
        fill(screen, x + 1, y + 1, 13, 10.5)
        fill(Color.white.opacity(0.07), x + 1, y + 1, 13, 3)
        fill(0x2B2F36, x + 0.5, y + 11.5, 14, 1)
        fill(name == nil ? 0x4A505B : 0x4CC38A, x + 12.5, y + 11.75, 1, 0.5)
        if let name { symbol(name, centre: CGPoint(x: x + 7.5, y: y + 6.25), points: 13, color: color) }
    }

    /// What a desk's screen shows for its occupant: the colour of its glass, its symbol and the
    /// symbol's colour. `nil` for an empty desk.
    private func look(of occupant: RoomOccupant?, step: Int) -> (screen: UInt32, name: String?, color: UInt32)? {
        guard let occupant else { return nil }
        let beat = step + occupant.phase
        var look: (screen: UInt32, name: String?, color: UInt32)
        switch occupant.state {
        case .working: look = (0x1E2B36, occupant.glyph, 0xC8E4FF)
        case .idle: look = (0x1E2B36, occupant.glyph, 0x5E7C93)
        case .waiting: look = (beat % 4 >= 2 ? 0xC98A2C : 0xF2A93B, RoomGlyph.waiting, Self.ink)
        case .stalled: look = (0x3A1E1B, RoomGlyph.stalled, 0xF0604D)
        case .done: look = (0x1F3A2C, RoomGlyph.done, 0x4CC38A)
        }
        if occupant.isFlashing { look.screen = 0xC8E4FF }
        return look
    }

    /// The whole monitor of a desk, with what it shows.
    func screen(at desk: CGPoint, of occupant: RoomOccupant?, step: Int) {
        guard let look = look(of: occupant, step: step) else {
            monitor(x: desk.x + 1, y: desk.y + 1, screen: 0x16181C, glyph: nil)
            return
        }
        monitor(x: desk.x + 1, y: desk.y + 1, screen: look.screen, glyph: look.name, color: look.color)
    }

    /// The glass of a desk's monitor alone, over a monitor already drawn: for the desks drawn
    /// from their kept image, and to light the screens again after the night dimmed the room.
    func screenFace(at desk: CGPoint, of occupant: RoomOccupant?, step: Int) {
        guard let look = look(of: occupant, step: step) else { return }
        let x = desk.x + 1, y = desk.y + 1
        fill(look.screen, x + 1, y + 1, 13, 10.5)
        fill(Color.white.opacity(0.07), x + 1, y + 1, 13, 3)
        fill(0x4CC38A, x + 12.5, y + 11.75, 1, 0.5)
        if let name = look.name { symbol(name, centre: CGPoint(x: x + 7.5, y: y + 6.25), points: 13, color: look.color) }
    }

    // MARK: - Desks

    /// The furniture of a desk, which never changes, in two layers kept as images: the chair,
    /// behind whoever sits there, and the desk itself with its dark monitor and its keyboard.
    struct DeskArt {
        let chair: Image
        let desk: Image
        /// Units of margin round the desk in both images, for its shadow.
        static let margin: CGFloat = 2
        static let size = CGSize(width: RoomGeometry.deskSize.width + margin * 2, height: RoomGeometry.deskSize.height + margin * 2)
    }

    /// The chair of a desk and the shadow under the desk: what is behind its occupant.
    func deskChair(at origin: CGPoint) {
        let x = origin.x, y = origin.y
        shadow(x + 1, y + 29, 34, 2)
        fill(0x2A2320, x + 19, y + 2.5, 12, 14)
        fill(0x2A2320, x + 18.5, y + 3, 13, 13)
        fill(0x3A302B, x + 19.5, y + 3.5, 11, 12)
        fill(0x453A34, x + 19.5, y + 3.5, 11, 0.5)
        fill(0x2A2320, x + 17, y + 9.5, 1.5, 6)
        fill(0x2A2320, x + 31.5, y + 9.5, 1.5, 6)
        fill(0x3A302B, x + 17, y + 9.5, 1.5, 0.5)
        fill(0x3A302B, x + 31.5, y + 9.5, 1.5, 0.5)
    }

    /// The desk in front of its occupant: its top, its front, its monitor switched off and its
    /// keyboard.
    func deskBody(at origin: CGPoint) {
        let x = origin.x, y = origin.y
        top(x: x, y: y + 15, width: 36, depth: 8, grain: [(3, 3, 9), (14, 7, 12)])
        front(x: x, y: y + 23, width: 36, height: 6, dividers: [12, 24], handles: [4.5, 16.5, 28.5])
        monitor(x: x + 1, y: y + 1, screen: 0x16181C, glyph: nil)
        keyboard(x: x + 18, y: y + 18, keys: 8, isLit: false)
    }

    /// One desk seen from the front and a little above, 36 by 31: the monitor at the back left
    /// of the top, Claudy behind it on the right, its arms on the keyboard. With `art` the
    /// furniture comes from its kept images and only what lives is drawn.
    func desk(at origin: CGPoint, occupant: RoomOccupant?, step: Int, art: DeskArt? = nil) {
        let x = origin.x, y = origin.y
        let beat = step + (occupant?.phase ?? 0)
        let margin = DeskArt.margin
        let frame = CGRect(x: (x - margin) * unit, y: (y - margin) * unit,
                           width: DeskArt.size.width * unit, height: DeskArt.size.height * unit)
        if let art { context.draw(art.chair, in: frame) } else { deskChair(at: origin) }
        if let occupant {
            sprite(RoomSprite.frame(beat % 23 == 0 || occupant.state == .idle ? .sitBlink : .sit), x: x + 17, y: y + 4,
                   tint: occupant.tint)
        }
        if let art { context.draw(art.desk, in: frame) } else { deskBody(at: origin) }
        guard let occupant else { return }
        // A lit screen throws its light on the desk.
        if occupant.state != .stalled {
            fill(0xC8E4FF, x + 2, y + 16.5, 13, 1.5, opacity: 0.16)
            fill(0xC8E4FF, x + 3, y + 18, 11, 1, opacity: 0.08)
        }
        screenFace(at: origin, of: occupant, step: step)
        fill(0x9A9CA6, x + 18.5, y + 18.5, 13, 2.5)
        for key in 0..<8 { fill(0x3A3F48, x + 19.5 + CGFloat(key) * 1.5, y + 18.5, 0.5, 2.5) }
        arms(x: x + 17, y: y + 12, tint: occupant.tint, isTyping: occupant.state == .working, beat: beat)
        if occupant.state == .idle { doze(x: x + 30, y: y + 2, step: step + occupant.phase) }
        switch occupant.phase % 3 {
        case 0:
            fill(Self.bubble, x + 33, y + 19, 2, 2.5)
            fill(0x8C6248, x + 33.5, y + 19.5, 1, 0.5)
        case 1:
            fill(0xEDE3D3, x + 32.5, y + 19.5, 3, 2)
            fill(0xB5A898, x + 33, y + 20, 2, 0.5)
        default:
            fill(0x9B4E45, x + 32.5, y + 19.5, 3, 2.5)
            fill(0x6FAE8F, x + 32, y + 17, 4, 3)
            fill(0x8FC7A8, x + 33.5, y + 16.5, 1.5, 1.5)
        }
    }

    /// Three small z's rising from a Claudy that waits, eyes closed: it dozes until its command
    /// or its parent answers.
    func doze(x: CGFloat, y: CGFloat, step: Int) {
        let glyph = [[1, 1, 1], [0, 1, 0], [1, 1, 1]]
        for letter in 0..<3 {
            let rise = CGFloat((step + letter * 3) % 9)
            let left = x + CGFloat(letter) * 2.5 + rise * 0.3, top = y - CGFloat(letter) * 2.5 - rise * 0.5
            let size: CGFloat = 0.5 + CGFloat(letter) * 0.25
            for (row, cells) in glyph.enumerated() {
                for (column, cell) in cells.enumerated() where cell == 1 {
                    fill(Color(hex: Self.bubble).opacity(0.85 - Double(rise) * 0.08),
                         left + CGFloat(column) * size, top + CGFloat(row) * size, size, size)
                }
            }
        }
    }

    /// The top of a desk, lit along its far edge, with a few lines of grain.
    func top(x: CGFloat, y: CGFloat, width: CGFloat, depth: CGFloat, grain: [(CGFloat, CGFloat, CGFloat)]) {
        fill(0xB98D69, x, y, width, depth)
        // The light comes from the window, on the left: the top is paler there.
        fill(Color.white.opacity(0.07), x, y, width / 3, depth)
        fill(Color.black.opacity(0.07), x + width * 0.72, y, width * 0.28, depth)
        fill(0xC9A07B, x, y, width, 0.5)
        for (offset, down, length) in grain { fill(0xAD815F, x + offset, y + down, length, 0.5) }
    }

    /// The front of a desk: its lip, its drawers, its feet.
    func front(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, dividers: [CGFloat], handles: [CGFloat]) {
        fill(0x9A6F52, x, y, width, 1)
        fill(0x8C6248, x, y + 1, width, height - 1)
        for divider in dividers { fill(0x6E4A3C, x + divider, y + 1, 0.5, height - 1) }
        for handle in handles { fill(0xC9A07B, x + handle, y + 3, 3, 0.5) }
        fill(0x68463C, x, y + height - 0.5, width, 0.5)
        fill(0x4A332B, x + 1, y + height, 2, 1)
        fill(0x4A332B, x + width - 3, y + height, 2, 1)
    }

    func keyboard(x: CGFloat, y: CGFloat, keys: Int, isLit: Bool) {
        let width = CGFloat(keys) * 1.5 + 2
        fill(0x3A3F48, x, y, width, 3.5)
        fill(isLit ? 0x9A9CA6 : 0x5A5C64, x + 0.5, y + 0.5, width - 1, 2.5)
        for key in 0..<keys { fill(0x3A3F48, x + 1.5 + CGFloat(key) * 1.5, y + 0.5, 0.5, 2.5) }
    }
}
