import Foundation

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

/// Identité du compte, telle que rapportée par l'API OAuth d'Anthropic.
struct OAuthProfile {
    let name: String
    let email: String
    let plan: String
    let organization: String
}

/// Client des points d'accès OAuth internes d'Anthropic — les mêmes que claude.ai ▸ Utilisation.
///
/// **Invariant.** Les pourcentages des jauges viennent *uniquement* d'ici. Les transcripts
/// locaux ne servent qu'au détail en tokens (répartitions, sparkline) — jamais fusionnés
/// avec l'API en un seul chiffre.
///
/// Fiabilité, dans l'ordre :
/// 1. **Refresh autonome** : à moins de 2 min de l'expiration, le grant `refresh_token` est
///    rejoué avec le client public de Claude Code, et le magasin (trousseau ou fichier) est
///    réécrit — Claude Code récupère le jeton frais. Le refresh n'est **jamais** tenté si le
///    magasin n'est pas réinscriptible : une rotation orpheline invaliderait la session de
///    Claude Code lui-même. L'actor sérialise les refresh, et le magasin est relu après
///    acquisition pour ne pas rafraîchir deux fois.
/// 2. **Retry unique sur 401** : refresh forcé puis une seule nouvelle tentative — pas de boucle.
/// 3. **Dernière valeur connue + backoff** : un échec (typiquement 429) ne remet rien à zéro,
///    la dernière valeur est resservie et les tentatives s'espacent (60 s + 60 s × échecs,
///    plafonné à 300 s). Premier succès : retour au rythme normal.
/// 4. **Fail-soft intégral** : tout parsing douteux rend `nil`, jamais de crash si la forme
///    de la réponse change.
/// 5. **Journal** : chaque échec est horodaté dans `~/Library/Application Support/Claudy/api.log`
///    (code HTTP, refresh), pour distinguer un rate-limit d'un jeton mort.
///
/// Point de fragilité assumé : ces points d'accès ne sont pas documentés et peuvent changer
/// côté Anthropic sans préavis — d'où le repli sur la référence personnelle dans l'agrégateur.
actor ClaudeAccountClient {

    struct Payload {
        let limits: [QuotaLimit]?
        let profile: OAuthProfile?
        /// Vrai quand `limits`/`profile` datent d'un passage précédent (échecs en cours).
        let isStale: Bool
        /// Vrai quand un jeton est disponible (connexion OAuth faite ou `.credentials.json` lisible).
        let isSignedIn: Bool
    }

    /// Instance partagée : la source de données et les actions de connexion/déconnexion
    /// du ViewModel doivent parler au même état.
    static let shared = ClaudeAccountClient()

    /// Client OAuth public de Claude Code — celui au nom duquel le jeton a été émis.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    private var credentials: OAuthCredentials?
    private var lastLimits: [QuotaLimit]?
    private var lastProfile: OAuthProfile?
    private var lastSuccess: Date?
    private var failureCount = 0
    private var nextAttempt = Date.distantPast

    // MARK: - Point d'entrée

    func fetch() async -> Payload {
        let now = Date()

        // claude.ai se met à jour à la minute : inutile d'interroger plus souvent.
        if let lastSuccess, now.timeIntervalSince(lastSuccess) < 30 {
            return Payload(limits: lastLimits, profile: lastProfile, isStale: false, isSignedIn: true)
        }
        // Backoff en cours : resservir la dernière valeur connue sans toucher au réseau.
        guard now >= nextAttempt else {
            return Payload(limits: lastLimits, profile: lastProfile, isStale: true,
                           isSignedIn: credentials != nil)
        }

        await ensureFreshCredentials()
        guard let token = credentials?.accessToken else {
            // Pas de jeton = pas connecté : état normal avant la première connexion,
            // pas une panne — pas de backoff ni de journal.
            return Payload(limits: nil, profile: nil, isStale: false, isSignedIn: false)
        }

        var (data, status) = await get(Self.usageURL, token: token)
        if status == 401 {
            DiagnosticLog.append("usage HTTP 401 — refresh forcé")
            if await refreshCredentials(force: true), let fresh = credentials?.accessToken {
                (data, status) = await get(Self.usageURL, token: fresh)
            }
        }
        guard status == 200, let data, let limits = Self.parseLimits(data) else {
            return recordFailure("usage HTTP \(status)")
        }

        // Le profil est secondaire : son échec ne condamne pas les jauges.
        if let token = credentials?.accessToken {
            let (profileData, profileStatus) = await get(Self.profileURL, token: token)
            if profileStatus == 200, let profileData, let profile = Self.parseProfile(profileData) {
                lastProfile = profile
            }
        }

        lastLimits = limits
        lastSuccess = now
        failureCount = 0
        nextAttempt = .distantPast
        return Payload(limits: limits, profile: lastProfile, isStale: false, isSignedIn: true)
    }

    private func recordFailure(_ reason: String) -> Payload {
        failureCount += 1
        let delay = min(60.0 + 60.0 * Double(failureCount - 1), 300.0)
        nextAttempt = Date().addingTimeInterval(delay)
        DiagnosticLog.append("\(reason) — échec n°\(failureCount), prochaine tentative dans \(Int(delay)) s")
        return Payload(limits: lastLimits, profile: lastProfile, isStale: lastLimits != nil,
                       isSignedIn: credentials != nil)
    }

    // MARK: - Connexion / déconnexion

    /// Injecte les jetons obtenus par le flux OAuth et les persiste dans l'item de Claudy.
    func signIn(_ newCredentials: OAuthCredentials) {
        credentials = newCredentials
        ClaudeCredentialsStore.persist(newCredentials)
        lastSuccess = nil
        failureCount = 0
        nextAttempt = .distantPast
    }

    /// Oublie tout : jetons, dernières valeurs, backoff. Ne touche pas aux magasins de Claude Code.
    func signOut() {
        ClaudeCredentialsStore.erase()
        credentials = nil
        lastLimits = nil
        lastProfile = nil
        lastSuccess = nil
        failureCount = 0
        nextAttempt = .distantPast
        DiagnosticLog.append("déconnexion — jeton Claudy supprimé")
    }

    // MARK: - Requêtes

    private func get(_ url: URL, token: String) async -> (Data?, Int) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Sans `anthropic-beta: oauth-2025-04-20`, l'API refuse les jetons OAuth.
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return (nil, 0) }
        return (data, status)
    }

    // MARK: - Jeton

    private func ensureFreshCredentials() async {
        if credentials == nil {
            credentials = await ClaudeCredentialsStore.load()
        }
        guard let credentials else { return }
        if let expiresAt = credentials.expiresAt, expiresAt < Date().addingTimeInterval(120) {
            _ = await refreshCredentials(force: false)
        }
    }

    /// Rafraîchit le jeton. Relit d'abord le magasin : Claude Code (ou un passage précédent)
    /// a pu le faire entre-temps, auquel cas consommer notre refresh token serait inutile
    /// et destructeur (rotation).
    private func refreshCredentials(force: Bool) async -> Bool {
        if let fresh = await ClaudeCredentialsStore.load() {
            let tokenChanged = fresh.accessToken != credentials?.accessToken
            credentials = fresh
            if tokenChanged { return true }
            if !force, let expiresAt = fresh.expiresAt, expiresAt > Date().addingTimeInterval(120) {
                return true
            }
        }

        guard let current = credentials,
              let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            DiagnosticLog.append("refresh impossible : pas de refresh token")
            return false
        }
        guard ClaudeCredentialsStore.canPersist(current) else {
            DiagnosticLog.append("refresh refusé : magasin non réinscriptible")
            return false
        }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else {
            DiagnosticLog.append("refresh : réseau indisponible")
            return false
        }
        guard status == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = root["access_token"] as? String, !newToken.isEmpty else {
            DiagnosticLog.append("refresh HTTP \(status)")
            return false
        }

        var updated = current
        updated.accessToken = newToken
        if let newRefresh = root["refresh_token"] as? String, !newRefresh.isEmpty {
            updated.refreshToken = newRefresh
        }
        let expiresIn = (root["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        updated.expiresAt = Date().addingTimeInterval(expiresIn)

        var oauth = (updated.root["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = updated.accessToken
        if let refresh = updated.refreshToken { oauth["refreshToken"] = refresh }
        oauth["expiresAt"] = Int((updated.expiresAt ?? Date()).timeIntervalSince1970 * 1000)
        updated.root["claudeAiOauth"] = oauth

        let persisted = ClaudeCredentialsStore.persist(updated)
        DiagnosticLog.append(persisted ? "refresh OK, magasin réécrit"
                                       : "refresh OK mais persistance ÉCHOUÉE — vérifier le trousseau")
        credentials = updated
        return true
    }

    // MARK: - Parsing (fail-soft : toute forme inattendue rend nil)

    private static func parseLimits(_ data: Data) -> [QuotaLimit]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLimits = root["limits"] as? [[String: Any]] else { return nil }

        let limits: [QuotaLimit] = rawLimits.compactMap { raw in
            guard let kind = raw["kind"] as? String,
                  let percent = raw["percent"] as? NSNumber,
                  let stamp = raw["resets_at"] as? String,
                  let resetsAt = date(from: stamp) else { return nil }

            let scope = raw["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            return QuotaLimit(
                kind: kind,
                percent: percent.doubleValue / 100,
                resetsAt: resetsAt,
                scopeName: model?["display_name"] as? String
            )
        }
        return limits.isEmpty ? nil : limits
    }

    private static func parseProfile(_ data: Data) -> OAuthProfile? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["account"] as? [String: Any] else { return nil }

        let organization = root["organization"] as? [String: Any]
        let name = (account["full_name"] as? String)
            ?? (account["display_name"] as? String) ?? ""
        guard !name.isEmpty else { return nil }

        let tier = (organization?["rate_limit_tier"] as? String)
            ?? (organization?["seat_tier"] as? String)
            ?? (organization?["organization_type"] as? String)
            ?? ""

        return OAuthProfile(
            name: name,
            email: (account["email"] as? String) ?? "",
            plan: AccountLoader.planLabel(from: tier),
            organization: (organization?["name"] as? String) ?? ""
        )
    }

    /// `resets_at` porte des fractions de seconde à 6 chiffres, que `ISO8601DateFormatter`
    /// refuse : la fraction est retirée avant parsing, la précision à la seconde suffit.
    private static func date(from raw: String) -> Date? {
        let cleaned = raw.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: cleaned)
    }
}

// MARK: - Journal de diagnostic

/// Journal horodaté des échecs API : `~/Library/Application Support/Claudy/api.log`.
/// Permet de distinguer un rate-limit (429 répétés) d'un jeton mort (401 + refresh échoué).
enum DiagnosticLog {

    private static let file: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let directory = base.appendingPathComponent("Claudy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("api.log")
    }()

    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func append(_ message: String) {
        NSLog("[Claudy] %@", message)
        guard let file else { return }

        // Journal borné : au-delà de 512 Ko, on repart de zéro plutôt que de grossir sans fin.
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 512_000 {
            try? FileManager.default.removeItem(at: file)
        }

        let line = "\(stamp.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}
