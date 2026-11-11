import XCTest
@testable import Claudy

/// Records what a notifier posts, and answers the permission question as told.
@MainActor
final class RecordingPoster: NotificationPosting {
    var allows = true
    var denied = false
    private(set) var posted: [Alert] = []
    private(set) var withdrawn: [String] = []

    func authorize() async -> Bool { allows }
    func isDenied() async -> Bool { denied }
    func post(_ alert: Alert) { posted.append(alert) }
    func withdraw(_ ids: [String]) { withdrawn += ids }
}

@MainActor
final class AlertRulesTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_793_400_000)

    /// A 5-hour window opened at `start`, read `minutes` later at `percent`.
    private func window(_ percent: Double, reset: Date? = nil, measured: Bool = true) -> UsageWindow {
        UsageWindow(title: "Session", window: "5h", percent: percent, tokensUsed: 0, windowStart: start,
                    resetDate: reset ?? start.addingTimeInterval(5 * 3600), accent: .coral, isMeasured: measured)
    }

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    // MARK: - Quota

    /// The first reading only sets the scene: a threshold crossed before Claudy looked is old news.
    func testFirstReadingSendsNothing() {
        var rules = QuotaAlerts()
        XCTAssertTrue(rules.evaluate(window(0.85), now: at(240)).isEmpty)
    }

    /// Crossing 80 % sends one alert per window, never again in it.
    func testCrossingEightyPercentAlertsOncePerWindow() {
        var rules = QuotaAlerts()
        _ = rules.evaluate(window(0.70), now: at(270))
        let alerts = rules.evaluate(window(0.82), now: at(280))
        XCTAssertEqual(alerts.map(\.kind), [.sessionHigh])
        XCTAssertEqual(alerts.first?.title, "Session at 82%")
        XCTAssertTrue(alerts.first?.body.hasSuffix("At this pace you stay under the limit.") ?? false)

        _ = rules.evaluate(window(0.79), now: at(285))
        XCTAssertTrue(rules.evaluate(window(0.83), now: at(290)).isEmpty)
    }

    /// Crossed early, at a pace that fills the window before it resets: the alert says so.
    func testEightyPercentSaysWhenThePaceFillsTheWindow() {
        var rules = QuotaAlerts()
        _ = rules.evaluate(window(0.70), now: at(230))
        let high = rules.evaluate(window(0.82), now: at(240)).first { $0.kind == .sessionHigh }
        XCTAssertTrue(high?.body.hasSuffix("At this pace it fills before then.") ?? false)
    }

    /// At this pace the quota fills well before the reset: said once, with when.
    func testLimitBeforeTheResetIsProjected() throws {
        var rules = QuotaAlerts()
        _ = rules.evaluate(window(0.40), now: at(50))
        let alerts = rules.evaluate(window(0.60), now: at(60))
        let alert = try XCTUnwrap(alerts.first { $0.kind == .limitBeforeReset })
        // 60 % in an hour fills at 1 h 40, 3 h 20 before the reset.
        let fullAt = UsageViewModel.clock(at(100))
        XCTAssertEqual(alert.body, "At this pace the session is full around \(fullAt), "
                       + "3 h 20 before it resets at \(UsageViewModel.clock(at(300))).")
        XCTAssertTrue(rules.evaluate(window(0.65), now: at(65)).allSatisfy { $0.kind != .limitBeforeReset })
    }

    /// A projection on a little use, or one that lands near the reset, says nothing.
    func testNoProjectionOnLittleUseOrNearTheReset() {
        var early = QuotaAlerts()
        _ = early.evaluate(window(0.20), now: at(10))
        XCTAssertTrue(early.evaluate(window(0.30), now: at(15)).isEmpty)

        var close = QuotaAlerts()
        _ = close.evaluate(window(0.55), now: at(160))
        // 0.6 in 175 min fills at about 292 min: within ten minutes of the reset at 300.
        XCTAssertTrue(close.evaluate(window(0.6), now: at(175)).isEmpty)
    }

    /// The full window reset: the session is back, and how long it was stopped when it was seen
    /// filling.
    func testSessionBackAfterAFullWindow() throws {
        var rules = QuotaAlerts()
        _ = rules.evaluate(window(0.95), now: at(250))
        _ = rules.evaluate(window(1.0), now: at(255))
        XCTAssertTrue(rules.evaluate(window(1.0), now: at(280)).isEmpty)

        let next = window(0.0, reset: at(300))
        let alert = try XCTUnwrap(rules.evaluate(next, now: at(302)).first)
        XCTAssertEqual(alert.kind, .sessionBack)
        XCTAssertEqual(alert.body, "The 5-hour quota reset at \(UsageViewModel.clock(at(300))). "
                       + "You were stopped for 45 min.")
        XCTAssertTrue(rules.evaluate(next, now: at(305)).isEmpty)
    }

    /// Found full at launch: the reset is still news, how long it lasted is not known.
    func testSessionBackWithoutAWitnessedStart() throws {
        var rules = QuotaAlerts()
        _ = rules.evaluate(window(1.0), now: at(280))
        let alert = try XCTUnwrap(rules.evaluate(window(0.0, reset: at(300)), now: at(301)).first)
        XCTAssertEqual(alert.body, "The 5-hour quota reset at \(UsageViewModel.clock(at(300))).")
    }

    func testUnmeasuredReadingSendsNothing() {
        var rules = QuotaAlerts()
        _ = rules.evaluate(window(0.7), now: at(230))
        XCTAssertTrue(rules.evaluate(window(0.9, measured: false), now: at(240)).isEmpty)
    }

    // MARK: - Sessions and agents

    private func session(_ id: String = "s1", status: ClaudeSession.Status, since: Date,
                         background: Bool = false) -> ClaudeSession {
        ClaudeSession(id: id, pid: 4242, processStartedAt: nil, name: "evan-b6", cwd: "/Users/me/EVAN",
                      openedAt: nil, status: status, statusSince: since, isBackground: background,
                      host: HostApp(name: "Visual Studio Code", bundleURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")),
                      lastPrompt: nil)
    }

    private func agent(_ id: String, started: Date, last: Date, finished: Bool = false,
                       edited: [String] = []) -> RunningAgent {
        RunningAgent(id: id, sessionID: "s1", sessionPID: 4242, sessionStartedAt: nil, sessionName: "claudy-a5",
                     title: "Run the test suite", startedAt: started, lastActivity: last, isFinished: finished,
                     actionCount: 3, recent: [], lastAction: nil, editedFiles: edited)
    }

    /// A session asking for a permission is announced once it has waited a moment, once, and its
    /// banner is taken back when it stops waiting.
    func testWaitingSessionIsAnnouncedThenWithdrawn() throws {
        var rules = ActivityAlerts()
        let since = at(0)
        let waiting = session(status: .waiting(reason: "permission prompt"), since: since)

        XCTAssertTrue(rules.evaluate(sessions: [waiting], agents: [], now: since.addingTimeInterval(5)).post.isEmpty)
        let posted = rules.evaluate(sessions: [waiting], agents: [], now: since.addingTimeInterval(25)).post
        let alert = try XCTUnwrap(posted.first)
        XCTAssertEqual(alert.kind, .sessionWaiting)
        XCTAssertEqual(alert.title, "evan-b6 is waiting for you")
        XCTAssertEqual(alert.body, "Permission prompt · EVAN · VS Code")
        XCTAssertEqual(alert.sessionID, "s1")
        XCTAssertTrue(rules.evaluate(sessions: [waiting], agents: [], now: since.addingTimeInterval(60)).post.isEmpty)

        let answered = rules.evaluate(sessions: [session(status: .busy, since: at(2))], agents: [], now: at(2))
        XCTAssertEqual(answered.withdraw, [alert.id])
    }

    /// A session already waiting at launch is old news; a new question replaces the old banner; a
    /// file that does not say since when still gets its banner once the wait is long enough.
    func testWaitingAtLaunchNewQuestionAndUnknownStart() throws {
        var rules = ActivityAlerts()
        let long = session(status: .waiting(reason: "permission prompt"), since: at(0))
        XCTAssertTrue(rules.evaluate(sessions: [long], agents: [], now: at(30)).post.isEmpty)
        XCTAssertTrue(rules.evaluate(sessions: [long], agents: [], now: at(31)).post.isEmpty)

        let first = try XCTUnwrap(rules.evaluate(sessions: [session(status: .waiting(reason: nil), since: at(40))],
                                                 agents: [], now: at(41)).post.first)
        let second = rules.evaluate(sessions: [session(status: .waiting(reason: nil), since: at(42))],
                                    agents: [], now: at(43))
        XCTAssertEqual(second.post.count, 1)
        XCTAssertEqual(second.withdraw, [first.id])

        var unknown = ActivityAlerts()
        let undated = ClaudeSession(id: "s9", pid: 1, processStartedAt: nil, name: "x", cwd: nil, openedAt: nil,
                                    status: .waiting(reason: nil), statusSince: nil, isBackground: false,
                                    host: nil, lastPrompt: nil)
        XCTAssertTrue(unknown.evaluate(sessions: [], agents: [], now: at(0)).post.isEmpty)
        XCTAssertTrue(unknown.evaluate(sessions: [undated], agents: [], now: at(1)).post.isEmpty)
        XCTAssertEqual(unknown.evaluate(sessions: [undated], agents: [], now: at(1.5)).post.map(\.kind), [.sessionWaiting])
    }

    /// Nobody sits at a program's session: it never says it waits.
    func testBackgroundSessionNeverAnnouncesWaiting() {
        var rules = ActivityAlerts()
        let waiting = session(status: .waiting(reason: nil), since: at(0), background: true)
        XCTAssertTrue(rules.evaluate(sessions: [waiting], agents: [], now: at(5)).post.isEmpty)
    }

    /// An agent silent past three minutes is announced once per silence.
    func testSilentAgentIsAnnouncedOnce() throws {
        var rules = ActivityAlerts()
        let quiet = agent("a", started: at(0), last: at(10))
        XCTAssertTrue(rules.evaluate(sessions: [], agents: [quiet], now: at(11)).post.isEmpty)
        let alert = try XCTUnwrap(rules.evaluate(sessions: [], agents: [quiet], now: at(14)).post.first)
        XCTAssertEqual(alert.kind, .agentSilent)
        XCTAssertEqual(alert.body, "\u{201C}Run the test suite\u{201D} has said nothing for 4 min. claudy-a5")
        XCTAssertTrue(rules.evaluate(sessions: [], agents: [quiet], now: at(20)).post.isEmpty)
    }

    /// Done is said of an agent seen at work, not of one found already finished.
    func testDoneIsSaidOfAnAgentSeenAtWork() throws {
        var rules = ActivityAlerts()
        _ = rules.evaluate(sessions: [], agents: [agent("a", started: at(0), last: at(9))], now: at(9.5))
        let done = agent("a", started: at(0), last: at(10), finished: true, edited: ["CHANGELOG.md"])
        let alert = try XCTUnwrap(rules.evaluate(sessions: [], agents: [done], now: at(10.5)).post.first)
        XCTAssertEqual(alert.kind, .agentDone)
        XCTAssertEqual(alert.body, "\u{201C}Run the test suite\u{201D} in 10 min. Wrote CHANGELOG.md")

        var fresh = ActivityAlerts()
        XCTAssertTrue(fresh.evaluate(sessions: [], agents: [done], now: at(10.5)).post.isEmpty)
    }

    /// The agents of a program's session go unannounced, like the session.
    func testAgentsOfABackgroundSessionAreNotAnnounced() {
        var rules = ActivityAlerts()
        let quiet = agent("a", started: at(0), last: at(10))
        let program = session(status: .busy, since: at(0), background: true)
        _ = rules.evaluate(sessions: [program], agents: [quiet], now: at(11))
        XCTAssertTrue(rules.evaluate(sessions: [program], agents: [quiet], now: at(14)).post.isEmpty)
    }

    // MARK: - Notifier

    private func store() -> UserDefaults {
        let name = "claudy-tests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    private func alert(_ kind: NotificationKind) -> Alert {
        Alert(kind: kind, id: kind.rawValue, title: "t", body: "b")
    }

    /// Only the kinds switched on go out; the switches are kept.
    func testNotifierPostsOnlyWhatIsSwitchedOn() async {
        let poster = RecordingPoster()
        let defaults = store()
        let notifier = Notifier(poster: poster, store: defaults)
        XCTAssertFalse(notifier.isEnabled(.agentDone))
        notifier.toggle(.sessionHigh)

        notifier.deliver([alert(.sessionHigh), alert(.agentDone), alert(.sessionWaiting)])
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(poster.posted.map(\.kind), [.sessionWaiting])
        XCTAssertFalse(Notifier(poster: RecordingPoster(), store: defaults).isEnabled(.sessionHigh))
    }

    /// Refused by the user: nothing is posted, and the menu learns it. A request that failed
    /// without a refusal posts nothing either, but is not taken for one.
    func testRefusedPermissionPostsNothing() async {
        let poster = RecordingPoster()
        poster.allows = false
        let notifier = Notifier(poster: poster, store: store())
        notifier.deliver([alert(.sessionWaiting)])
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(poster.posted.isEmpty)
        XCTAssertFalse(notifier.isDenied)

        poster.denied = true
        notifier.deliver([alert(.sessionWaiting)])
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(poster.posted.isEmpty)
        XCTAssertTrue(notifier.isDenied)
    }
}
