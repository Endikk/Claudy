import AppKit
import SwiftUI

/// The Claude mascot in isometric pixel art, typing at a laptop on a small desk. Built on the
/// 2:1 isometric grid with the light from the top left: lit top, mid-tone left face, dark right
/// face, and a tinted outline rather than a black one. Three frames: hands resting, left hand on
/// the keys, right hand on the keys. Drawn cell by cell in a Canvas, so there is no image asset
/// and the body takes whatever tint the caller passes.
struct ClaudyTyping: View {
    /// Body colour. The top face, flank and outline are derived from it.
    var tint: Color = Theme.Accent.coral.color
    /// Plays the typing loop when true; shows the resting frame otherwise.
    var isTyping: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// Width over height of the sprite; callers size the frame with it.
    static let aspectRatio = CGFloat(Sprite.columns) / CGFloat(Sprite.rows)

    static let frameDuration: TimeInterval = 0.16

    enum Pose { case resting, leftDown, rightDown }

    /// left, right, left, right, then a beat reading the screen.
    static let sequence: [Pose] = [.leftDown, .rightDown, .leftDown, .rightDown, .resting, .resting]

    var body: some View {
        if isTyping && !reduceMotion {
            TimelineView(.periodic(from: .now, by: Self.frameDuration)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.frameDuration)
                canvas(Self.sequence[tick % Self.sequence.count])
            }
        } else {
            canvas(.resting)
        }
    }

    private func canvas(_ pose: Pose) -> some View {
        let frame = Sprite.frame(pose)
        let tint = tint
        return Canvas { context, size in
            let raw = min(size.width / CGFloat(Sprite.columns), size.height / CGFloat(Sprite.rows))
            // Snap the cell to whole device pixels so edges stay crisp.
            let cell = max(1, (raw * displayScale).rounded(.down)) / displayScale
            let originX = ((size.width - cell * CGFloat(Sprite.columns)) / 2 * displayScale).rounded() / displayScale
            let originY = ((size.height - cell * CGFloat(Sprite.rows)) / 2 * displayScale).rounded() / displayScale

            var paths: [Character: Path] = [:]
            for (row, line) in frame.enumerated() {
                for (column, ink) in line.enumerated() where ink != "." {
                    paths[ink, default: Path()].addRect(CGRect(
                        x: originX + CGFloat(column) * cell,
                        y: originY + CGFloat(row) * cell,
                        width: cell, height: cell
                    ))
                }
            }
            for (ink, path) in paths {
                for color in Self.colors(for: ink, tint: tint) {
                    context.fill(path, with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Colours stacked on each ink, bottom first. Faces derived from the tint are the tint under
    /// an overlay, since Color.mix needs macOS 15.
    private static func colors(for ink: Character, tint: Color) -> [Color] {
        switch ink {
        case "C": return [tint]
        case "T": return [tint, Theme.Pixel.highlight]
        case "D": return [tint, Theme.Pixel.shade]
        case "o": return [tint, Theme.Pixel.outline]
        case "E": return [Theme.Pixel.eye]
        case "O": return [tint]
        case "k": return [Theme.Pixel.keys]
        case "K": return [Theme.Pixel.laptop]
        case "L": return [Theme.Pixel.lid]
        case "G": return [Theme.Pixel.screenGlow]
        case "w": return [Theme.Pixel.deskTop]
        case "W": return [Theme.Pixel.deskFront]
        case "V": return [Theme.Pixel.deskSide]
        default:  return []
        }
    }

    /// One frame as a bitmap, for places SwiftUI does not reach such as the menu bar.
    /// `cell` is the side of one sprite pixel in points; half a point lands on whole pixels on
    /// Retina screens.
    static func image(_ pose: Pose, tint: Color, cell: CGFloat) -> NSImage {
        let frame = Sprite.frame(pose)
        let size = NSSize(width: CGFloat(Sprite.columns) * cell, height: CGFloat(Sprite.rows) * cell)
        return NSImage(size: size, flipped: true) { _ in
            for (row, line) in frame.enumerated() {
                for (column, ink) in line.enumerated() where ink != "." {
                    let rect = NSRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                      width: cell, height: cell)
                    for color in colors(for: ink, tint: tint) {
                        NSColor(color).setFill()
                        rect.fill(using: .sourceOver)
                    }
                }
            }
            return true
        }
    }
}

/// The three frames, one character per cell. Generated from a 2:1 isometric scene of boxes
/// (body, legs, arms, desk, keyboard, lid), then kept as data so each pixel can be edited by hand.
///
///   C body, left face   T body, top    D body, right face   o outline   E eye   O logo
///   k keys   K laptop edge   L lid back   G screen glow on the lid edge
///   w desk top   W desk front   V desk side   . empty
private enum Sprite {
        static let resting: [String] = [
            "...............oo............",
            ".............ooTToo..........",
            "...........ooTTTTTToo........",
            "..........oTTTTTTTTTToo......",
            ".........oCTTTTTTTTTTTToo....",
            ".........oCCCTTTTTTTTTTTToo..",
            ".........oCCCCCTTTTTTTTTTTTo.",
            ".........oCCCECCCTTTTTTTTTTDo",
            ".........oCCCECCCCCTTTTTTDDDo",
            ".........oCCCCCCCCECCTTDDDDDo",
            ".........oCTTCCCCCECCCDDDDDDo",
            "........oTTTTDCCCCCCCCDDDDDDo",
            ".....oooCTTDDDCCCCCCCCDDDDDDo",
            "....oGGwCCDDDCCCCTTCCCDDDDDDo",
            "...ooLLGGCDooooTTTTDCCDDDDDDo",
            ".oowwLLLLGGkkoCTTDDDCCDDDDDo.",
            "owwwwLLLOLLGGkCCDDDCCCDDDCDo.",
            "oWWwwKKLLOLLLKkCDooooCDooCDo.",
            "oWWWWwwKKLLLLKkkkKwoooo.oCDo.",
            "oWWWWWWwwKKLLKkKKwwwwo...oo..",
            ".ooWWWWWWwwKKKKwwwwwwVo......",
            "...ooWWWWWWwwwwwwwwVVVo......",
            ".....ooWWWWWWwwwwVVVVVo......",
            ".......ooWWWWWWVVVVVVo.......",
            ".........ooWWWWVVVVoo........",
            "...........ooWWVVoo..........",
            ".............oooo............"
        ]

        static let leftDown: [String] = [
            "...............oo............",
            ".............ooTToo..........",
            "...........ooTTTTTToo........",
            "..........oTTTTTTTTTToo......",
            ".........oCTTTTTTTTTTTToo....",
            ".........oCCCTTTTTTTTTTTToo..",
            ".........oCCCCCTTTTTTTTTTTTo.",
            ".........oCCCECCCTTTTTTTTTTDo",
            ".........oCCCECCCCCTTTTTTDDDo",
            ".........oCCCCCCCCECCTTDDDDDo",
            ".........oCCCCCCCCECCCDDDDDDo",
            ".........oCTTCCCCCCCCCDDDDDDo",
            ".....ooooTTTTDCCCCCCCCDDDDDDo",
            "....oGGwCTTDDDCCCTTCCCDDDDDDo",
            "...ooLLGGCDDDooTTTTDCCDDDDDDo",
            ".oowwLLLLGGkkoCTTDDDCCDDDDDo.",
            "owwwwLLLOLLGGkCCDDDCCCDDDCDo.",
            "oWWwwKKLLOLLLKkCDooooCDooCDo.",
            "oWWWWwwKKLLLLKkkkKwoooo.oCDo.",
            "oWWWWWWwwKKLLKkKKwwwwo...oo..",
            ".ooWWWWWWwwKKKKwwwwwwVo......",
            "...ooWWWWWWwwwwwwwwVVVo......",
            ".....ooWWWWWWwwwwVVVVVo......",
            ".......ooWWWWWWVVVVVVo.......",
            ".........ooWWWWVVVVoo........",
            "...........ooWWVVoo..........",
            ".............oooo............"
        ]

        static let rightDown: [String] = [
            "...............oo............",
            ".............ooTToo..........",
            "...........ooTTTTTToo........",
            "..........oTTTTTTTTTToo......",
            ".........oCTTTTTTTTTTTToo....",
            ".........oCCCTTTTTTTTTTTToo..",
            ".........oCCCCCTTTTTTTTTTTTo.",
            ".........oCCCECCCTTTTTTTTTTDo",
            ".........oCCCECCCCCTTTTTTDDDo",
            ".........oCCCCCCCCECCTTDDDDDo",
            ".........oCTTCCCCCECCCDDDDDDo",
            "........oTTTTDCCCCCCCCDDDDDDo",
            ".....oooCTTDDDCCCCCCCCDDDDDDo",
            "....oGGwCCDDDCCCCCCCCCDDDDDDo",
            "...ooLLGGCDooooCCTTCCCDDDDDDo",
            ".oowwLLLLGGkkooTTTTDCCDDDDDo.",
            "owwwwLLLOLLGGkCTTDDDCCDDDCDo.",
            "oWWwwKKLLOLLLKCCDDDooCDooCDo.",
            "oWWWWwwKKLLLLKkCDKwoooo.oCDo.",
            "oWWWWWWwwKKLLKkKKwwwwo...oo..",
            ".ooWWWWWWwwKKKKwwwwwwVo......",
            "...ooWWWWWWwwwwwwwwVVVo......",
            ".....ooWWWWWWwwwwVVVVVo......",
            ".......ooWWWWWWVVVVVVo.......",
            ".........ooWWWWVVVVoo........",
            "...........ooWWVVoo..........",
            ".............oooo............"
        ]

    static let rows = resting.count
    static let columns = resting[0].count

    static func frame(_ pose: ClaudyTyping.Pose) -> [String] {
        switch pose {
        case .resting:   return resting
        case .leftDown:  return leftDown
        case .rightDown: return rightDown
        }
    }
}
