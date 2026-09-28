import XCTest
@testable import Claudy

/// Every notched Mac, not only the one Claudy is developed on: notches of other widths and
/// heights, the scaled resolutions macOS offers ("Larger text" to "More space"), and a built-in
/// screen placed anywhere around an external one. The sizes are a sweep, not measurements: what
/// is checked holds for any of them.
final class NotchShapesTests: XCTestCase {

    private static let screenWidths: [CGFloat] = [1147, 1280, 1352, 1470, 1496, 1512, 1710, 1728, 1800, 2056]
    private static let notchWidths: [CGFloat] = [150, 185, 200, 230]
    private static let notchHeights: [CGFloat] = [24, 32, 37, 44]

    /// The open island: its view plus the shadow's margin, and a tall content.
    private static let openSize = CGSize(width: 440 + 2 * 28, height: 220)

    /// Origins of the built-in screen: main, left of an external screen, right of it and higher,
    /// below it.
    private static func origins(for size: CGSize) -> [CGPoint] {
        [.zero, CGPoint(x: -size.width, y: 0), CGPoint(x: 2560, y: 300), CGPoint(x: 0, y: -size.height)]
    }

    private struct Case: CustomStringConvertible {
        let frame: CGRect
        let notch: CGSize
        /// The notch a point off centre, as a rounded scaled resolution can leave it.
        let skew: CGFloat
        var description: String { "screen \(frame), notch \(notch), skew \(skew)" }
    }

    private static var cases: [Case] {
        screenWidths.flatMap { width -> [Case] in
            let size = CGSize(width: width, height: (width * 0.6464).rounded())
            return origins(for: size).flatMap { origin in
                notchWidths.flatMap { notchWidth in
                    notchHeights.flatMap { notchHeight in
                        [0, 1.5].map { skew in
                            Case(frame: CGRect(origin: origin, size: size),
                                 notch: CGSize(width: notchWidth, height: notchHeight), skew: skew)
                        }
                    }
                }
            }
        }
    }

    private func geometry(_ item: Case) throws -> NotchGeometry {
        let side = (item.frame.width - item.notch.width) / 2
        return try XCTUnwrap(NotchGeometry(ScreenMetrics(
            frame: item.frame, safeAreaTop: item.notch.height,
            leftAreaWidth: side + item.skew, rightAreaWidth: side - item.skew
        )), "\(item)")
    }

    func testTheNotchIsFoundWhereverTheScreenIs() throws {
        for item in Self.cases {
            let notch = try geometry(item).notch
            XCTAssertEqual(notch.size, item.notch, "\(item)")
            XCTAssertEqual(notch.maxY, item.frame.maxY, "\(item)")
            XCTAssertEqual(notch.midX, item.frame.midX + item.skew, accuracy: 0.001, "\(item)")
        }
    }

    func testAtRestTheEarsHugTheNotchAndStayOnScreen() throws {
        for item in Self.cases {
            let geometry = try geometry(item)
            let resting = NotchLayout(geometry: geometry).restingFrame
            XCTAssertEqual(resting.maxY, item.frame.maxY, "hangs from the top, \(item)")
            XCTAssertEqual(resting.height, item.notch.height, "the notch's height, \(item)")
            XCTAssertEqual(resting.midX, geometry.notch.midX, accuracy: 0.001, "centred, \(item)")
            XCTAssertEqual(resting.width, item.notch.width + 2 * NotchLayout.earWidth, "\(item)")
            XCTAssertTrue(item.frame.contains(resting), "on screen, \(item)")
        }
    }

    func testOpenTheIslandStaysOnScreenAndGrowsFromTheEars() throws {
        for item in Self.cases {
            let layout = NotchLayout(geometry: try geometry(item))
            let open = layout.frame(for: Self.openSize)
            XCTAssertEqual(open.maxY, item.frame.maxY, "hangs from the top, \(item)")
            XCTAssertTrue(item.frame.contains(open), "on screen, \(item)")
            XCTAssertEqual(NotchLayout.step(from: layout.restingFrame, to: open).now, open,
                           "grows at once around the ears, \(item)")
            XCTAssertGreaterThanOrEqual(layout.openWidth(content: 440, margin: 28), layout.restingFrame.width, "\(item)")
        }
    }

    func testAScreenWithoutNotchNeverGetsAnIsland() {
        for width in Self.screenWidths {
            let frame = CGRect(x: 0, y: 0, width: width, height: (width * 0.6464).rounded())
            let flat = ScreenMetrics(frame: frame, safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil)
            XCTAssertNil(NotchGeometry(flat), "\(frame)")
            XCTAssertNil(NotchGeometry.find(in: [flat, flat]), "\(frame)")
        }
    }
}
