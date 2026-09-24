import XCTest
@testable import Claudy

/// The account client end to end on an Enterprise account: requests go through a stub, the token
/// is injected, and no keychain or network is ever touched.
final class EnterpriseAccountClientTests: XCTestCase {

    private var store: UserDefaults!
    private let suite = "claudy.tests.enterprise-client"

    private let enterpriseToken = OAuthCredentials(
        accessToken: "enterprise",
        refreshToken: nil,
        expiresAt: Date().addingTimeInterval(3600),
        root: ["claudeAiOauth": ["subscriptionType": "enterprise"]],
        source: .claudeCode
    )

    override func setUp() {
        store = UserDefaults(suiteName: suite)
        store.removePersistentDomain(forName: suite)
        StubbedAnthropic.reset()
        URLProtocol.registerClass(StubbedAnthropic.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubbedAnthropic.self)
        store.removePersistentDomain(forName: suite)
    }

    private func client() -> ClaudeAccountClient {
        let token = enterpriseToken
        return ClaudeAccountClient(store: store, borrowedToken: { token }, ownToken: .empty)
    }

    func testEnterpriseAnswerIsAReadingNotAFailure() async throws {
        StubbedAnthropic.usage = (200, Self.enterpriseUsage)
        StubbedAnthropic.profile = (200, Self.enterpriseProfile)

        let payload = await client().fetch()

        let spend = try XCTUnwrap(payload.reading?.spend)
        XCTAssertEqual(payload.reading?.source, .api)
        XCTAssertEqual(spend.used, 46.31, accuracy: 0.0001)
        XCTAssertEqual(spend.limit, 500, accuracy: 0.0001)
        XCTAssertTrue(payload.isSignedIn)
    }

    /// The profile only says "default_claude_zero"; the token's `subscriptionType` names the plan.
    func testPlanReadsEnterpriseFromTheTokenWhenTheTierHidesIt() async throws {
        StubbedAnthropic.usage = (200, Self.enterpriseUsage)
        StubbedAnthropic.profile = (200, Self.enterpriseProfile)

        let payload = await client().fetch()

        XCTAssertEqual(try XCTUnwrap(payload.profile).plan, "Enterprise")
    }

    func testSpendSurvivesAFailedRefreshAsAStaleReading() async throws {
        StubbedAnthropic.usage = (200, Self.enterpriseUsage)
        StubbedAnthropic.profile = (200, Self.enterpriseProfile)
        let client = client()
        _ = await client.fetch()

        StubbedAnthropic.usage = (503, Data())
        await client.resetBackoff()
        let payload = await client.fetch()

        let reading = try XCTUnwrap(payload.reading)
        guard case .stale = reading.source else { return XCTFail("expected a stale reading, got \(reading.source)") }
        XCTAssertEqual(try XCTUnwrap(reading.spend).used, 46.31, accuracy: 0.0001)
    }

    /// Same path on a Max account: a failing manual refresh must not wipe the gauges either.
    func testWindowsSurviveAFailedManualRefresh() async throws {
        StubbedAnthropic.usage = (200, Data("""
        {"five_hour": {"utilization": 40.0, "resets_at": "2099-01-01T00:00:00.000000+00:00"},
         "seven_day": {"utilization": 10.0, "resets_at": "2099-01-05T00:00:00.000000+00:00"}}
        """.utf8))
        let client = client()
        _ = await client.fetch()

        StubbedAnthropic.usage = (503, Data())
        await client.resetBackoff()
        let payload = await client.fetch()

        XCTAssertEqual(try XCTUnwrap(payload.reading?.session).percent, 0.40, accuracy: 0.0001)
    }

    /// A 200 carrying no quota at all (no window, no cap) is still no measurement: it must back
    /// off like any failure instead of hammering the endpoint every refresh.
    func testAnswerWithoutAnyQuotaBacksOff() async {
        StubbedAnthropic.usage = (200, Data(#"{"five_hour": null, "seven_day": null}"#.utf8))
        let client = client()

        let first = await client.fetch()
        let second = await client.fetch()

        XCTAssertNil(first.reading)
        XCTAssertNil(second.reading)
        XCTAssertEqual(StubbedAnthropic.usageRequests, 1)
    }

    // MARK: - Fixtures

    private static let enterpriseUsage = Data("""
    {
      "five_hour": null, "seven_day": null,
      "extra_usage": {"is_enabled": true, "monthly_limit": 50000, "used_credits": 4631,
                      "utilization": 9.262, "currency": "USD", "decimal_places": 2,
                      "spend_limit_reached": false},
      "spend": {"used": {"amount_minor": 4631, "currency": "USD", "exponent": 2},
                "limit": {"amount_minor": 50000, "currency": "USD", "exponent": 2},
                "percent": 9, "severity": "normal", "enabled": true}
    }
    """.utf8)

    private static let enterpriseProfile = Data("""
    {"account": {"full_name": "Ada Lovelace", "email": "ada@example.com"},
     "organization": {"name": "Acme", "rate_limit_tier": "default_claude_zero"}}
    """.utf8)
}

/// Answers for `api.anthropic.com` only; any other host goes to the real network untouched.
private final class StubbedAnthropic: URLProtocol {

    nonisolated(unsafe) static var usage: (Int, Data) = (500, Data())
    nonisolated(unsafe) static var profile: (Int, Data) = (404, Data())
    nonisolated(unsafe) static var usageRequests = 0

    static func reset() {
        usage = (500, Data())
        profile = (404, Data())
        usageRequests = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.anthropic.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let answer: (Int, Data)
        if url.path.hasSuffix("/usage") {
            Self.usageRequests += 1
            answer = Self.usage
        } else {
            answer = Self.profile
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.0, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
