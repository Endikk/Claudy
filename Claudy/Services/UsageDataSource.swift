import Foundation

/// Source of usage data.
protocol UsageDataSource: Sendable {
    func fetch() async throws -> UsageSnapshot
}

/// Where the token detail comes from: `TranscriptScanner` in the app, a stub in tests.
protocol TranscriptSource: Sendable {
    func scan() async throws -> [TranscriptEntry]
}

extension TranscriptScanner: TranscriptSource {}

enum UsageDataError: Error {
    /// No trace of Claude Code on this machine.
    case claudeNotInstalled
    /// The transcript folder exists but will not be read (permissions, disk).
    case projectsUnreadable
}

/// Real source: the account's quotas for the gauges, Claude Code's local transcripts for the
/// token detail.
///
/// Source order is deliberate. The account reading comes first; failing that, the counters
/// Claude Code already received in its headers and relayed through the status line — same
/// figures, zero requests. A stale reading yields to a fresh bridge.
actor LocalUsageDataSource: UsageDataSource {

    private let scanner: TranscriptSource
    private let client: ClaudeAccountClient
    private let isInstalled: @Sendable () -> Bool
    /// Set once a pass over the history has ended, read or failed. From then on each reading
    /// waits for the history, so a read error reaches the card as it always did.
    private var hasReadHistory = false
    /// The pass under way, joined rather than started again by a reading that comes meanwhile.
    private var pass: Task<[TranscriptEntry], Error>?

    init(scanner: TranscriptSource = TranscriptScanner(),
         client: ClaudeAccountClient = .shared,
         isInstalled: @escaping @Sendable () -> Bool = { ClaudeHome.isInstalled }) {
        self.scanner = scanner
        self.client = client
        self.isInstalled = isInstalled
    }

    func fetch() async throws -> UsageSnapshot {
        guard isInstalled() else { throw UsageDataError.claudeNotInstalled }

        // The history is read alongside the account rather than before it: a first pass over a
        // large one takes a moment, and who is signed in is known in milliseconds.
        let scan = readHistory()
        let payload = await client.fetch()

        // Signed out on purpose means no quota at all: the bar would otherwise keep a percentage
        // relayed by Claude Code's status line next to a card saying "not signed in".
        let bridge = payload.isSignedOutByUser ? nil : UsageBridge.read()
        let reading = Self.merge(account: payload.reading, bridge: bridge)

        var account = AccountLoader.load()
        if let profile = payload.profile {
            account = Account(
                name: profile.name,
                email: profile.email,
                plan: profile.plan,
                organization: profile.organization,
                isAdmin: account.isAdmin
            )
        }

        // The sign-in card shows no token count, so it never waits for the history. It takes it
        // once a pass has finished, which keeps the menu bar icon typing on local activity.
        let entries = payload.isSignedIn || hasReadHistory ? try await scan.value : []
        var snapshot = UsageAggregator.snapshot(from: entries, account: account, reading: reading)
        snapshot.isSignedIn = payload.isSignedIn
        return snapshot
    }

    private func readHistory() -> Task<[TranscriptEntry], Error> {
        if let pass { return pass }
        let scanner = self.scanner
        let pass = Task {
            defer {
                self.hasReadHistory = true
                self.pass = nil
            }
            return try await scanner.scan()
        }
        self.pass = pass
        return pass
    }

    /// The account's reading, unless it is not fresh and the status-line bridge has one. A last
    /// spend reading stays: the bridge only relays 5-hour and weekly windows, which a plan billed
    /// on usage does not have, so any it carries describe another account.
    static func merge(account: QuotaReading?, bridge: QuotaReading?) -> QuotaReading? {
        guard let bridge else { return account }
        if let account, account.source == .api || account.spend != nil { return account }
        return bridge
    }
}

/// Automatic switch: real data when Claude Code is present, the demo set otherwise. The choice is
/// remade on every refresh, so installing Claude Code afterwards is enough.
struct AdaptiveUsageDataSource: UsageDataSource {

    private let local = LocalUsageDataSource()
    private let demo = DemoUsageDataSource()

    /// Only the absence of Claude Code justifies the demo set: any other failure must surface in
    /// the UI rather than show invented figures.
    func fetch() async throws -> UsageSnapshot {
        do {
            return try await local.fetch()
        } catch UsageDataError.claudeNotInstalled {
            return try await demo.fetch()
        }
    }
}
