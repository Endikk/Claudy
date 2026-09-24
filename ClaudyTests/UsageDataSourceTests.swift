import XCTest
@testable import Claudy

/// A history read that only ends when the test says so, standing in for a first pass over a
/// large history.
private actor HeldScanner: TranscriptSource {
    private let entries: [TranscriptEntry]
    private let failure: Error?
    private var isReleased = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var passes = 0

    init(entries: [TranscriptEntry] = [], failure: Error? = nil) {
        self.entries = entries
        self.failure = failure
    }

    func scan() async throws -> [TranscriptEntry] {
        passes += 1
        if !isReleased { await withCheckedContinuation { waiting.append($0) } }
        if let failure { throw failure }
        return entries
    }

    func release() {
        isReleased = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}

/// The card must not wait for the history to decide what to show: the account is read alongside
/// it, and the sign-in card, which shows no token count, does not wait for it at all.
final class UsageDataSourceTests: XCTestCase {

    private var store: UserDefaults!
    private let suite = "claudy.tests.datasource"

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

    func testSignInCardDoesNotWaitForTheHistory() async throws {
        let scanner = HeldScanner(entries: [entry()])
        let source = LocalUsageDataSource(scanner: scanner, client: client(token: nil), isInstalled: { true })

        let (finishedEarly, snapshot) = try await fetch(source, releasing: scanner)

        XCTAssertTrue(finishedEarly, "the sign-in card waited for the history to be read")
        XCTAssertFalse(snapshot.isSignedIn)
    }

    func testAccountIsReadWhileTheHistoryIsStillBeingRead() async throws {
        StubbedAnthropic.usage = (200, Self.usage)
        let scanner = HeldScanner(entries: [entry(tokens: 1_234)])
        let source = LocalUsageDataSource(scanner: scanner, client: client(token: token), isInstalled: { true })

        let fetch = Task { try await source.fetch() }
        try await waitUntil { StubbedAnthropic.usageRequests > 0 }
        let askedBeforeTheHistoryEnded = StubbedAnthropic.usageRequests > 0
        await scanner.release()
        let snapshot = try await fetch.value

        XCTAssertTrue(askedBeforeTheHistoryEnded)
        XCTAssertTrue(snapshot.isSignedIn)
        XCTAssertEqual(snapshot.todayTokens, 1_234, "a signed-in card waits for its token counts")
    }

    func testSignedOutCardPicksTheHistoryUpOnceItIsRead() async throws {
        let scanner = HeldScanner(entries: [entry(tokens: 50)])
        let source = LocalUsageDataSource(scanner: scanner, client: client(token: nil), isInstalled: { true })

        _ = try await fetch(source, releasing: scanner)
        try await Task.sleep(nanoseconds: 100_000_000)
        let next = try await source.fetch()

        XCTAssertEqual(next.todayTokens, 50, "local activity still animates the menu bar icon")
    }

    /// A signed-out card does not wait for the history, but a read that failed must still show:
    /// "Could not read the transcripts folder" is how the user learns about a permission problem.
    func testHistoryReadFailureSurfacesOnTheSignInCardToo() async throws {
        let scanner = HeldScanner(failure: UsageDataError.projectsUnreadable)
        let source = LocalUsageDataSource(scanner: scanner, client: client(token: nil), isInstalled: { true })

        _ = try await fetch(source, releasing: scanner)
        try await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await source.fetch()
            XCTFail("the failed read was swallowed")
        } catch UsageDataError.projectsUnreadable {
            // Expected.
        }
    }

    /// The sign-in card is read again every 10 s; a first pass that takes longer must not be
    /// started a second time.
    func testSlowFirstPassIsJoinedNotRepeated() async throws {
        let scanner = HeldScanner()
        let source = LocalUsageDataSource(scanner: scanner, client: client(token: nil), isInstalled: { true })

        _ = try await source.fetch()
        _ = try await source.fetch()
        await scanner.release()

        let passes = await scanner.passes
        XCTAssertEqual(passes, 1)
    }

    // MARK: - Helpers

    private let token = OAuthCredentials(accessToken: "borrowed", refreshToken: nil,
                                         expiresAt: Date().addingTimeInterval(3600), root: [:],
                                         source: .claudeCode)

    private func client(token: OAuthCredentials?) -> ClaudeAccountClient {
        ClaudeAccountClient(store: store, borrowedToken: { token }, ownToken: .empty)
    }

    private func entry(tokens: Int = 10) -> TranscriptEntry {
        TranscriptEntry(date: Date().addingTimeInterval(-60), model: "claude-opus-5", tokens: tokens,
                        weight: 1, cwd: "/w/Claudy", project: "/w/Claudy", sessionID: "s",
                        isSidechain: false, dedupKey: UUID().uuidString)
    }

    /// Fetches while the history is held, then lets it go whatever happened, so a fetch that
    /// waits for it fails the test instead of hanging it.
    private func fetch(_ source: LocalUsageDataSource,
                       releasing scanner: HeldScanner) async throws -> (Bool, UsageSnapshot) {
        let done = Flag()
        let fetch = Task { () throws -> UsageSnapshot in
            let snapshot = try await source.fetch()
            await done.set()
            return snapshot
        }
        try? await waitUntil { await done.isSet }
        let finishedEarly = await done.isSet
        await scanner.release()
        return (finishedEarly, try await fetch.value)
    }

    private struct Timeout: Error {}

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<40 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw Timeout()
    }

    private static let usage = Data("""
    {"five_hour": {"utilization": 40.0, "resets_at": "2099-01-01T00:00:00.000000+00:00"},
     "seven_day": {"utilization": 10.0, "resets_at": "2099-01-05T00:00:00.000000+00:00"}}
    """.utf8)
}
