import CryptoKit
import Foundation

/// **Read-only** access to Claude Code's OAuth token — the most dependable source Claudy has,
/// since Claude Code renews it itself and no `refresh_token` is ever read or spent here.
///
/// No macOS prompt appears because the keychain item was created by `/usr/bin/security`, so its
/// ACL trusts that binary alone; going through the same executable rather than
/// `SecItemCopyMatching` is exactly the path Claude Code takes on every start.
enum ClaudeCodeCredentials {

    /// Characters accepted in a keychain account name; beyond them Claude Code falls back to a
    /// fixed identifier, and we must make the same choice to target the same item.
    private static let safeAccount = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._@-")
    private static let fallbackAccount = "claude-code-user"
    private static let readTimeout: TimeInterval = 3

    /// Claude Code's current token, or `nil` when the tool is absent or signed out.
    static func load() -> OAuthCredentials? {
        if let data = keychainData(), let credentials = parse(data) { return credentials }
        if let data = try? Data(contentsOf: credentialsFile), let credentials = parse(data) {
            return credentials
        }
        return nil
    }

    private static var credentialsFile: URL {
        ClaudeHome.configDirectory.appendingPathComponent(".credentials.json")
    }

    /// `Claude Code-credentials`, suffixed with the first eight characters of the configuration
    /// directory's SHA-256 when that directory is custom — Claude Code's exact rule, without
    /// which a machine using `CLAUDE_CONFIG_DIR` would target the wrong item.
    private static var service: String {
        let base = "Claude Code-credentials"
        guard let custom = ClaudeHome.customConfigDirectory else { return base }
        let normalized = custom.path.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(base)-\(hex.prefix(8))"
    }

    private static var account: String {
        let candidate = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        guard !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy(safeAccount.contains) else {
            return fallbackAccount
        }
        return candidate
    }

    /// Reads the item through `security`. A refused read would open a dialog and block forever,
    /// so past the timeout this source is abandoned rather than freezing the refresh.
    private static func keychainData() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-a", account, "-w", "-s", service]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            DiagnosticLog.append("Claude Code keychain: could not launch security")
            return nil
        }

        let deadline = Date().addingTimeInterval(readTimeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !process.isRunning else {
            process.terminate()
            DiagnosticLog.append("Claude Code keychain: read timed out (access dialog?)")
            return nil
        }

        guard process.terminationStatus == 0,
              let data = try? output.fileHandleForReading.readToEnd(),
              !data.isEmpty else { return nil }
        return data
    }

    /// The `refresh_token` is deliberately dropped: Claudy must never be able to consume it,
    /// because rotating it would sign Claude Code out.
    private static func parse(_ data: Data) -> OAuthCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }

        let expiresAt = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }

        return OAuthCredentials(
            accessToken: token,
            refreshToken: nil,
            expiresAt: expiresAt,
            root: root,
            source: .claudeCode
        )
    }
}
