import Foundation

/// A request-free source: the `anthropic-ratelimit-unified-*` counters Claude Code already
/// receives on every API response and pipes to its status line, which one `tee` can drop here.
///
/// Same figures as `/api/oauth/usage`, immune to rate limiting, but they only move while Claude
/// Code works and cover the 5-hour and weekly windows only. A safety net, not the primary source.
enum UsageBridge {

    /// Past this age a reading describes a session long finished and says nothing about the
    /// current window.
    private static let freshness: TimeInterval = 30 * 60

    static var file: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Claudy", isDirectory: true)
            .appendingPathComponent("usage-bridge.json")
    }

    /// Status-line command to add to `~/.claude/settings.json`, offered for copying rather than
    /// installed outright: overwriting someone's status line unasked is not ours to do.
    static var statuslineSnippet: String {
        #"tee "$HOME/Library/Application Support/Claudy/usage-bridge.json" > /dev/null"#
    }

    /// Latest reading dropped by Claude Code, when it is still current. The file is rewritten on
    /// every status-line render, so its modification date times the reading far better than its
    /// contents do.
    static func read(now: Date = Date()) -> QuotaReading? {
        guard let file, let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        guard now.timeIntervalSince(modified) < freshness else { return nil }

        guard let limits = root["rate_limits"] as? [String: Any] else { return nil }
        let session = window(limits["five_hour"])
        let weekly = window(limits["seven_day"])
        guard session != nil || weekly != nil else { return nil }

        return QuotaReading(session: session, weekly: weekly, scoped: nil, source: .bridge)
    }

    /// Two shapes coexist depending on the Claude Code version: `used_percentage` (0…100) with a
    /// Unix-seconds `resets_at` on the status-line side, `utilization` with an ISO `resets_at` on
    /// the SDK side. Both are accepted rather than depending on a detail that has already moved.
    private static func window(_ raw: Any?) -> QuotaWindow? {
        guard let object = raw as? [String: Any] else { return nil }
        let percent = (object["used_percentage"] as? NSNumber) ?? (object["utilization"] as? NSNumber)
        guard let percent else { return nil }

        var resetsAt: Date?
        if let seconds = object["resets_at"] as? NSNumber {
            resetsAt = Date(timeIntervalSince1970: seconds.doubleValue)
        } else if let stamp = object["resets_at"] as? String {
            resetsAt = ClaudeAccountClient.date(from: stamp)
        }
        return QuotaWindow(percent: percent.doubleValue / 100, resetsAt: resetsAt)
    }
}
