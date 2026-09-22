import AppKit
import SwiftUI

/// The Claude mascot in isometric pixel art, typing at a laptop on a small desk. Built on the
/// 2:1 isometric grid with the light from the top left: lit top, mid-tone left face, dark right
/// face, and a tinted outline rather than a black one. Three frames: hands resting, left hand on
/// the keys, right hand on the keys. Drawn cell by cell in a Canvas, so there is no image asset
/// and the body takes whatever tint the caller passes.
///
/// When a quota fills up, the laptop explodes once and Claude stays dead until it frees up
/// (`ClaudyOverload`). The explosion needs room, so the drawing overflows the view's frame on
/// every side without changing its layout size.
struct ClaudyTyping: View {
    /// Body colour. The top face, flank and outline are derived from it.
    var tint: Color = Theme.Accent.coral.color
    /// Plays the typing loop when true; shows the resting frame otherwise.
    var isTyping: Bool = true
    /// A quota is full. Turning true while on screen plays the explosion; already true on
    /// appear goes straight to the dead state, since nobody saw it happen.
    var isOverloaded: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// When the explosion started; `nil` outside the one-off intro.
    @State private var overloadStart: Date?

    /// Width over height of the sprite; callers size the frame with it.
    static let aspectRatio = CGFloat(Sprite.columns) / CGFloat(Sprite.rows)

    static let frameDuration: TimeInterval = 0.16

    enum Pose { case resting, leftDown, rightDown }

    /// left, right, left, right, then a beat reading the screen.
    static let sequence: [Pose] = [.leftDown, .rightDown, .leftDown, .rightDown, .resting, .resting]

    /// Redraw pace: fine enough for the explosion's 70 ms frames, then half of the dead loop's.
    private static let introTick: TimeInterval = 0.035
    private static let deadTick: TimeInterval = 0.13

    var body: some View {
        Color.clear
            .overlay(GeometryReader { geometry in drawing(in: geometry.size) })
            .accessibilityHidden(true)
            .onChange(of: isOverloaded) { overloaded in
                overloadStart = overloaded ? Date() : nil
            }
            .task(id: overloadStart) {
                // Hand over to the slower dead-loop pace once the intro is over.
                guard overloadStart != nil else { return }
                try? await Task.sleep(nanoseconds: UInt64(ClaudyOverload.introDuration * 1_000_000_000))
                if !Task.isCancelled { overloadStart = nil }
            }
    }

