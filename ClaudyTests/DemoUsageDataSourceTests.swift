import XCTest
@testable import Claudy

/// The demo must read like a session already under way: its gauge on the pace marker, not far
/// ahead of a window that opened the moment the app launched.
final class DemoUsageDataSourceTests: XCTestCase {

    @MainActor
    func testFirstReadingIsOnPace() async throws {
        let session = try await DemoUsageDataSource().fetch().session

        XCTAssertTrue(session.isActive)
        XCTAssertLessThan(abs(session.percent - session.elapsed), 0.04,
                          "\(session.percent) used for \(session.elapsed) of the window elapsed")
        XCTAssertEqual(UsageViewModel.pace(session)?.text, "on pace")
    }
}
