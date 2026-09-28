import XCTest
@testable import Claudy

/// The notch is what macOS leaves between the two usable parts of the menu bar. Plain values in,
/// so none of this needs a notched Mac.
final class NotchGeometryTests: XCTestCase {

    /// Measured on a 16-inch MacBook Pro (Mac16,7) at its default size, on 2026-09-29.
    private let builtIn = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 32,
        leftAreaWidth: 771.5,
        rightAreaWidth: 771.5
    )

    private let external = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        safeAreaTop: 0,
        leftAreaWidth: nil,
        rightAreaWidth: nil
    )

    func testTheNotchSitsBetweenTheTwoUsableAreas() throws {
        let geometry = try XCTUnwrap(NotchGeometry(builtIn))

        XCTAssertEqual(geometry.notch, CGRect(x: 771.5, y: 1085, width: 185, height: 32))
        XCTAssertEqual(geometry.screenFrame, builtIn.frame)
    }

    func testAScreenWithoutTopInsetHasNoNotch() {
        XCTAssertNil(NotchGeometry(external))
    }

    func testAnInsetWithoutUsableAreasIsNotANotch() {
        var odd = builtIn
        odd.leftAreaWidth = nil
        odd.rightAreaWidth = nil

        XCTAssertNil(NotchGeometry(odd))
    }

    func testAreasCoveringTheWholeWidthLeaveNoNotch() {
        var full = builtIn
        full.leftAreaWidth = 864
        full.rightAreaWidth = 864

        XCTAssertNil(NotchGeometry(full))
    }

    func testTheBuiltInScreenIsFoundBehindAnExternalMainScreen() {
        var leftOfMain = builtIn
        leftOfMain.frame = CGRect(x: -1728, y: 0, width: 1728, height: 1117)

        let geometry = NotchGeometry.find(in: [external, leftOfMain])

        XCTAssertEqual(geometry?.notch, CGRect(x: -956.5, y: 1085, width: 185, height: 32))
        XCTAssertEqual(geometry?.screenFrame, leftOfMain.frame)
    }

    func testWithoutANotchedScreenNothingIsFound() {
        XCTAssertNil(NotchGeometry.find(in: [external]))
        XCTAssertNil(NotchGeometry.find(in: []))
    }
}
