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

    // MARK: - Simulation (`ClaudySimulateNotch`)

    func testWithoutSimulationTheScreensAreLeftAlone() {
        XCTAssertEqual(NotchGeometry.simulating(nil, on: [builtIn, external]), [builtIn, external])
    }

    /// A MacBook Air M1, an iMac, a Mac mini: no notch anywhere, so no island.
    func testSimulatingNoneRemovesEveryNotch() {
        let screens = NotchGeometry.simulating("none", on: [builtIn, external])

        XCTAssertNil(NotchGeometry.find(in: screens))
        XCTAssertEqual(screens.map(\.frame), [builtIn.frame, external.frame])
    }

    /// Another notch on the first screen, centred: for checking other shapes on this Mac.
    func testSimulatingASizePutsThatNotchAtTheTopCentreOfTheFirstScreen() throws {
        let screens = NotchGeometry.simulating("230x44", on: [external, builtIn])

        let geometry = try XCTUnwrap(NotchGeometry.find(in: screens))
        XCTAssertEqual(geometry.notch, CGRect(x: 1165, y: 1396, width: 230, height: 44))
    }

    func testAnUnreadableSimulationIsIgnored() {
        for value in ["", "wide", "0x32", "200x0", "200", "-5x32", "3000x32"] {
            XCTAssertEqual(NotchGeometry.simulating(value, on: [builtIn]), [builtIn], value)
        }
    }
}
