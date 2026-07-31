import Foundation

/// Lit le compte connecté dans `.claude.json` (bloc `oauthAccount`).
/// Aucune valeur n'est codée en dur : sur une machine inconnue, l'app affiche le compte de
/// *cette* machine, et à défaut le nom complet de la session macOS.
enum AccountLoader {

    static func load() -> Account {
        guard let url = ClaudeHome.configFile,
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["oauthAccount"] as? [String: Any] else {
            return fallback()
        }

        let name = (oauth["displayName"] as? String)?.trimmed ?? ""
        let role = (oauth["organizationRole"] as? String) ?? ""

        return Account(
            name: name.isEmpty ? systemName : name,
            email: (oauth["emailAddress"] as? String)?.trimmed ?? "",
            plan: plan(from: oauth),
            organization: (oauth["organizationName"] as? String)?.trimmed ?? "",
            isAdmin: role.lowercased().contains("admin")
        )
    }

    static func fallback() -> Account {
        Account(name: systemName, email: "", plan: "", organization: "", isAdmin: false)
    }

    /// `NSFullUserName()` renvoie le nom complet du compte macOS ; `NSUserName()` sert de filet.
    private static var systemName: String {
        let full = NSFullUserName().trimmed
        return full.isEmpty ? NSUserName() : full
    }

    /// « default_claude_max_5x » → « Max 5× », « claude_pro » → « Pro ».
    /// Transformation générique : aucun palier n'est énuméré, donc les futurs paliers passent aussi.
    private static func plan(from oauth: [String: Any]) -> String {
        let raw = (oauth["organizationRateLimitTier"] as? String)
            ?? (oauth["userRateLimitTier"] as? String)
            ?? (oauth["seatTier"] as? String)
            ?? (oauth["organizationType"] as? String)
            ?? ""

        let words = raw
            .replacingOccurrences(of: "default_", with: "")
            .replacingOccurrences(of: "claude_", with: "")
            .split(separator: "_")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "" }

        return words.map { word -> String in
            // « 5x » → « 5× »
            if word.count <= 3, word.hasSuffix("x"), Int(word.dropLast()) != nil {
                return word.dropLast() + "×"
            }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
