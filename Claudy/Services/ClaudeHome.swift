import Foundation

/// Emplacement des données Claude Code sur la machine courante.
/// Rien n'est codé en dur : tout se déduit de l'environnement de l'utilisateur qui lance l'app.
enum ClaudeHome {

    /// Répertoire personnalisé, s'il est défini. Le réglage `claudy.configDir`
    /// (`defaults write com.claudy.Claudy claudy.configDir <chemin>`) prime : une app lancée
    /// depuis le Finder ou le Dock n'hérite pas des variables du shell, `CLAUDE_CONFIG_DIR`
    /// ne sert donc qu'aux lancements depuis un terminal.
    private static var customDirectory: URL? {
        let candidates = [
            UserDefaults.standard.string(forKey: "claudy.configDir"),
            ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
        ]
        guard let path = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Répertoire de configuration. `CLAUDE_CONFIG_DIR` prime, sinon `~/.claude`.
    static var configDirectory: URL {
        customDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    /// Un dossier par projet, nommé d'après son chemin de travail.
    static var projectsDirectory: URL {
        configDirectory.appendingPathComponent("projects", isDirectory: true)
    }

    /// `.claude.json` vit dans le répertoire de configuration quand celui-ci est personnalisé,
    /// et à la racine du dossier personnel sinon. Pas de repli de l'un vers l'autre : rediriger
    /// `CLAUDE_CONFIG_DIR` doit isoler complètement, sinon on lirait le compte d'une autre config.
    static var configFile: URL? {
        let candidate = customDirectory?.appendingPathComponent(".claude.json")
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Vrai dès qu'une trace de Claude Code existe : sans ça, l'app bascule en démonstration.
    static var isInstalled: Bool {
        configFile != nil || FileManager.default.fileExists(atPath: projectsDirectory.path)
    }
}
