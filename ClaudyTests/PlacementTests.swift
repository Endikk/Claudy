import XCTest
@testable import Claudy

/// Where Claudy shows itself. The notch needs a notched screen; without one Claudy waits in the
/// menu bar and the choice is kept for when the screen comes back.
final class PlacementTests: XCTestCase {

    func testANewInstallStartsAsTheWidget() {
        XCTAssertEqual(Placement.stored(raw: nil, legacyInMenuBar: false), .widget)
    }

    func testAnUpdateKeepsClaudyInTheMenuBar() {
        XCTAssertEqual(Placement.stored(raw: nil, legacyInMenuBar: true), .menuBar)
    }

    func testTheSavedPlacementWinsOverTheLegacyFlag() {
        XCTAssertEqual(Placement.stored(raw: "notch", legacyInMenuBar: true), .notch)
        XCTAssertEqual(Placement.stored(raw: "widget", legacyInMenuBar: true), .widget)
    }

    func testAnUnknownValueFallsBackToTheLegacyFlag() {
        XCTAssertEqual(Placement.stored(raw: "dock", legacyInMenuBar: true), .menuBar)
        XCTAssertEqual(Placement.stored(raw: "dock", legacyInMenuBar: false), .widget)
    }

    func testTheNotchNeedsANotchedScreen() {
        XCTAssertEqual(Placement.notch.effective(hasNotch: true), .notch)
        XCTAssertEqual(Placement.notch.effective(hasNotch: false), .menuBar)
        XCTAssertEqual(Placement.widget.effective(hasNotch: false), .widget)
        XCTAssertEqual(Placement.menuBar.effective(hasNotch: true), .menuBar)
    }

    func testMenusOfferTheOtherPlacements() {
        XCTAssertEqual(Placement.widget.offered(hasNotch: true), [.menuBar, .notch])
        XCTAssertEqual(Placement.menuBar.offered(hasNotch: true), [.widget, .notch])
        XCTAssertEqual(Placement.notch.offered(hasNotch: true), [.widget, .menuBar])
    }

    func testWithoutANotchNoMenuOffersIt() {
        XCTAssertEqual(Placement.widget.offered(hasNotch: false), [.menuBar])
        XCTAssertEqual(Placement.menuBar.offered(hasNotch: false), [.widget])
    }

    /// The lid is closed on an external display: the menu bar item stands in for the island, so
    /// offering "Show in menu bar" would do nothing.
    func testANotchChoiceShownInTheMenuBarOffersOnlyTheWidget() {
        XCTAssertEqual(Placement.notch.offered(hasNotch: false), [.widget])
    }
}
