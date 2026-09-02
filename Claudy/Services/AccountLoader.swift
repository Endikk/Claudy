import Foundation

/// Reads the signed-in account from `.claude.json` (`oauthAccount` block). Nothing is hardcoded:
/// on an unknown machine the app shows *that* machine's account, falling back to the macOS
/// session's full name.
enum AccountLoader {

    /// `.claude.json` routinely reaches several megabytes, so it is only re-read when its
    /// modification date changes.
    private static var cache: (mtime: Date, account: Account)?

    static func load() -> Account {
        guard let url = ClaudeHome.configFile else { return fallback() }

        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        if let cache, let mtime, cache.mtime == mtime {
            return cache.account
        }

        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["oauthAccount"] as? [String: Any] else {
            return fallback()
        }

        let name = (oauth["displayName"] as? String)?.trimmed ?? ""
        let role = (oauth["organizationRole"] as? String) ?? ""

        let account = Account(
            name: name.isEmpty ? systemName : name,
            email: (oauth["emailAddress"] as? String)?.trimmed ?? "",
            plan: plan(from: oauth),
            organization: (oauth["organizationName"] as? String)?.trimmed ?? "",
            isAdmin: role.lowercased().contains("admin")
        )
        if let mtime { cache = (mtime, account) }
        return account
    }

    static func fallback() -> Account {
        Account(name: systemName, email: "", plan: "", organization: "", isAdmin: false)
    }

    /// `NSFullUserName()` gives the macOS account's full name; `NSUserName()` is the safety net.
    private static var systemName: String {
        let full = NSFullUserName().trimmed
        return full.isEmpty ? NSUserName() : full
    }

    private static func plan(from oauth: [String: Any]) -> String {
        planLabel(from: (oauth["organizationRateLimitTier"] as? String)
            ?? (oauth["userRateLimitTier"] as? String)
            ?? (oauth["seatTier"] as? String)
            ?? (oauth["organizationType"] as? String)
            ?? "")
    }

    /// "default_claude_max_5x" → "Max 5×", "claude_pro" → "Pro". Purely generic: no tier is
    /// enumerated, so tiers introduced later render correctly too.
    static func planLabel(from raw: String) -> String {
        let words = raw
            .replacingOccurrences(of: "default_", with: "")
            .replacingOccurrences(of: "claude_", with: "")
            .split(separator: "_")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "" }

        return words.map { word -> String in
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
