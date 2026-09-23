import SwiftUI
import XCTest
@testable import Claudy

/// The card's shadow lives in the window's transparent margin, and whatever reaches the window
/// edge is cut straight: on a light wallpaper that shows as a grey box around the card.
@MainActor
final class CardShadowTests: XCTestCase {

    /// Retina, and the 1x external displays still plugged into many Macs.
    private static let scales: [CGFloat] = [1, 2]

    /// The full card and the minimal one: both corners, both sizes.
    private static let cards: [(size: CGSize, corner: CGFloat)] = [
        (CGSize(width: Theme.Metric.fullWidth, height: 520), Theme.Metric.cardCorner),
        (CGSize(width: Theme.Metric.minimalWidth, height: 53), Theme.Metric.minimalCorner),
    ]

    private static let cases = scales.flatMap { scale in cards.map { (scale: scale, size: $0.size, corner: $0.corner) } }

    func testShadowFadesOutBeforeTheWindowEdge() throws {
        for card in Self.cases {
            let alpha = try render(card.size, corner: card.corner, scale: card.scale)
            XCTAssertLessThanOrEqual(alpha.maxOnBorder, 1, "shadow cut by the window edge, card \(card.size) @\(card.scale)x")
        }
    }

    func testShadowShowsBelowTheCard() throws {
        let inset = Theme.Metric.shadowInset
        for card in Self.cases {
            let alpha = try render(card.size, corner: card.corner, scale: card.scale)
            let justBelow = alpha.at(x: inset + card.size.width / 2, y: inset + card.size.height + 2, scale: card.scale)
            XCTAssertGreaterThan(justBelow, 20, "no shadow under card \(card.size) @\(card.scale)x")
        }
    }

    /// The glass is translucent: anything painted under it would show through.
    func testNothingIsPaintedUnderTheCard() throws {
        let inset = Theme.Metric.shadowInset
        for card in Self.cases {
            let alpha = try render(card.size, corner: card.corner, scale: card.scale)
            let centre = alpha.at(x: inset + card.size.width / 2, y: inset + card.size.height / 2, scale: card.scale)
            XCTAssertEqual(centre, 0, "shadow painted under card \(card.size) @\(card.scale)x")
        }
    }

    // MARK: - Rendering

    /// Renders the shadow the way `RootView` lays it out: the card's frame, then the margin.
    private func render(_ size: CGSize, corner: CGFloat, scale: CGFloat) throws -> AlphaMap {
        let view = CardShadow(corner: corner)
            .frame(width: size.width, height: size.height)
            .padding(Theme.Metric.shadowInset)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        return try XCTUnwrap(AlphaMap(image))
    }
}

/// The alpha channel of an image, rows from the top.
private struct AlphaMap {
    let width: Int
    let height: Int
    let values: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        values = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// Alpha at a point given in points from the top left.
    func at(x: CGFloat, y: CGFloat, scale: CGFloat) -> UInt8 {
        values[Int(y * scale) * width + Int(x * scale)]
    }

    /// The strongest alpha on the outermost ring of pixels: the window edge.
    var maxOnBorder: UInt8 {
        let rows = [0, height - 1].flatMap { row in (0..<width).map { values[row * width + $0] } }
        let columns = [0, width - 1].flatMap { column in (0..<height).map { values[$0 * width + column] } }
        return (rows + columns).max() ?? 0
    }
}
