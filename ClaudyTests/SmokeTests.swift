import XCTest
@testable import Claudy

final class SmokeTests: XCTestCase {
    func testTestTargetRuns() {
        XCTAssertEqual(Theme.Metric.fullWidth, 340)
    }
}
