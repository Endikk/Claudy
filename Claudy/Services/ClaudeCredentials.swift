import Foundation
import Security

/// An OAuth token together with the store it came from, so it can be written back to exactly
/// the same place.
struct OAuthCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    /// The store's full document, rewritten as is; only the `claudeAiOauth` token fields change.
    var root: [String: Any]
    var source: Source

    enum Source: Equatable {
        /// Keychain item created by Claudy ("Claudy-credentials"): owned by the app, so **no
        /// macOS dialog**, on read or on write.
        case ownKeychain
        case file(URL)
        /// Claude Code's token, read but never written back — Claude Code renews it. No
        /// `refresh_token` is retained for this source.
        case claudeCode
    }

    /// True when the token belongs to Claude Code: Claudy must neither refresh, persist, nor
    /// delete it.
    var isBorrowed: Bool { source == .claudeCode }

    /// Scopes actually attached to the token. They must be sent back unchanged on refresh: a
    /// renewed token without `user:profile` stops granting access to the quotas.
    var scopes: [String]? {
        let oauth = root["claudeAiOauth"] as? [String: Any]
        guard let scopes = oauth?["scopes"] as? [String], !scopes.isEmpty else { return nil }
        return scopes
    }

    /// "pro", "max", "enterprise": what Claude Code recorded when it signed in.
    var subscriptionType: String? {
        (root["claudeAiOauth"] as? [String: Any])?["subscriptionType"] as? String
    }
}

/// Claudy's own token store.
///
/// Read order: **Claudy's** keychain item first (created by its OAuth sign-in), then
/// `<config>/.credentials.json` for installs without a keychain — a plain file read, no dialog.
/// Claude Code's keychain item is never read through `SecItemCopyMatching`; that is what used to
/// raise "Claudy wants to use your confidential information". Borrowing it is
/// `ClaudeCodeCredentials`' job, through `/usr/bin/security`.
enum ClaudeCredentialsStore {

    private static let ownService = "Claudy-credentials"

    private static var credentialsFile: URL {
        ClaudeHome.configDirectory.appendingPathComponent(".credentials.json")
    }

    /// Claude Code may be writing the file at that very moment, so a few spaced attempts avoid
    /// wrongly concluding "token missing or corrupt".
    static func load() async -> OAuthCredentials? {
        if let data = keychainData() {
            return parse(data, source: .ownKeychain)
        }
        let file = credentialsFile
        for attempt in 0..<5 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 40_000_000) }
            if let data = try? Data(contentsOf: file),
               let credentials = parse(data, source: .file(file)) {
                return credentials
            }
        }
        return nil
    }

    private static func parse(_ data: Data, source: OAuthCredentials.Source) -> OAuthCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }

        let expiresAt = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }

        return OAuthCredentials(
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: expiresAt,
            root: root,
            source: source
        )
    }

    /// True when `persist` stands a chance. To be checked **before** refreshing a token: rotating
    /// a refresh token we cannot write back would invalidate the session.
    static func canPersist(_ credentials: OAuthCredentials) -> Bool {
        switch credentials.source {
        case .claudeCode:
            return false
        case .ownKeychain:
            return true
        case .file(let url):
            return FileManager.default.isWritableFile(atPath: url.path)
        }
    }

    /// Writes the token back to its own store. Rewriting Claude Code's store would steal its
    /// session, so it is refused outright; the file path writes atomically, through a temporary
    /// file, so Claude Code never reads half-written JSON.
    @discardableResult
    static func persist(_ credentials: OAuthCredentials) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: credentials.root) else { return false }

        switch credentials.source {
        case .claudeCode:
            return false
        case .ownKeychain:
            return keychainWrite(data)
        case .file(let url):
            let tmp = url.deletingLastPathComponent()
                .appendingPathComponent(".credentials.json.tmp-\(ProcessInfo.processInfo.processIdentifier)")
            do {
                try data.write(to: tmp)
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
                return true
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                return false
            }
        }
    }

    /// Sign-out: removes Claudy's item. Claude Code's stores are never touched.
    static func erase() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func keychainWrite(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
        ]
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "Claudy: Claude token"
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
