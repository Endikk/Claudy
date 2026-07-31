import Foundation
import Security

/// Une limite réelle du compte, telle que rapportée par l'API OAuth d'Anthropic.
struct QuotaLimit {
    /// `session` (fenêtre 5 h), `weekly_all` (hebdo tous modèles), `weekly_scoped` (hebdo d'un modèle).
    let kind: String
    /// 0…1
    let percent: Double
    let resetsAt: Date
    /// Nom du modèle concerné pour `weekly_scoped` (« Fable », « Opus »…), `nil` sinon.
    let scopeName: String?
}

/// Quotas réels du compte, lus via l'API OAuth d'Anthropic avec le jeton que Claude Code
/// conserve localement (trousseau « Claude Code-credentials », sinon `.credentials.json`).
///
/// **Seule requête réseau de l'app** : `GET api.anthropic.com/api/oauth/usage`. Rien n'est
/// envoyé hormis le jeton d'authentification, et rien n'est écrit — le jeton n'est jamais
/// rafraîchi ici, pour ne pas invalider celui de Claude Code.
///
/// Tout échec (pas de jeton, jeton expiré, hors-ligne) rend `nil` : l'app retombe alors sur
/// la référence personnelle calculée depuis les transcripts.
actor QuotaLoader {

    private var cache: (limits: [QuotaLimit], at: Date)?

    func fetch() async -> [QuotaLimit]? {
        // Le premier plan (claude.ai) se met à jour à la minute : inutile d'interroger plus
        // souvent, même quand l'utilisateur enchaîne les rafraîchissements manuels.
        if let cache, Date().timeIntervalSince(cache.at) < 30 { return cache.limits }

        guard let token = Self.accessToken(),
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLimits = root["limits"] as? [[String: Any]] else { return nil }

        let limits: [QuotaLimit] = rawLimits.compactMap { raw in
            guard let kind = raw["kind"] as? String,
                  let percent = raw["percent"] as? NSNumber,
                  let stamp = raw["resets_at"] as? String,
                  let resetsAt = Self.date(from: stamp) else { return nil }

            let scope = raw["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            return QuotaLimit(
                kind: kind,
                percent: percent.doubleValue / 100,
                resetsAt: resetsAt,
                scopeName: model?["display_name"] as? String
            )
        }

        guard !limits.isEmpty else { return nil }
        cache = (limits, Date())
        return limits
    }

    // MARK: - Jeton

    /// Jeton d'accès de Claude Code. Trousseau d'abord (macOS), fichier ensuite (autres installs).
    /// Le premier accès au trousseau déclenche la demande d'autorisation système habituelle.
    private static func accessToken() -> String? {
        var data: Data?

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess {
            data = item as? Data
        } else {
            let file = ClaudeHome.configDirectory.appendingPathComponent(".credentials.json")
            data = try? Data(contentsOf: file)
        }

        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// `resets_at` porte des fractions de seconde à 6 chiffres, que `ISO8601DateFormatter`
    /// refuse : la fraction est retirée avant parsing, la précision à la seconde suffit.
    private static func date(from raw: String) -> Date? {
        let cleaned = raw.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: cleaned)
    }
}
