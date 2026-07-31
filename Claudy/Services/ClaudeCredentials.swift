import Foundation
import Security

/// Jeton OAuth, avec son magasin d'origine — pour pouvoir le réécrire exactement au même endroit.
struct OAuthCredentials {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    /// Document complet du magasin : réécrit tel quel, seuls les champs du jeton
    /// `claudeAiOauth` sont modifiés.
    var root: [String: Any]
    var source: Source

    enum Source: Equatable {
        /// Item trousseau créé par Claudy (« Claudy-credentials ») : possédé par l'app,
        /// donc **aucun dialogue macOS**, ni à la lecture ni à l'écriture.
        case ownKeychain
        case file(URL)
    }
}

/// Magasin de jetons de Claudy.
///
/// Ordre de lecture : item trousseau **de Claudy** d'abord (créé par la connexion OAuth),
/// puis `<config>/.credentials.json` (installs sans trousseau — lecture de fichier, sans
/// dialogue). L'item trousseau de *Claude Code* n'est volontairement **jamais** lu : c'est
/// lui qui déclenchait « Claudy veut utiliser vos informations confidentielles ».
enum ClaudeCredentialsStore {

    private static let ownService = "Claudy-credentials"

    private static var credentialsFile: URL {
        ClaudeHome.configDirectory.appendingPathComponent(".credentials.json")
    }

    // MARK: - Lecture

    static func load() async -> OAuthCredentials? {
        if let data = keychainData() {
            return parse(data, source: .ownKeychain)
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
    /// une rotation de refresh token qu'on ne peut pas réécrire invaliderait la session.
    static func canPersist(_ credentials: OAuthCredentials) -> Bool {
        switch credentials.source {
        case .ownKeychain:
            return true
        case .file(let url):
            return FileManager.default.isWritableFile(atPath: url.path)
        }
    }

    @discardableResult
    static func persist(_ credentials: OAuthCredentials) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: credentials.root) else { return false }

        switch credentials.source {
        case .ownKeychain:
            return keychainWrite(data)
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

    /// Déconnexion : supprime l'item de Claudy. Ne touche jamais aux magasins de Claude Code.
    static func erase() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Trousseau (item de Claudy uniquement)

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
            attributes[kSecAttrLabel as String] = "Claudy — jeton Claude"
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
