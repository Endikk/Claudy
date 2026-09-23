import Foundation

/// One quota window as the card renders it: session 5h, weekly, per-model.
struct UsageWindow {
    /// Displayed title: "Session", "Weekly", or the model name.
    let title: String
    /// Window qualifier: "5h", "7d".
    let window: String
    /// 0…1 as the account reports it. With no measurement this is 0 and `isMeasured` is false,
    /// so the UI shows "—" rather than that zero.
    var percent: Double
    /// Tokens recorded on this machine during the window. A local count, unrelated to the
    /// percentage — Anthropic's quota is not a token tally.
    var tokensUsed: Int
    /// Start of the window, which is what sets the expected pace.
    var windowStart: Date
    var resetDate: Date

    var accent: Theme.Accent

    /// True when `percent` comes from a real account quota; false when no measurement exists.
    var isMeasured: Bool = true

    /// Money behind the percentage, on a monthly spend cap only. It replaces the token line: a
    /// month of tokens is not something the local transcripts can count.
    var amount: SpendReading? = nil

    /// False when no window is running: there is nothing to count down, and showing a reset
    /// time already in the past would be a lie.
    var isActive: Bool { isMeasured && resetDate > Date() }

    /// End of this machine's current activity block, when the transcripts show one. Kept apart
    /// from `resetDate` so it can animate Claudy without ever turning into a countdown.
    var localActivityEnd: Date? = nil

    /// True while a window runs on the account or Claude Code works on this machine. This is
    /// what animates Claudy: `isActive` alone freezes the mascot whenever the account has no
    /// window to report, unreadable quota or Claude Code billing another account alike.
    var isRunning: Bool {
        let now = Date()
        return resetDate > now || (localActivityEnd.map { $0 > now } ?? false)
    }

    /// Share of the window already elapsed, 0…1. This is where the pace marker sits: halfway
    /// through a window, steady consumption would read 50 %.
    var elapsed: Double {
        let duration = resetDate.timeIntervalSince(windowStart)
        guard duration > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(windowStart) / duration, 0), 1)
    }

    /// Distance from the expected pace, in percentage points. Positive means ahead of the clock.
    var paceDelta: Double { percent - elapsed }
}

/// One point of the daily history feeding the sparkline.
struct TokenSample: Identifiable, Equatable {
    let id: Date
    let date: Date
    var tokens: Int

    init(date: Date, tokens: Int) {
        self.id = date
        self.date = date
        self.tokens = tokens
    }
}

/// Seven-day split by model.
struct ModelUsage: Identifiable {
    let id: String
    let name: String
    var tokens: Int
    /// Share of the total, 0…1
    var share: Double
    let accent: Theme.Accent
}

/// Seven-day split by project.
struct ProjectUsage: Identifiable {
    let id: String
    let name: String
    var tokens: Int
    /// Share of the total, 0…1
    var share: Double
}

/// Signed-in account.
struct Account {
    let name: String
    let email: String
    let plan: String
    let organization: String
    let isAdmin: Bool

    var initial: String {
        let letter = name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        return letter.isEmpty ? "?" : letter
    }
}

/// Everything the view renders at one instant. A single structure, so the view model can never
/// expose a half-updated state.
struct UsageSnapshot {
    var session: UsageWindow
    var weekly: UsageWindow
    var sonnet: UsageWindow
    /// Monthly spend cap of a usage-billed plan (Enterprise), `nil` on plans metered in windows.
    /// Such a plan has no session or weekly quota, so this gauge leads the card instead.
    var spend: UsageWindow? = nil

    /// The gauge the card leads with. `session` still drives the mascot either way: it is placed
    /// from local activity when the account has no 5-hour window.
    var primary: UsageWindow { spend ?? session }

    /// Seven points, oldest first; the last one is today and therefore partial.
    var history: [TokenSample]
    var models: [ModelUsage]
    var projects: [ProjectUsage]

    var account: Account
    var activeModel: String
    var todayTokens: Int
    var weekTokens: Int
    var sessionCount: Int
    var updatedAt: Date

    /// Where the displayed percentages come from. The UI announces it: this is what separates
    /// an account reading from a last known state, and both from an absence of measurement.
    var quotaSource: QuotaSource

    /// True when Claude Code is missing from the machine, which the UI states rather than
    /// passing sample values off as a real reading.
    var isDemo: Bool { quotaSource == .demo }

    /// True when a Claude token is available, so the gauges show real quotas. False sends the
    /// card to onboarding — never to estimated quotas.
    var isSignedIn: Bool = false

    /// Strain: 0 below 95 % on every gauge, 1 at 100 %. Above 0 the card's hairline reddens —
    /// a signal you catch without reading a number. An unmeasured gauge never triggers it:
    /// nothing raises an alarm about a figure we do not have.
    var strain: Double {
        let peak = ([session, weekly, sonnet] + [spend].compactMap { $0 })
            .filter(\.isMeasured).map(\.percent).max() ?? 0
        return min(max((peak - 0.95) / 0.05, 0), 1)
    }

    /// A quota that blocks work is full: the 5h session, the weekly limit, or the monthly spend
    /// cap. The per-model window is left out, since another model still answers. Unmeasured
    /// windows never count.
    var isOverloaded: Bool {
        if spend?.amount?.isLimitReached == true { return true }
        return ([session, weekly] + [spend].compactMap { $0 })
            .contains { $0.isMeasured && $0.percent >= 1 }
    }

    /// State shown before the first `fetch()` — never visible for more than a few milliseconds,
    /// but it spares every view an optional.
    static let placeholder = UsageSnapshot(
        session: UsageWindow(title: "Session", window: "5h",
                             percent: 0, tokensUsed: 0,
                             windowStart: .now, resetDate: .now, accent: .coral,
                             isMeasured: false),
        weekly: UsageWindow(title: "Weekly", window: "7d",
                            percent: 0, tokensUsed: 0,
                            windowStart: .now, resetDate: .now, accent: .amber,
                            isMeasured: false),
        sonnet: UsageWindow(title: "Per model", window: "7d",
                            percent: 0, tokensUsed: 0,
                            windowStart: .now, resetDate: .now, accent: .violet,
                            isMeasured: false),
        history: [],
        models: [],
        projects: [],
        account: Account(name: "", email: "", plan: "", organization: "", isAdmin: false),
        activeModel: "",
        todayTokens: 0,
        weekTokens: 0,
        sessionCount: 0,
        updatedAt: .now,
        quotaSource: .unavailable
    )
}
