import XCTest
@testable import Claudy

/// `api.log` is what separates a rate limit from a dead token on the user's Mac. A test run, or
/// the test host reading quotas meanwhile, must never write fake incidents into it.
final class DiagnosticLogTests: XCTestCase {

    func testTestRunsWriteOutsideTheUsersLog() throws {
        let usersLog = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory,
                                                              in: .userDomainMask).first)
            .appendingPathComponent("Claudy/api.log")

        let file = try XCTUnwrap(DiagnosticLog.file)

        XCTAssertNotEqual(file.standardizedFileURL.path, usersLog.standardizedFileURL.path)
        XCTAssertTrue(file.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    func testAppendWritesTheLine() throws {
        let marker = "diagnostic-log-test-\(UUID().uuidString)"

        DiagnosticLog.append(marker)

        let contents = try String(contentsOf: XCTUnwrap(DiagnosticLog.file), encoding: .utf8)
        XCTAssertTrue(contents.contains(marker))
    }
}
