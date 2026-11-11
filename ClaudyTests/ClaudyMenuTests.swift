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

    private func menu(showing placement: Placement, hasNotch: Bool, notifier: Notifier? = nil,
                      hotKey: Bool = true) -> NSMenu {
        ClaudyMenu(viewModel: UsageViewModel(source: NoReading()),
                   notifier: notifier ?? Notifier(poster: RecordingPoster(), store: Self.store()),
                   isHotKeyActive: { hotKey })
            .make(showing: placement, hasNotch: hasNotch)
    }

    /// Preferences of their own, so no test reads or changes the user's switches.
    private static func store() -> UserDefaults {
        let name = "claudy-tests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    func testNotificationsSubmenuHasOneSwitchPerKind() throws {
        let notifier = Notifier(poster: RecordingPoster(), store: Self.store())
        let item = try XCTUnwrap(menu(showing: .menuBar, hasNotch: false, notifier: notifier)
            .items.first { $0.title == "Notifications" })
        let switches = try XCTUnwrap(item.submenu).items.filter { $0.representedObject is String }

        XCTAssertEqual(switches.map(\.title), NotificationKind.allCases.map(\.menuTitle))
        // An agent finishing is asked for; everything else is on from the start.
        XCTAssertEqual(switches.filter { $0.state == .off }.map(\.title), ["An agent is done"])
    }

    func testShortcutIsShownOrSaidTaken() throws {
        let shown = try XCTUnwrap(menu(showing: .widget, hasNotch: false).items.first { $0.title == "Show or hide Claudy" })
        XCTAssertEqual(shown.keyEquivalent, "c")
        XCTAssertEqual(shown.keyEquivalentModifierMask, [.control, .option])

        let titles = menu(showing: .widget, hasNotch: false, hotKey: false).items.map(\.title)
        XCTAssertTrue(titles.contains("Show or hide Claudy (⌃⌥C is taken)"))
    }

    func testOffersTheExport() {
        XCTAssertTrue(menu(showing: .menuBar, hasNotch: false).items.map(\.title).contains("Export usage as CSV…"))
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
