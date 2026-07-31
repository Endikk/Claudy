import Foundation
import Security

/// Jeton OAuth de Claude Code, avec son magasin d'origine — pour pouvoir le réécrire
/// exactement là où Claude Code le lira.
struct OAuthCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    /// Document complet du magasin (`mcpOAuth`, `organizationUuid`…) : réécrit tel quel,
    /// seuls les champs du jeton `claudeAiOauth` sont modifiés.
    var root: [String: Any]
    var source: Source

    enum Source: Equatable {
        case keychain
        case file(URL)
    }
}

/// Accès au magasin de jetons de Claude Code : trousseau macOS d'abord
/// (« Claude Code-credentials »), fichier `<config>/.credentials.json` sinon.
enum ClaudeCredentialsStore {

    private static let service = "Claude Code-credentials"

    private static var credentialsFile: URL {
        ClaudeHome.configDirectory.appendingPathComponent(".credentials.json")
    }

    // MARK: - Lecture

    static func load() async -> OAuthCredentials? {
        if let data = keychainData() {
            return parse(data, source: .keychain)
        }
        // Claude Code peut être en train d'écrire le fichier au même instant : quelques
        // tentatives espacées évitent de conclure à tort « jeton absent ou corrompu ».
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

    // MARK: - Écriture

    /// Vrai si `persist` a une chance d'aboutir. À vérifier **avant** de rafraîchir un jeton :
    /// une rotation de refresh token qu'on ne peut pas réécrire dans le magasin invaliderait
    /// la session de Claude Code lui-même.
    static func canPersist(_ credentials: OAuthCredentials) -> Bool {
        switch credentials.source {
        case .keychain:
            // Mise à jour à blanc (mêmes octets) : teste l'autorisation d'écriture sans rien changer.
            guard let data = keychainData() else { return false }
            return keychainUpdate(data)
        case .file(let url):
            return FileManager.default.isWritableFile(atPath: url.path)
        }
    }

    @discardableResult
    static func persist(_ credentials: OAuthCredentials) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: credentials.root) else { return false }

        switch credentials.source {
        case .keychain:
            return keychainUpdate(data)
        case .file(let url):
            // Écriture atomique : fichier temporaire puis remplacement, pour que Claude Code
            // ne lise jamais un JSON à moitié écrit.
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

    // MARK: - Trousseau

    private static func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func keychainUpdate(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
    }
}
