import Foundation

/// Turns a raw model identifier into a display label without a hardcoded table, so any past or
/// future model following `claude-<family>-<version>` (or `claude-<version>-<family>`) renders.
///
/// `claude-opus-4-8` → "Opus 4.8" · `claude-3-5-haiku-20241022` → "Haiku 3.5"
enum ModelName {

    /// Display label. Eight-digit components are release dates, not version numbers, so only
    /// short numeric parts contribute to the version.
    static func display(_ identifier: String) -> String {
        let parts = identifier
            .replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .map(String.init)

        let family = parts.first { Int($0) == nil } ?? identifier
        let version = versionNumbers(identifier).map(String.init)

        let label = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? label : "\(label) \(version.joined(separator: "."))"
    }

    /// Accent assigned to a model family; unknown families fall through to the neutral tone.
    static func accent(_ identifier: String) -> Theme.Accent {
        let lowercased = identifier.lowercased()
        if lowercased.contains("opus") { return .coral }
        if lowercased.contains("sonnet") { return .violet }
        if lowercased.contains("haiku") { return .sky }
        return .sage
    }

    /// Lowercased family name — "opus", "sonnet", "haiku" — used to group successive versions
    /// of one family under a single gauge.
    static func family(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .first { Int($0) == nil }
            .map { $0.lowercased() } ?? identifier.lowercased()
    }

    /// Input price per million tokens, in dollars, from Anthropic's public list. Only the ratios
    /// matter: they turn a token count into what it weighs against the quota, where one Opus
    /// token costs five Haiku tokens. Unknown families take the mid-range price rather than zero,
    /// so a new model is never silently left out of the ranking.
    static func inputPrice(_ identifier: String) -> Double {
        let version = versionNumbers(identifier)
        let major = version.first ?? 0
        let minor = version.count > 1 ? version[1] : 0
        let atLeast = { (maj: Int, min: Int) in major > maj || (major == maj && minor >= min) }

        switch family(identifier) {
        case "fable", "mythos": return 10
        case "opus": return atLeast(4, 5) ? 5 : 15
        case "sonnet": return atLeast(5, 0) ? 2 : 3
        case "haiku": return atLeast(4, 5) ? 1 : (atLeast(3, 5) ? 0.8 : 0.25)
        default: return 3
        }
    }

    /// `[4, 5]` for `claude-haiku-4-5-20251001` and for `claude-3-5-haiku`: dates are dropped.
    private static func versionNumbers(_ identifier: String) -> [Int] {
        identifier
            .replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .filter { $0.count <= 2 }
            .compactMap { Int($0) }
    }

    /// False for `<synthetic>` entries, which Claude Code generates locally without calling a model.
    static func isReal(_ identifier: String) -> Bool {
        !identifier.isEmpty && !identifier.hasPrefix("<")
    }
}
