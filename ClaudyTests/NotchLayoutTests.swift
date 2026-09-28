import XCTest
@testable import Claudy

/// The island's window hangs from the top of the notched screen, centred on the notch, and never
/// leaves the screen. It grows at once and shrinks late, so the animated shape is never cut.
final class NotchLayoutTests: XCTestCase {

    private func geometry(
        frame: CGRect = CGRect(x: 0, y: 0, width: 1728, height: 1117),
        left: CGFloat = 771.5,
        right: CGFloat = 771.5
    ) throws -> NotchGeometry {
        try XCTUnwrap(NotchGeometry(ScreenMetrics(
            frame: frame, safeAreaTop: 32, leftAreaWidth: left, rightAreaWidth: right
        )))
    }

    func testAtRestTheEarsFlankTheNotch() throws {
        let layout = NotchLayout(geometry: try geometry())

        XCTAssertEqual(layout.restingSize, CGSize(width: 185 + 2 * 48, height: 32))
        XCTAssertEqual(layout.restingFrame, CGRect(x: 723.5, y: 1085, width: 281, height: 32))
    }

    func testOpenTheShapeHangsFromTheTopCentredOnTheNotch() throws {
        let layout = NotchLayout(geometry: try geometry())

        let frame = layout.frame(for: CGSize(width: 290, height: 400))

        // The notch's centre is x = 864.
        XCTAssertEqual(frame, CGRect(x: 719, y: 717, width: 290, height: 400))
    }

    func testTheFrameNeverLeavesTheScreen() throws {
        let small = CGRect(x: 0, y: 0, width: 400, height: 300)
        let nearLeft = NotchLayout(geometry: try geometry(frame: small, left: 10, right: 200))
        let nearRight = NotchLayout(geometry: try geometry(frame: small, left: 200, right: 10))
        let tall = CGSize(width: 290, height: 400)

        XCTAssertEqual(nearLeft.frame(for: tall), CGRect(x: 0, y: 0, width: 290, height: 300))
        XCTAssertEqual(nearRight.frame(for: tall), CGRect(x: 110, y: 0, width: 290, height: 300))
    }

    func testOnASecondScreenTheFramesUseGlobalCoordinates() throws {
        let screen = CGRect(x: -1728, y: 200, width: 1728, height: 1117)
        let layout = NotchLayout(geometry: try geometry(frame: screen))

        XCTAssertEqual(layout.restingFrame, CGRect(x: -1004.5, y: 1285, width: 281, height: 32))
    }

    func testGrowingTakesTheLargerFrameAtOnce() throws {
        let layout = NotchLayout(geometry: try geometry())
        let open = layout.frame(for: CGSize(width: 290, height: 400))

        let step = NotchLayout.step(from: layout.restingFrame, to: open)

        XCTAssertEqual(step.now, open)
        XCTAssertEqual(step.settle, open)
    }

    func testShrinkingWaitsForTheShapeToClose() throws {
        let layout = NotchLayout(geometry: try geometry())
        let open = layout.frame(for: CGSize(width: 290, height: 400))

        let step = NotchLayout.step(from: open, to: layout.restingFrame)

        XCTAssertEqual(step.now, open)
        XCTAssertEqual(step.settle, layout.restingFrame)
    }

    func testAWindowWithoutFrameYetTakesTheTargetAsIs() throws {
        let layout = NotchLayout(geometry: try geometry())

        let step = NotchLayout.step(from: .zero, to: layout.restingFrame)

        XCTAssertEqual(step.now, layout.restingFrame)
        XCTAssertEqual(step.settle, layout.restingFrame)
    }
}
