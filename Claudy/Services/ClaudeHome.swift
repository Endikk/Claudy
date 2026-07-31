import Foundation

/// Emplacement des données Claude Code sur la machine courante.
/// Rien n'est codé en dur : tout se déduit de l'environnement de l'utilisateur qui lance l'app.
enum ClaudeHome {

    /// Répertoire personnalisé par `CLAUDE_CONFIG_DIR`, s'il est défini.
    private static var customDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !path.isEmpty else { return nil }
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
