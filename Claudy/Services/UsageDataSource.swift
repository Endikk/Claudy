import Foundation

/// Source des données d'usage.
protocol UsageDataSource: Sendable {
    func fetch() async throws -> UsageSnapshot
}

enum UsageDataError: Error {
    /// Aucune trace de Claude Code sur cette machine.
    case claudeNotInstalled
}

/// Source réelle : transcripts locaux de Claude Code.
///
/// Il n'existe pas d'API publique donnant la consommation d'un compte ; la seule source
/// disponible est `<config>/projects/**/*.jsonl`, que Claude Code écrit à chaque réponse.
actor LocalUsageDataSource: UsageDataSource {

    private let scanner = TranscriptScanner()

    func fetch() async throws -> UsageSnapshot {
        guard ClaudeHome.isInstalled else { throw UsageDataError.claudeNotInstalled }

        let result = await scanner.scan()
        return UsageAggregator.snapshot(from: result.entries, account: AccountLoader.load())
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
        } catch {
            return try await demo.fetch()
        }
    }
}
