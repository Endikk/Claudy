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

/// Claudy's own token store, as the account client uses it. Injected so tests never reach the
/// real keychain.
struct OwnTokenStore {
    var load: () -> OAuthCredentials?
    var persist: (OAuthCredentials) -> Bool
    var erase: () -> Void

    static let keychain = OwnTokenStore(load: ClaudeCredentialsStore.load,
                                        persist: ClaudeCredentialsStore.persist,
                                        erase: ClaudeCredentialsStore.erase)
}

/// Claudy's own token store: the keychain item its OAuth sign-in creates, and nothing else.
///
/// Claude Code's `<config>/.credentials.json` is not a store of Claudy's. It is borrowed read-only
/// by `ClaudeCodeCredentials`, refresh token dropped: refreshing it from here would rotate Claude
/// Code's refresh token and sign Claude Code out. Claude Code's keychain item is never read
/// through `SecItemCopyMatching` either; that is what used to raise "Claudy wants to use your
/// confidential information".
enum ClaudeCredentialsStore {

    private static let ownService = "Claudy-credentials"

    static func load() -> OAuthCredentials? {
        keychainData().flatMap { parse($0, source: .ownKeychain) }
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

    /// Writes the token back to Claudy's keychain item. Rewriting Claude Code's store would steal
    /// its session, so it is refused outright.
    @discardableResult
    static func persist(_ credentials: OAuthCredentials) -> Bool {
        guard !credentials.isBorrowed,
              let data = try? JSONSerialization.data(withJSONObject: credentials.root) else { return false }
        return keychainWrite(data)
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
