import Foundation

/// One quota window as the account actually reports it. `percent` is Anthropic's own value,
/// never a local estimate.
struct QuotaWindow: Equatable {
    /// 0…1
    let percent: Double
    /// Reset instant announced by Anthropic; `nil` when the window is idle.
    let resetsAt: Date?
    /// Model name for a per-model window ("Fable", "Sonnet"…), `nil` otherwise.
    let label: String?

    init(percent: Double, resetsAt: Date?, label: String? = nil) {
        self.percent = min(max(percent, 0), 1)
        self.resetsAt = resetsAt
        self.label = label
    }
}

/// Where the displayed percentages come from. The UI always states it: a number with no known
/// origin is a number nobody can trust.
enum QuotaSource: Equatable {
    /// `GET /api/oauth/usage` — the exact values behind claude.ai ▸ Usage and `/usage`.
    case api
    /// `anthropic-ratelimit-unified-*` headers relayed by Claude Code's status line: the same
    /// counters, seen from API responses, without an extra request.
    case bridge
    /// Last known reading, the account being momentarily unreachable.
    case stale(Date)
    /// No measurement: gauges stay empty rather than showing an estimate.
    case unavailable
    /// Claude Code is not installed, so the sample data set is shown and labelled as such.
    case demo

    var isMeasured: Bool {
        switch self {
        case .api, .bridge, .stale, .demo: true
        case .unavailable: false
        }
    }

    /// Short badge shown in the header, `nil` when the source is the reference one.
    var badge: String? {
        switch self {
        case .api: nil
        case .bridge: "relay"
        case .stale: "⟳"
        case .unavailable: "offline"
        case .demo: "demo"
        }
    }
}

/// Monthly spend cap of a usage-billed plan (Enterprise), as the account reports it. Such a plan
/// has no 5-hour or weekly window: this cap is its only quota.
struct SpendReading: Equatable {
    /// Amounts in major units: 46.31 means $46.31.
    let used: Double
    /// Always above zero: no cap, or a zero one, is not a quota and never becomes a reading.
    let limit: Double
    /// ISO 4217 code, "USD".
    let currency: String
    /// Anthropic's own verdict, which can come before `used` reaches `limit` to the cent.
    let isLimitReached: Bool
    let resetsAt: Date

    /// 0…1, from the amounts rather than the rounded `percent` the API also sends.
    var percent: Double { limit > 0 ? min(max(used / limit, 0), 1) : 0 }

    var startsAt: Date { Self.utc.date(byAdding: .month, value: -1, to: resetsAt) ?? resetsAt }

    /// Spend caps reset at 00:00 UTC on the first of each month. The API does not send that
    /// instant, so it is derived from the rule, which is also what claude.ai ▸ Usage shows.
    static func periodEnd(after date: Date) -> Date {
        let month = utc.dateComponents([.year, .month], from: date)
        let start = utc.date(from: month) ?? date
        return utc.date(byAdding: .month, value: 1, to: start) ?? date
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
}

/// Full reading of the account's quotas at one instant.
struct QuotaReading: Equatable {
    var session: QuotaWindow?
    var weekly: QuotaWindow?
    /// Weekly window scoped to one model ("weekly_scoped").
    var scoped: QuotaWindow?
    /// Monthly spend cap, set only on a plan that reports no window.
    var spend: SpendReading? = nil
    var source: QuotaSource

    var isEmpty: Bool { session == nil && weekly == nil && scoped == nil && spend == nil }
}
