import XCTest
@testable import Claudy

private struct EmptySource: UsageDataSource {
    func fetch() async throws -> UsageSnapshot { .placeholder }
}

/// The refresh button also looks for a new Claudy. The timer and the wake-up refresh do not:
/// the update checker keeps its own daily schedule.
@MainActor
final class ManualRefreshTests: XCTestCase {

    func testManualRefreshAlsoChecksForUpdates() async {
        let viewModel = UsageViewModel(source: EmptySource())
        var checks = 0
        viewModel.onUserRefresh = { checks += 1 }

        await viewModel.refresh(userInitiated: true)

        XCTAssertEqual(checks, 1)
    }

    func testAutomaticRefreshLeavesUpdatesAlone() async {
        let viewModel = UsageViewModel(source: EmptySource())
        var checks = 0
        viewModel.onUserRefresh = { checks += 1 }

        await viewModel.refresh()

        XCTAssertEqual(checks, 0)
    }

    /// Holding ⌘R repeats the key: each repeat must not lift a backoff the server asked for.
    func testRefreshLiftsTheBackoffOncePerMinute() async {
        let suite = "claudy.tests.manualrefresh"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let client = ClaudeAccountClient(store: store, borrowedToken: { nil }, ownToken: .empty)
        let start = Date(timeIntervalSince1970: 0)

        let first = await client.resetBackoff(now: start)
        let repeated = await client.resetBackoff(now: start + ClaudeAccountClient.manualRetrySpacing - 1)
        let aMinuteLater = await client.resetBackoff(now: start + ClaudeAccountClient.manualRetrySpacing)

        XCTAssertTrue(first)
        XCTAssertFalse(repeated)
        XCTAssertTrue(aMinuteLater)
    }
}
