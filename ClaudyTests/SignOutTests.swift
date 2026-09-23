import XCTest
@testable import Claudy

/// Signing Claudy out must hold even while Claude Code stays signed in: the borrowed token would
/// otherwise take over at the next reading and the button would do nothing.
final class SignOutTests: XCTestCase {

    private var store: UserDefaults!
    private let suite = "claudy.tests.signout"

    override func setUp() {
        store = UserDefaults(suiteName: suite)
        store.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
        URLProtocol.unregisterClass(HeldAPI.self)
    }

    private func claudeCodeToken(_ value: String = "borrowed", expiresIn: TimeInterval = 3600) -> OAuthCredentials {
        OAuthCredentials(accessToken: value, refreshToken: nil,
                         expiresAt: Date().addingTimeInterval(expiresIn), root: [:], source: .claudeCode)
    }

    /// The keychain is never reached: Claude Code's token comes from the stub, and the erasing
    /// of Claudy's own item is only counted.
    private func client(borrowed: OAuthCredentials?, erased: (() -> Void)? = nil) -> ClaudeAccountClient {
        ClaudeAccountClient(store: store, borrowedToken: { borrowed }, eraseOwnToken: erased ?? {})
    }

    // MARK: - Signing out

    func testSignOutErasesClaudysTokenAndHoldsAcrossARelaunch() async {
        var erasures = 0
        let running = client(borrowed: claudeCodeToken(), erased: { erasures += 1 })

        await running.signOut()
        let relaunched = client(borrowed: claudeCodeToken())
        let payload = await relaunched.fetch()

        XCTAssertEqual(erasures, 1)
        XCTAssertFalse(payload.isSignedIn)
        XCTAssertTrue(payload.isSignedOutByUser)
        XCTAssertNil(payload.reading)
        XCTAssertNil(payload.profile)
    }

    func testSignedOutClientIgnoresClaudeCodesToken() async {
        store.set(true, forKey: ClaudeAccountClient.signedOutKey)
        let client = client(borrowed: claudeCodeToken())

        let payload = await client.fetch()

        XCTAssertFalse(payload.isSignedIn)
        XCTAssertNil(payload.reading)
        XCTAssertNil(payload.profile)
    }

    // MARK: - Signing back in

    func testSigningBackInReusesClaudeCodesSessionWithoutABrowser() async {
        store.set(true, forKey: ClaudeAccountClient.signedOutKey)
        let client = client(borrowed: claudeCodeToken())

        let resumed = await client.resumeWithClaudeCode()

        XCTAssertTrue(resumed)
        let isSignedOut = await client.isSignedOutByUser
        XCTAssertFalse(isSignedOut)
        XCTAssertFalse(store.bool(forKey: ClaudeAccountClient.signedOutKey))
    }

    func testSigningBackInNeedsTheBrowserWhenClaudeCodeIsSignedOut() async {
        store.set(true, forKey: ClaudeAccountClient.signedOutKey)
        let client = client(borrowed: nil)

        let resumed = await client.resumeWithClaudeCode()

        XCTAssertFalse(resumed)
        let isSignedOut = await client.isSignedOutByUser
        XCTAssertTrue(isSignedOut)
    }

    func testExpiredClaudeCodeTokenDoesNotCountAsASession() async {
        store.set(true, forKey: ClaudeAccountClient.signedOutKey)
        let client = client(borrowed: claudeCodeToken(expiresIn: -60))

        let resumed = await client.resumeWithClaudeCode()

        XCTAssertFalse(resumed)
    }

    // MARK: - A reading still in flight when the session changes

    /// Sign out, then straight back in, while a reading waits on the network. What it brings back
    /// belongs to the session that ended: it must not be served, nor cached for the next reading.
    func testReadingInFlightAcrossASessionChangeIsDropped() async throws {
        HeldAPI.reset(token: "signout-race")
        URLProtocol.registerClass(HeldAPI.self)
        let client = client(borrowed: claudeCodeToken("signout-race"))

        let inFlight = Task { await client.fetch() }
        let arrived = await Task.detached { HeldAPI.arrived.wait(timeout: .now() + 5) }.value
        XCTAssertEqual(arrived, .success, "the usage request never reached the stub")

        await client.signOut()
        let resumed = await client.resumeWithClaudeCode()
        XCTAssertTrue(resumed)
        HeldAPI.usageStatus = 503
        HeldAPI.release.signal()

        let stale = await inFlight.value
        XCTAssertNil(stale.reading, "a reading from the previous session was served")
        XCTAssertNil(stale.profile)

        let next = await client.fetch()
        XCTAssertNil(next.reading, "a reading from the previous session was cached")
        XCTAssertNil(next.profile, "a profile from the previous session was cached")
    }
}

/// Stands in for Anthropic's API, for one test token only, so the app hosting the tests keeps its
/// own traffic. The first usage request is held until `release` is signalled.
private final class HeldAPI: URLProtocol {
    private static var bearer = ""
    static var usageStatus = 200
    private static var holds = true
    static var arrived = DispatchSemaphore(value: 0)
    static var release = DispatchSemaphore(value: 0)

    static func reset(token: String) {
        bearer = "Bearer \(token)"
        usageStatus = 200
        holds = true
        arrived = DispatchSemaphore(value: 0)
        release = DispatchSemaphore(value: 0)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "Authorization") == bearer
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isUsage = request.url?.path.hasSuffix("/usage") == true
        let held = isUsage && Self.holds
        if held { Self.holds = false }
        // Decided on arrival: the held request answers as the server stood when it was sent.
        let status = isUsage ? Self.usageStatus : 200

        DispatchQueue.global().async { [self] in
            if held {
                Self.arrived.signal()
                _ = Self.release.wait(timeout: .now() + 5)
            }
            let body = isUsage ? Self.usage : Self.profile
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: status == 200 ? body : Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static let usage = Data("""
    {"five_hour": {"utilization": 42, "resets_at": "2099-01-01T00:00:00Z"},
     "seven_day": {"utilization": 17, "resets_at": "2099-01-05T00:00:00Z"}}
    """.utf8)

    private static let profile = Data("""
    {"account": {"full_name": "Previous Account", "email": "previous@example.com"}}
    """.utf8)
}
