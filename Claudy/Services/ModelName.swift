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
        let version = parts.filter { Int($0) != nil && $0.count <= 2 }

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

    /// False for `<synthetic>` entries, which Claude Code generates locally without calling a model.
    static func isReal(_ identifier: String) -> Bool {
        !identifier.isEmpty && !identifier.hasPrefix("<")
    }
}
