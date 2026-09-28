import AppKit
import XCTest
@testable import Claudy

private struct NoReading: UsageDataSource {
    func fetch() async throws -> UsageSnapshot { .placeholder }
}

/// The right-click menu of the menu bar item and of the island. Built with explicit placements:
/// the test host shares the user's preferences, so no test changes the saved one.
@MainActor
final class ClaudyMenuTests: XCTestCase {

    private func menu(showing placement: Placement, hasNotch: Bool) -> NSMenu {
        ClaudyMenu(viewModel: UsageViewModel(source: NoReading()))
            .make(showing: placement, hasNotch: hasNotch)
    }

    func testTheIslandOffersTheTwoOtherPlacements() {
        let titles = menu(showing: .notch, hasNotch: true).items.map(\.title)

        XCTAssertTrue(titles.contains("Show floating widget"))
        XCTAssertTrue(titles.contains("Show in menu bar"))
        XCTAssertFalse(titles.contains("Show in notch"))
    }

    func testTheMenuBarItemOffersTheNotchOnlyWithOne() {
        XCTAssertTrue(menu(showing: .menuBar, hasNotch: true).items.map(\.title).contains("Show in notch"))
        XCTAssertFalse(menu(showing: .menuBar, hasNotch: false).items.map(\.title).contains("Show in notch"))
    }

    func testEachPlacementEntryCarriesItsPlacement() {
        let placements = menu(showing: .widget, hasNotch: true).items
            .compactMap { $0.representedObject as? Placement }

        XCTAssertEqual(placements, [.menuBar, .notch])
    }

    func testRefreshComesFirstAndQuitLast() {
        let items = menu(showing: .menuBar, hasNotch: false).items

        XCTAssertEqual(items.first?.title, "Refresh")
        XCTAssertEqual(items.last?.title, "Quit Claudy")
    }
}
