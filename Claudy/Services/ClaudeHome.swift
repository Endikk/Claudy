import Foundation

/// Where Claude Code keeps its data on the current machine. Nothing is hardcoded: everything is
/// derived from the environment of the user running the app.
enum ClaudeHome {

    /// Custom directory, when one is set. The `claudy.configDir` preference
    /// (`defaults write com.claudy.Claudy claudy.configDir <path>`) wins, because an app launched
    /// from Finder or the Dock inherits no shell variables — `CLAUDE_CONFIG_DIR` therefore only
    /// applies to terminal launches.
    static var customConfigDirectory: URL? {
        let candidates = [
            UserDefaults.standard.string(forKey: "claudy.configDir"),
            ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
        ]
        guard let path = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Configuration directory: the custom one when set, otherwise `~/.claude`.
    static var configDirectory: URL {
        customConfigDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    /// Every folder that may hold transcripts on this machine, each with one folder per project
    /// named after its working directory.
    static var projectsDirectories: [URL] {
        projectsDirectories(custom: customConfigDirectory,
                            home: FileManager.default.homeDirectoryForCurrentUser,
                            environment: ProcessInfo.processInfo.environment)
    }

    /// A custom directory stands alone. Otherwise `~/.claude/projects` comes first, then the XDG
    /// location (`$XDG_CONFIG_HOME/claude/projects`, `~/.config/claude/projects` by default) that
    /// some Claude Code releases wrote to. ccusage reads both for the same reason, and responses
    /// found in both are counted once.
    static func projectsDirectories(custom: URL?, home: URL, environment: [String: String]) -> [URL] {
        if let custom { return [custom.appendingPathComponent("projects", isDirectory: true)] }

        let xdgHome = environment["XDG_CONFIG_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath,
                                              isDirectory: true) }
            ?? home.appendingPathComponent(".config", isDirectory: true)
        return [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            xdgHome.appendingPathComponent("claude/projects", isDirectory: true),
        ]
    }

    /// `.claude.json` lives in the configuration directory when that directory is custom, and at
    /// the home root otherwise. Neither falls back to the other: redirecting `CLAUDE_CONFIG_DIR`
    /// must isolate completely, or the app would read another configuration's account.
    static var configFile: URL? {
        let candidate = customConfigDirectory?.appendingPathComponent(".claude.json")
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// True as soon as any trace of Claude Code exists; without one the app switches to demo mode.
    static var isInstalled: Bool {
        configFile != nil || projectsDirectories.contains { FileManager.default.fileExists(atPath: $0.path) }
    }
}
