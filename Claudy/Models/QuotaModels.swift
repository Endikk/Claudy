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

/// Full reading of the account's quotas at one instant.
struct QuotaReading: Equatable {
    var session: QuotaWindow?
    var weekly: QuotaWindow?
    /// Weekly window scoped to one model ("weekly_scoped").
    var scoped: QuotaWindow?
    var source: QuotaSource

    var isEmpty: Bool { session == nil && weekly == nil && scoped == nil }
}
