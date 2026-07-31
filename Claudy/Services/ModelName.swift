import Foundation

/// Traduction d'un identifiant de modèle brut en libellé affichable, sans table codée en dur :
/// n'importe quel modèle passé ou futur respectant la convention `claude-<famille>-<version>`
/// (ou `claude-<version>-<famille>`) est rendu correctement.
///
/// `claude-opus-4-8` → « Opus 4.8 » · `claude-3-5-haiku-20241022` → « Haiku 3.5 »
enum ModelName {

    static func display(_ identifier: String) -> String {
        let parts = identifier
            .replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .map(String.init)

        let family = parts.first { Int($0) == nil } ?? identifier
        // Les composants de 8 chiffres sont des dates de version, pas des numéros de modèle.
        let version = parts.filter { Int($0) != nil && $0.count <= 2 }

        let label = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? label : "\(label) \(version.joined(separator: "."))"
    }

    /// Accent attribué à une famille de modèles ; les familles inconnues tournent sur la palette.
    static func accent(_ identifier: String) -> Theme.Accent {
        let lowercased = identifier.lowercased()
        if lowercased.contains("opus") { return .coral }
        if lowercased.contains("sonnet") { return .violet }
        if lowercased.contains("haiku") { return .sky }
        return .sage
    }

    static func isSonnet(_ identifier: String) -> Bool {
        family(identifier) == "sonnet"
    }

    /// Famille du modèle, en minuscules : « opus », « sonnet », « haiku »…
    /// Sert à regrouper les versions successives d'une même famille dans une seule jauge.
    static func family(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .first { Int($0) == nil }
            .map { $0.lowercased() } ?? identifier.lowercased()
    }

    /// Les lignes `<synthetic>` sont générées localement par Claude Code, sans appel au modèle.
    static func isReal(_ identifier: String) -> Bool {
        !identifier.isEmpty && !identifier.hasPrefix("<")
    }
}
