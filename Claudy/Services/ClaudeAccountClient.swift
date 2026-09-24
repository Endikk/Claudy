import Foundation

/// Account identity as reported by Anthropic's OAuth API.
struct OAuthProfile {
    let name: String
    let email: String
    let plan: String
    let organization: String
}

/// Client for Anthropic's OAuth endpoints — the same ones behind claude.ai ▸ Usage and `/usage`.
///
/// Percentages come from here alone; local transcripts only ever supply the token detail, never
/// merged with a quota into one figure. Tokens are tried in order of dependability: Claude Code's,
/// borrowed read-only, which it renews itself and Claudy therefore never has to refresh; then
/// Claudy's own, for machines where that one cannot be read. A failure resets nothing — the last
/// known reading is served again, marked stale, and attempts space out.
actor ClaudeAccountClient {

    struct Payload {
        let reading: QuotaReading?
        let profile: OAuthProfile?
        /// True when a token is available, borrowed or Claudy's own.
        let isSignedIn: Bool
        /// The user signed Claudy out: nothing is to be shown, not even what Claude Code relays
        /// through its status line. Carried here so it is read with the reading, in one call.
        var isSignedOutByUser = false

        static var signedOut: Payload {
            Payload(reading: nil, profile: nil, isSignedIn: false, isSignedOutByUser: true)
        }
    }

    /// Shared instance: the data source and the view model's sign-in/sign-out actions must talk
    /// to the same state.
    static let shared = ClaudeAccountClient()

    /// Claude Code's public OAuth client — the one the token was issued to.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// Scopes Claude Code 2.1 carries through a refresh. `user:profile` is essential: without it
    /// the API returns no quota at all ("missing profile scope").
    static let scopes = [
        "user:profile", "user:inference", "user:sessions:claude_code",
        "user:mcp_servers", "user:file_upload",
    ]

    /// Scopes requested at authorisation: Claude Code adds `org:create_api_key`. Asking for the
    /// exact same set keeps Anthropic from treating Claudy's request differently.
    static let authorizeScopes = ["org:create_api_key"] + scopes

    /// Claude Code 2.1's canonical entry point. It currently redirects (307) to
    /// `claude.ai/oauth/authorize`; going through it follows the redirect Anthropic maintains
    /// rather than hardcoding today's destination.
    static let authorizeURL = URL(string: "https://claude.com/cai/oauth/authorize")!

    /// Claude Code 2.1's production token host. `console.anthropic.com`, used until now, no
    /// longer serves tokens — which is why every refresh failed.
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let manualRedirectURL = "https://platform.claude.com/oauth/code/callback"

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    /// claude.ai updates by the minute, so polling faster gains nothing and invites 429s.
    private static let cacheTTL: TimeInterval = 60
    /// Rate limit or refused token: patience is the only useful answer.
    private static let backoffSteps: [TimeInterval] = [300, 900, 1800, 3600]
    /// Network or server fault: retry soon, since it can clear at any second.
    private static let transientSteps: [TimeInterval] = [30, 60, 120, 300]
    /// The profile (name, plan) only moves when a subscription changes. Re-reading it every cycle
    /// would double the request count for nothing — and that is what fed the 429s.
    private static let profileTTL: TimeInterval = 6 * 3600

    private var credentials: OAuthCredentials?
    private var lastReading: QuotaReading?
    private var lastProfile: OAuthProfile?
    private var profileFetchedAt: Date?
    private var lastSuccess: Date?
    private var failureCount = 0
    private var nextAttempt = Date.distantPast
    private var lastManualRetry: Date?
    /// Set by a manual retry: the next reading skips the cache. `lastSuccess` stays, since it is
    /// what lets a failed retry fall back to the last reading instead of "—".
    private var skipsCache = false
    /// Claudy's own token declared dead (`invalid_grant`): it is no longer attempted, and the
    /// borrowed token takes over until an explicit new sign-in.
    private var ownTokenIsDead = false

    /// Set by "Sign out", cleared by signing back in. Persisted, so a relaunch keeps Claudy signed
    /// out whatever Claude Code does meanwhile.
    static let signedOutKey = "claudy.signedOut"

    private let store: UserDefaults
    /// Claude Code's token, read-only, and Claudy's own keychain item. Injected so tests never
    /// reach the real keychain.
    private let borrowedToken: () -> OAuthCredentials?
    private let ownToken: OwnTokenStore

    /// Bumped by every sign-in and sign-out. The actor is reentrant, so a reading or a token
    /// refresh can still be waiting on the network when the session changes: whatever it brings
    /// back then belongs to the previous session and is dropped, never written back. Without
    /// this, a refresh landing after a sign-out would put a live token back in the keychain.
    private var generation = 0

    init(store: UserDefaults = .standard,
         borrowedToken: @escaping () -> OAuthCredentials? = ClaudeCodeCredentials.load,
         ownToken: OwnTokenStore = .keychain) {
        self.store = store
        self.borrowedToken = borrowedToken
        self.ownToken = ownToken
    }

    /// True after "Sign out": no token is read, not even Claude Code's, until the user signs back
    /// in. Without it the borrowed token would take over at the next reading and the sign-out
    /// would undo itself.
    var isSignedOutByUser: Bool { store.bool(forKey: Self.signedOutKey) }

    /// Current reading, from cache, from the network, or from the last known state.
    func fetch() async -> Payload {
        guard !isSignedOutByUser else { return .signedOut }
        let payload = await read()
        // The actor is reentrant: a sign-out landing while a request was in flight wins over that
        // request's answer.
        return isSignedOutByUser ? .signedOut : payload
    }

    private func read() async -> Payload {
        let now = Date()
        let started = generation

        if !skipsCache, let lastSuccess, now.timeIntervalSince(lastSuccess) < Self.cacheTTL, lastReading != nil {
            return Payload(reading: lastReading, profile: lastProfile, isSignedIn: true)
        }
        guard now >= nextAttempt else { return stalePayload() }
        skipsCache = false

        await resolveCredentials(started)
        guard started == generation else { return stalePayload() }

        // An unreadable token must not wipe a valid reading; onboarding returns only if we
        // never had one.
        guard let credentials, !credentials.accessToken.isEmpty else { return stalePayload() }

        var (data, status, retryAfter) = await get(Self.usageURL, token: credentials.accessToken)
        guard started == generation else { return stalePayload() }
        if status == 401, await recoverFromUnauthorized(started), let token = self.credentials?.accessToken {
            (data, status, retryAfter) = await get(Self.usageURL, token: token)
            guard started == generation else { return stalePayload() }
        }
        guard status == 200, let data, let reading = Self.parseUsage(data) else {
            let reason = status == 200 ? "usage HTTP 200 without any quota in the payload"
                                       : "usage HTTP \(status)"
            return recordFailure(reason, status: status, retryAfter: retryAfter)
        }

        let profileIsStale = profileFetchedAt.map { now.timeIntervalSince($0) > Self.profileTTL } ?? true
        if profileIsStale, let token = self.credentials?.accessToken {
            let (profileData, profileStatus, _) = await get(Self.profileURL, token: token)
            guard started == generation else { return stalePayload() }
            if profileStatus == 200, let profileData,
               let profile = Self.parseProfile(profileData, subscription: self.credentials?.subscriptionType) {
                lastProfile = profile
                profileFetchedAt = now
            }
        }

        lastReading = reading
        lastSuccess = now
        failureCount = 0
        nextAttempt = .distantPast
        return Payload(reading: reading, profile: lastProfile, isSignedIn: true)
    }

    /// Last known reading, stripped of whatever stopped being true: a window past its reset time
    /// reopened at zero since, so its old percentage would be wrong rather than merely old.
    private func stalePayload() -> Payload {
        guard let lastReading, let lastSuccess else {
            return Payload(reading: nil, profile: lastProfile, isSignedIn: credentials != nil)
        }

        let now = Date()
        let stillValid: (QuotaWindow?) -> QuotaWindow? = { window in
            guard let window, let resetsAt = window.resetsAt else { return nil }
            return resetsAt > now ? window : nil
        }
        var stale = QuotaReading(
            session: stillValid(lastReading.session),
            weekly: stillValid(lastReading.weekly),
            scoped: stillValid(lastReading.scoped),
            spend: lastReading.spend.flatMap { $0.resetsAt > now ? $0 : nil },
            source: .stale(lastSuccess)
        )
        if stale.isEmpty { stale.source = .unavailable }

        return Payload(reading: stale.isEmpty ? nil : stale,
                       profile: lastProfile,
                       isSignedIn: credentials != nil || lastProfile != nil)
    }

    /// Spaces attempts by the *nature* of the fault rather than by their count alone. A rate limit
    /// calls for patience; a dropped connection does not — punishing a blinking Wi-Fi with five
    /// frozen minutes would stall the counter long after the network came back.
    private func recordFailure(_ reason: String, status: Int, retryAfter: TimeInterval?) -> Payload {
        failureCount += 1
        let steps = Self.isTransient(status) ? Self.transientSteps : Self.backoffSteps
        let step = steps[min(failureCount - 1, steps.count - 1)]
        let delay = max(retryAfter ?? 0, step)
        nextAttempt = Date().addingTimeInterval(delay)
        DiagnosticLog.append("\(reason) — failure #\(failureCount), next attempt in \(Int(delay))s")
        return stalePayload()
    }

    /// Passing fault: unreachable network (`0`) or server incident (`5xx`). Nothing of our doing,
    /// and nothing that gains from a long wait.
    private static func isTransient(_ status: Int) -> Bool {
        status == 0 || (500...599).contains(status)
    }

    /// A manual retry lifts the server's backoff once a minute at most: holding ⌘R repeats the
    /// key, and each repeat would otherwise send a request. Same span as the cache.
    static let manualRetrySpacing: TimeInterval = cacheTTL

    /// Immediate retry requested by the user: a click on "refresh" must attempt something, even
    /// in the middle of an hour-long backoff. False when the last one is under a minute old.
    @discardableResult
    func resetBackoff(now: Date = Date()) -> Bool {
        if let lastManualRetry, now.timeIntervalSince(lastManualRetry) < Self.manualRetrySpacing { return false }
        lastManualRetry = now
        failureCount = 0
        nextAttempt = .distantPast
        skipsCache = true
        return true
    }

    /// Stores the tokens obtained through Claudy's own OAuth flow in its own keychain item.
    func signIn(_ newCredentials: OAuthCredentials) {
        store.removeObject(forKey: Self.signedOutKey)
        startSession(with: newCredentials)
        ownToken.persist(newCredentials)
    }

    /// Signing back in while Claude Code holds a live session: borrowing it again is enough, no
    /// browser needed. False when Claude Code has none, and the browser sign-in has to run.
    func resumeWithClaudeCode() -> Bool {
        guard let borrowed = borrowedToken(), !Self.isExpired(borrowed) else { return false }
        store.removeObject(forKey: Self.signedOutKey)
        startSession(with: borrowed)
        DiagnosticLog.append("signed back in: borrowing Claude Code's token")
        return true
    }

    /// Erases Claudy's own token and stops borrowing Claude Code's until the user signs back in.
    /// Claude Code's stores are never touched: the CLI stays signed in.
    func signOut() {
        store.set(true, forKey: Self.signedOutKey)
        ownToken.erase()
        startSession(with: nil)
        DiagnosticLog.append("signed out: Claudy token removed, Claude Code's no longer read")
    }

    /// A new session keeps nothing of the previous one: no reading, no profile, since the account
    /// may differ, and no schedule. Work still in flight for the old one is dropped on arrival.
    private func startSession(with newCredentials: OAuthCredentials?) {
        generation += 1
        credentials = newCredentials
        lastReading = nil
        lastProfile = nil
        profileFetchedAt = nil
        ownTokenIsDead = false
        resetSchedule()
    }

    private func resetSchedule() {
        lastSuccess = nil
        failureCount = 0
        nextAttempt = .distantPast
    }

    /// Authenticated GET. Without `anthropic-beta: oauth-2025-04-20` the API refuses OAuth tokens.
    private func get(_ url: URL, token: String) async -> (Data?, Int, TimeInterval?) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return (nil, 0, nil) }
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return (data, http.statusCode, retryAfter)
    }

    /// Picks the token to use, borrowed first. A still-valid borrowed token is kept as is, since
    /// re-reading the keychain every three minutes would spawn a `security` process for nothing.
    /// Expired, it is still tried last: only the server decides, and better that than announcing
    /// "signed out" on the strength of a local date.
    private func resolveCredentials(_ started: Int) async {
        if let current = credentials, current.isBorrowed, !Self.isExpired(current) { return }

        let borrowed = borrowedToken()
        if let borrowed, !Self.isExpired(borrowed) {
            credentials = borrowed
            return
        }

        if !ownTokenIsDead, let own = ownToken.load() {
            guard started == generation else { return }
            credentials = own
            if !Self.isExpired(own) { return }
            if await refreshOwnToken(force: false, started: started) { return }
        }

        guard started == generation else { return }
        if let borrowed { credentials = borrowed }
    }

    /// Two-minute margin: a token expiring mid-request would produce an avoidable 401.
    private static func isExpired(_ credentials: OAuthCredentials) -> Bool {
        guard let expiresAt = credentials.expiresAt else { return false }
        return expiresAt < Date().addingTimeInterval(120)
    }

    /// Response to a 401. On a borrowed token there is nothing to refresh: Claude Code may have
    /// written a new one meanwhile, so a re-read is enough — and it is all Claudy allows itself.
    private func recoverFromUnauthorized(_ started: Int) async -> Bool {
        guard let current = credentials else { return false }

        if current.isBorrowed {
            guard let fresh = borrowedToken(),
                  fresh.accessToken != current.accessToken else {
                DiagnosticLog.append("usage HTTP 401 on borrowed token — Claude Code must sign in again")
                return false
            }
            credentials = fresh
            return true
        }

        DiagnosticLog.append("usage HTTP 401 — forcing refresh")
        return await refreshOwnToken(force: true, started: started)
    }

    /// Refreshes **Claudy's own** token. The store is re-read first: a previous pass may have done
    /// it already, in which case spending our refresh token would be both useless and destructive
    /// (rotation).
    private func refreshOwnToken(force: Bool, started: Int) async -> Bool {
        if let fresh = ownToken.load() {
            guard started == generation else { return false }
            let tokenChanged = fresh.accessToken != credentials?.accessToken
            credentials = fresh
            if tokenChanged { return true }
            if !force, !Self.isExpired(fresh) { return true }
        }

        guard let current = credentials, !current.isBorrowed,
              let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            DiagnosticLog.append("refresh impossible: no refresh token")
            return false
        }
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": (current.scopes ?? Self.scopes).joined(separator: " "),
        ])
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else {
            DiagnosticLog.append("refresh: network unavailable")
            return false
        }
        // Signed out (or in again) while the request was out: the new token is discarded, not
        // written back to a keychain the user just emptied.
        guard started == generation else {
            DiagnosticLog.append("refresh answer dropped: the session changed meanwhile")
            return false
        }
        guard status == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = root["access_token"] as? String, !newToken.isEmpty else {
            if Self.isInvalidGrant(status: status, data: data) {
                ownTokenIsDead = true
                DiagnosticLog.append("refresh invalid_grant — Claudy token dropped, borrowing from Claude Code")
            } else {
                DiagnosticLog.append("refresh HTTP \(status)")
            }
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

        let persisted = ownToken.persist(updated)
        DiagnosticLog.append(persisted ? "refresh OK, store rewritten"
                                       : "refresh OK but persistence FAILED — check the keychain")
        credentials = updated
        return true
    }

    /// `invalid_grant` means the refresh token was revoked or already rotated: it will not come
    /// back, so it is declared dead once and for all rather than retried in a loop.
    private static func isInvalidGrant(status: Int, data: Data) -> Bool {
        guard status == 400 || status == 401,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let error = root["error"] as? String { return error == "invalid_grant" }
        if let error = root["error"] as? [String: Any], let type = error["type"] as? String {
            return type == "invalid_grant"
        }
        return false
    }

    /// Reads `/api/oauth/usage`. Two representations coexist in one payload: the top-level fields
    /// (`utilization`, 0-100) that `/usage` reads, and `limits[]`, the only place naming the model
    /// of the per-model window. The former leads, the latter completes. A payload with neither
    /// window belongs to a usage-billed plan, whose only quota is its monthly spend cap.
    static func parseUsage(_ data: Data, now: Date = Date()) -> QuotaReading? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var reading = QuotaReading(session: nil, weekly: nil, scoped: nil, source: .api)
        reading.session = window(root["five_hour"])
        reading.weekly = window(root["seven_day"])

        let scoped = [
            ("seven_day_opus", "Opus"),
            ("seven_day_sonnet", "Sonnet"),
            ("seven_day_oauth_apps", "OAuth apps"),
        ]
        for (key, name) in scoped {
            guard let candidate = window(root[key], label: name) else { continue }
            if candidate.percent > (reading.scoped?.percent ?? -1) { reading.scoped = candidate }
        }

        if let limits = root["limits"] as? [[String: Any]] {
            for raw in limits {
                guard let kind = raw["kind"] as? String,
                      let percent = raw["percent"] as? NSNumber else { continue }
                let resetsAt = (raw["resets_at"] as? String).flatMap(date(from:))
                let scope = raw["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                let candidate = QuotaWindow(percent: percent.doubleValue / 100,
                                            resetsAt: resetsAt,
                                            label: model?["display_name"] as? String)
                switch kind {
                case "session": reading.session = reading.session ?? candidate
                case "weekly_all": reading.weekly = reading.weekly ?? candidate
                case "weekly_scoped":
                    if candidate.label != nil || reading.scoped == nil { reading.scoped = candidate }
                default: break
                }
            }
        }

        if reading.session == nil, reading.weekly == nil {
            reading.spend = spend(root, now: now)
        }

        return reading.isEmpty ? nil : reading
    }

    /// Enterprise plans are billed on usage: `five_hour` and `seven_day` come back null and the
    /// meter is `spend`, each amount in minor units with its exponent (4631 at exponent 2 is
    /// $46.31). `extra_usage`, the older shape of the same budget, is the fallback. Pro and Max
    /// carry these blocks too, as their extra-usage cap, which is why only a payload without
    /// windows is read here.
    private static func spend(_ root: [String: Any], now: Date) -> SpendReading? {
        let extra = root["extra_usage"] as? [String: Any]
        let reached = (extra?["spend_limit_reached"] as? Bool) ?? false
        let resetsAt = SpendReading.periodEnd(after: now)

        if let block = root["spend"] as? [String: Any], (block["enabled"] as? Bool) != false,
           let used = amount(block["used"]), let limit = amount(block["limit"]), limit.value > 0 {
            return SpendReading(used: used.value, limit: limit.value, currency: limit.currency,
                                isLimitReached: reached, resetsAt: resetsAt)
        }

        guard let extra, (extra["is_enabled"] as? Bool) == true,
              let usedMinor = extra["used_credits"] as? NSNumber,
              let limitMinor = extra["monthly_limit"] as? NSNumber, limitMinor.doubleValue > 0 else {
            return nil
        }
        let scale = pow(10, (extra["decimal_places"] as? NSNumber)?.doubleValue ?? 2)
        return SpendReading(used: usedMinor.doubleValue / scale, limit: limitMinor.doubleValue / scale,
                            currency: (extra["currency"] as? String) ?? "USD",
                            isLimitReached: reached, resetsAt: resetsAt)
    }

    /// `{ "amount_minor": 4631, "currency": "USD", "exponent": 2 }` → 46.31 USD.
    private static func amount(_ raw: Any?) -> (value: Double, currency: String)? {
        guard let object = raw as? [String: Any],
              let minor = object["amount_minor"] as? NSNumber else { return nil }
        let exponent = (object["exponent"] as? NSNumber)?.doubleValue ?? 2
        return (minor.doubleValue / pow(10, exponent), (object["currency"] as? String) ?? "USD")
    }

    /// One top-level block: `{ "utilization": 59.0, "resets_at": "…" }`, `null` when inapplicable.
    private static func window(_ raw: Any?, label: String? = nil) -> QuotaWindow? {
        guard let object = raw as? [String: Any],
              let utilization = object["utilization"] as? NSNumber else { return nil }
        let resetsAt = (object["resets_at"] as? String).flatMap(date(from:))
        return QuotaWindow(percent: utilization.doubleValue / 100, resetsAt: resetsAt, label: label)
    }

    /// `subscription` is the token's own `subscriptionType` ("enterprise"), kept as the last
    /// candidate: the organisation's tier says more on every plan but Enterprise.
    private static func parseProfile(_ data: Data, subscription: String?) -> OAuthProfile? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["account"] as? [String: Any] else { return nil }

        let organization = root["organization"] as? [String: Any]
        let name = (account["full_name"] as? String)
            ?? (account["display_name"] as? String) ?? ""
        guard !name.isEmpty else { return nil }

        let plan = AccountLoader.planLabel(candidates: [
            organization?["rate_limit_tier"] as? String,
            organization?["seat_tier"] as? String,
            organization?["organization_type"] as? String,
            subscription,
        ])

        return OAuthProfile(
            name: name,
            email: (account["email"] as? String) ?? "",
            plan: plan,
            organization: (organization?["name"] as? String) ?? ""
        )
    }

    /// `resets_at` carries six-digit fractional seconds, which `ISO8601DateFormatter` rejects;
    /// the fraction is stripped before parsing, second precision being ample.
    static func date(from raw: String) -> Date? {
        let cleaned = raw.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: cleaned)
    }
}

/// Timestamped log of API failures at `~/Library/Application Support/Claudy/api.log`. It is what
/// separates a rate limit (repeated 429s) from a dead token (401 plus failed refresh).
enum DiagnosticLog {

    /// `Application Support/Claudy/api.log`. Under XCTest, the tests and the test host write to a
    /// temporary copy instead: a stubbed server's failures must never read as incidents in the
    /// user's own log.
    static let file: URL? = {
        guard let directory = directory(environment: ProcessInfo.processInfo.environment) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("api.log")
    }()

    /// `CLAUDY_LOG_DIRECTORY` wins: the pre-release checks launch the real app against a stand-in
    /// Claude folder and keep what it logs apart.
    static func directory(environment: [String: String]) -> URL? {
        if let custom = environment["CLAUDY_LOG_DIRECTORY"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let isTestRun = environment["XCTestConfigurationFilePath"] != nil
        let base = isTestRun
            ? FileManager.default.temporaryDirectory
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("Claudy", isDirectory: true)
    }

    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Appends one line. The log is bounded: past 512 KB it restarts rather than growing forever.
    static func append(_ message: String) {
        NSLog("[Claudy] %@", message)
        guard let file else { return }

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
