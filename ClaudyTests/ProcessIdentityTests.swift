import XCTest
@testable import Claudy

/// The kernel's word on a pid, checked on this very process: the one process every test host is
/// sure to have.
final class ProcessIdentityTests: XCTestCase {

    private let me = ProcessInfo.processInfo.processIdentifier

    /// Claude Code writes `procStart` as `ctime` does, in UTC, with a padded day.
    func testProcStartIsReadAsUTC() throws {
        let date = try XCTUnwrap(ProcessIdentity.date(fromProcStart: "Mon Nov  9 22:26:03 2026"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second],
                       [2026, 11, 9, 22, 26, 3])
        XCTAssertNil(ProcessIdentity.date(fromProcStart: "yesterday"))
    }

    func testKnowsWhenThisProcessStarted() throws {
        let start = try XCTUnwrap(ProcessIdentity.startDate(of: me))
        XCTAssertLessThan(start, Date())
        XCTAssertGreaterThan(start, Date().addingTimeInterval(-24 * 3600))
        XCTAssertNil(ProcessIdentity.startDate(of: 0))
    }

    /// The process is the session when it started when the file says; an hour off, it is another
    /// process that took the pid. Pid 0 and 1 never are.
    func testSessionMatchesOnStartTime() throws {
        let start = try XCTUnwrap(ProcessIdentity.startDate(of: me))
        XCTAssertTrue(ProcessIdentity.isSession(pid: me, startedAt: start))
        XCTAssertTrue(ProcessIdentity.isSession(pid: me, startedAt: start.addingTimeInterval(1)))
        XCTAssertFalse(ProcessIdentity.isSession(pid: me, startedAt: start.addingTimeInterval(-3 * 3600)))
        XCTAssertFalse(ProcessIdentity.isSession(pid: 0, startedAt: start))
        XCTAssertFalse(ProcessIdentity.isSession(pid: 1, startedAt: nil))
        XCTAssertFalse(ProcessIdentity.isSession(pid: -1, startedAt: nil))
    }

    /// Without a recorded start, only a Claude Code binary passes: the test host is not one.
    func testWithoutAStartTimeOnlyAClaudeBinaryPasses() {
        XCTAssertFalse(ProcessIdentity.isSession(pid: me, startedAt: nil))
    }

    func testSendRefusesPidZeroAndOneAndNamesAGoneProcess() {
        XCTAssertEqual(ProcessIdentity.send(SIGINT, to: 0), EINVAL)
        XCTAssertEqual(ProcessIdentity.send(SIGINT, to: 1), EINVAL)
        // Signal 0 sends nothing and still reports whether the process exists.
        XCTAssertEqual(ProcessIdentity.send(0, to: me), 0)
        XCTAssertEqual(ProcessIdentity.send(0, to: 2_147_000_000), ESRCH)
    }
}
