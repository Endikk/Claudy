import XCTest
@testable import Claudy

/// What the open island says: the lead quota in large, the others in small, and one line on
/// when the lead one resets. Never a countdown to a reset already past, never a figure that was
/// not measured.
@MainActor
final class NotchActivityTests: XCTestCase {

    private let now = Date()

    private func window(
        _ title: String,
        percent: Double = 0.28,
        resetIn: TimeInterval = 4 * 3600 + 5 * 60 + 30,
        isMeasured: Bool = true,
        amount: SpendReading? = nil
    ) -> UsageWindow {
        UsageWindow(title: title, window: "5h", percent: percent, tokensUsed: 0,
                    windowStart: now.addingTimeInterval(-3600), resetDate: now.addingTimeInterval(resetIn),
                    accent: .coral, isMeasured: isMeasured, amount: amount)
    }

    private func snapshot(session: UsageWindow, spend: UsageWindow? = nil) -> UsageSnapshot {
        var snapshot = UsageSnapshot.placeholder
        snapshot.session = session
        snapshot.weekly = window("Weekly", percent: 0.12)
        snapshot.sonnet = window("Fable", percent: 0)
        snapshot.spend = spend
        return snapshot
    }

    func testARunningSessionSaysWhenItResets() {
        let session = window("Session")

        let activity = NotchActivity(snapshot: snapshot(session: session), now: now)

        let expected = "reset \(UsageViewModel.resetTime(session.resetDate, now: now)) · in 4 h 5 min"
        XCTAssertEqual(activity.resetLine, expected)
    }

    func testAMeasuredSessionWithNoWindowRunningSaysInactive() {
        let activity = NotchActivity(snapshot: snapshot(session: window("Session", resetIn: -60)), now: now)

        XCTAssertEqual(activity.resetLine, "inactive")
    }

    func testAnUnmeasuredSessionSaysUnavailable() {
        let activity = NotchActivity(snapshot: snapshot(session: window("Session", isMeasured: false)), now: now)

        XCTAssertEqual(activity.resetLine, "unavailable")
    }

    func testAPlanInWindowsListsWeeklyThenPerModel() {
        let activity = NotchActivity(snapshot: snapshot(session: window("Session")), now: now)

        XCTAssertEqual(activity.lead.title, "Session")
        XCTAssertEqual(activity.others.map(\.title), ["Weekly", "Fable"])
        XCTAssertNil(activity.spentLine)
    }

    /// A plan billed on usage has no weekly or per-model quota: the spend leads, alone, with
    /// the money behind it.
    func testASpendCapLeadsAloneWithItsAmounts() {
        let reading = SpendReading(used: 46.31, limit: 500, currency: "USD", isLimitReached: false,
                                   resetsAt: now.addingTimeInterval(86_400 * 3))
        let spend = window("Monthly spend", percent: reading.percent, resetIn: 86_400 * 3, amount: reading)

        let activity = NotchActivity(snapshot: snapshot(session: window("Session"), spend: spend), now: now)

        XCTAssertEqual(activity.lead.title, "Monthly spend")
        XCTAssertTrue(activity.others.isEmpty)
        XCTAssertEqual(activity.spentLine, UsageViewModel.spent(reading))
    }
}
