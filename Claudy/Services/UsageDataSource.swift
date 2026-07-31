import Foundation

/// Source des données d'usage.
protocol UsageDataSource: Sendable {
    func fetch() async throws -> UsageSnapshot
}

enum UsageDataError: Error {
    /// Aucune trace de Claude Code sur cette machine.
    case claudeNotInstalled
    /// Le dossier des transcripts existe mais ne se laisse pas lire (droits, disque).
    case projectsUnreadable
}

/// Source réelle : transcripts locaux de Claude Code.
///
/// Il n'existe pas d'API publique donnant la consommation d'un compte ; la seule source
/// disponible est `<config>/projects/**/*.jsonl`, que Claude Code écrit à chaque réponse.
actor LocalUsageDataSource: UsageDataSource {

    private let scanner = TranscriptScanner()
    private let quotaLoader = QuotaLoader()

    func fetch() async throws -> UsageSnapshot {
        guard ClaudeHome.isInstalled else { throw UsageDataError.claudeNotInstalled }

        let result = try await scanner.scan()
        // Quotas réels du compte quand le jeton local le permet ; `nil` (hors-ligne, pas de
        // jeton) fait retomber les jauges sur la référence personnelle.
        let quotas = await quotaLoader.fetch()
        return UsageAggregator.snapshot(from: result.entries, account: AccountLoader.load(), quotas: quotas)
    }
}

/// Bascule automatique : les vraies données si Claude Code est présent, la démonstration sinon.
/// Le choix est refait à chaque rafraîchissement — installer Claude Code après coup suffit.
struct AdaptiveUsageDataSource: UsageDataSource {

    private let local = LocalUsageDataSource()
    private let demo = DemoUsageDataSource()

    func fetch() async throws -> UsageSnapshot {
        do {
            return try await local.fetch()
        } catch UsageDataError.claudeNotInstalled {
            // Seule l'absence de Claude Code justifie la démonstration : toute autre panne
            // doit remonter à l'interface plutôt que d'afficher des chiffres inventés.
            return try await demo.fetch()
        }
    }
}
