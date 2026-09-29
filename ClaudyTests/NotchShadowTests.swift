import Metal
import SwiftUI
import XCTest
@testable import Claudy

/// The open island casts the card's shadow into a transparent margin on its sides and below it.
/// Its top is the screen's edge: nothing to fade there. Whatever reaches the other edges of the
/// window is cut straight, which shows as a grey box on a light wallpaper.
@MainActor
final class NotchShadowTests: XCTestCase {

    private static let scales: [CGFloat] = [1, 2]
    private static let open = CGSize(width: 290, height: 400)
    private static let radius: CGFloat = 20

    /// GitHub's Intel Macs are virtual machines whose graphics device Metal cannot load SwiftUI's
    /// shaders for: rendering there aborts the whole run instead of failing a test.
    override func setUpWithError() throws {
        #if arch(x86_64)
        let device = MTLCreateSystemDefaultDevice()?.name ?? ""
        if device.isEmpty || device.localizedCaseInsensitiveContains("paravirtual") {
            throw XCTSkip("SwiftUI cannot render on this virtual graphics device (\(device)).")
        }
        #endif
    }

    func testShadowFadesOutBeforeTheSideAndBottomEdges() throws {
        for scale in Self.scales {
            let alpha = try render(scale: scale)
            XCTAssertLessThanOrEqual(alpha.maxOnSidesAndBottom, 1, "shadow cut by the window edge @\(scale)x")
        }
    }

    func testShadowShowsBelowTheIsland() throws {
        let inset = Theme.Metric.shadowInset
        for scale in Self.scales {
            let alpha = try render(scale: scale)
            let justBelow = alpha.at(x: inset + Self.open.width / 2, y: Self.open.height + 2, scale: scale)
            XCTAssertGreaterThan(justBelow, 20, "no shadow under the island @\(scale)x")
        }
    }

    func testShadowShowsBesideTheIsland() throws {
        let inset = Theme.Metric.shadowInset
        for scale in Self.scales {
            let alpha = try render(scale: scale)
            let justLeft = alpha.at(x: inset - 2, y: Self.open.height / 2, scale: scale)
            XCTAssertGreaterThan(justLeft, 10, "no shadow beside the island @\(scale)x")
        }
    }

    // MARK: - Rendering

    /// Laid out as `NotchView` does when open: the shape, then the margin on three sides.
    private func render(scale: CGFloat) throws -> AlphaMap {
        let inset = Theme.Metric.shadowInset
        let view = OutlineShadow(outline: NotchShape(bottomRadius: Self.radius))
            .frame(width: Self.open.width, height: Self.open.height)
            .padding(EdgeInsets(top: 0, leading: inset, bottom: inset, trailing: inset))
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

    /// The strongest alpha on the left, right and bottom edges: the top one is the screen's.
    var maxOnSidesAndBottom: UInt8 {
        let bottom = (0..<width).map { values[(height - 1) * width + $0] }
        let sides = [0, width - 1].flatMap { column in (0..<height).map { values[$0 * width + column] } }
        return (bottom + sides).max() ?? 0
    }
}