    @ViewBuilder
    private func drawing(in size: CGSize) -> some View {
        if isOverloaded {
            if reduceMotion {
                canvas(ClaudyOverload.frames[ClaudyOverload.frameIndex(elapsed: nil)], in: size)
            } else if let overloadStart {
                TimelineView(.periodic(from: .now, by: Self.introTick)) { context in
                    let elapsed = context.date.timeIntervalSince(overloadStart)
                    canvas(ClaudyOverload.frames[ClaudyOverload.frameIndex(elapsed: elapsed)], in: size)
                }
            } else {
                TimelineView(.periodic(from: .now, by: Self.deadTick)) { context in
                    // Any time past the intro lands in the dead loop.
                    let elapsed = ClaudyOverload.introDuration + context.date.timeIntervalSinceReferenceDate
                    canvas(ClaudyOverload.frames[ClaudyOverload.frameIndex(elapsed: elapsed)], in: size)
                }
            }
        } else if isTyping && !reduceMotion {
            TimelineView(.periodic(from: .now, by: Self.frameDuration)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.frameDuration)
                canvas(Sprite.frame(Self.sequence[tick % Self.sequence.count]), in: size, embedded: true)
            }
        } else {
            canvas(Sprite.frame(.resting), in: size, embedded: true)
        }
    }

    /// Draws a frame on the overload grid, which frames the sprite with room on every side.
    /// `embedded` frames are sprite-sized and placed at the sprite's spot in that grid.
    private func canvas(_ frame: [String], in size: CGSize, embedded: Bool = false) -> some View {
        let raw = min(size.width / CGFloat(Sprite.columns), size.height / CGFloat(Sprite.rows))
        // Snap the cell to whole device pixels so edges stay crisp.
        let cell = max(1, (raw * displayScale).rounded(.down)) / displayScale
        let snap = { (value: CGFloat) in (value * displayScale).rounded() / displayScale }
        let spriteX = snap((size.width - cell * CGFloat(Sprite.columns)) / 2)
        let spriteY = snap((size.height - cell * CGFloat(Sprite.rows)) / 2)
        let origin = ClaudyOverload.spriteOrigin
        let offset = embedded ? (column: origin.column, row: origin.row) : (column: 0, row: 0)
        let tint = tint

        return Canvas { context, _ in
            var paths: [Character: Path] = [:]
            for (row, line) in frame.enumerated() {
                for (column, ink) in line.enumerated() where ink != "." {
                    paths[ink, default: Path()].addRect(CGRect(
                        x: CGFloat(column + offset.column) * cell,
                        y: CGFloat(row + offset.row) * cell,
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
        .frame(width: CGFloat(ClaudyOverload.columns) * cell, height: CGFloat(ClaudyOverload.rows) * cell)
        .offset(x: spriteX - CGFloat(origin.column) * cell, y: spriteY - CGFloat(origin.row) * cell)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Colours stacked on each ink, bottom first. Faces derived from the tint are the tint under
    /// an overlay, since Color.mix needs macOS 15. An unknown ink draws nothing.
    static func colors(for ink: Character, tint: Color) -> [Color] {
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
        case "1": return [Theme.Pixel.flash]
        case "2": return [Theme.Pixel.fireYellow]
        case "3": return [Theme.Pixel.fireOrange]
        case "4": return [Theme.Pixel.fireRed]
        case "y": return [Theme.Pixel.ember]
        case "5": return [Theme.Pixel.smokeDark]
        case "6": return [Theme.Pixel.smoke]
        case "7": return [Theme.Pixel.smokeLight]
        case "8": return [Theme.Pixel.smokePale]
        case "x": return [Theme.Pixel.charred]
        case "c": return [Theme.Pixel.ash]
        case "t": return [Theme.Pixel.ashTop]
        case "d": return [Theme.Pixel.ashSide]
        case "s": return [Theme.Pixel.groundShadow]
        default:  return []
        }
    }

    /// The sprite's rows for a pose, for tests and for the overload grid's alignment.
    static func frame(_ pose: Pose) -> [String] { Sprite.frame(pose) }

    /// One sprite frame as a bitmap, for places SwiftUI does not reach such as the menu bar.
    /// `cell` is the side of one sprite pixel in points; half a point lands on whole pixels on
    /// Retina screens.
    static func image(_ pose: Pose, tint: Color, cell: CGFloat) -> NSImage {
        bitmap(Sprite.frame(pose), tint: tint, cell: cell)
    }

    /// One overload frame as a bitmap. Larger than the sprite, which sits at `spriteOrigin`.
    static func overloadImage(_ index: Int, tint: Color, cell: CGFloat) -> NSImage {
        bitmap(ClaudyOverload.frames[index], tint: tint, cell: cell)
    }

    /// One wave frame as a bitmap, padded on both sides to the sprite's width so the
    /// percentage next to the menu bar icon does not move when Claude starts waving.
    static func waveImage(_ index: Int, tint: Color, cell: CGFloat) -> NSImage {
        let padding = max(0, Sprite.columns - ClaudyWave.columns)
        let left = String(repeating: ".", count: padding / 2)
        let right = String(repeating: ".", count: padding - padding / 2)
        return bitmap(ClaudyWave.frames[index].map { left + $0 + right }, tint: tint, cell: cell)
    }

    private static func bitmap(_ frame: [String], tint: Color, cell: CGFloat) -> NSImage {
        let columns = frame.first?.count ?? 0
        let size = NSSize(width: CGFloat(columns) * cell, height: CGFloat(frame.count) * cell)
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
