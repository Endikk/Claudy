import Foundation

/// Source of usage data.
protocol UsageDataSource: Sendable {
    func fetch() async throws -> UsageSnapshot
}

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

    private let scanner = TranscriptScanner()
    private let client = ClaudeAccountClient.shared

    func fetch() async throws -> UsageSnapshot {
        guard ClaudeHome.isInstalled else { throw UsageDataError.claudeNotInstalled }

        let entries = try await scanner.scan()
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

        var snapshot = UsageAggregator.snapshot(from: entries, account: account, reading: reading)
        snapshot.isSignedIn = payload.isSignedIn
        return snapshot
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
