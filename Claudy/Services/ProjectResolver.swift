import Foundation

/// Maps a working directory to the project it belongs to.
///
/// Claude Code records the directory the model was *in*, which moves with every `cd`: one session
/// in a monorepo shows up as `App`, `bridge`, `src`… Grouping by that last component split one
/// project into many rows and merged unrelated folders that happen to share a name. The project
/// is the repository instead: the nearest ancestor holding `.git`, with worktrees folded back
/// into their main checkout.
struct ProjectResolver {

    /// Stops the upward walk: a dotfiles repository at the home root would otherwise swallow
    /// every folder that is not itself a repository.
    private let ceilings: Set<String>
    private let fileManager = FileManager.default
    private var cache: [String: String?] = [:]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        ceilings = ["/", "", home.standardizedFileURL.path]
    }

    /// Repository root holding `cwd`, or nil outside any repository: a scratch directory, a
    /// deleted temporary folder, or a plain folder never put under Git.
    mutating func repositoryRoot(of cwd: String) -> String? {
        if let cached = cache[cwd] { return cached }
        guard cwd.hasPrefix("/") else { return nil }

        var path = URL(fileURLWithPath: cwd).standardizedFileURL.path
        var found: String?
        while !ceilings.contains(path) {
            let marker = (path as NSString).appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: marker, isDirectory: &isDirectory) {
                found = isDirectory.boolValue ? path : mainCheckout(ofWorktreeMarker: marker) ?? path
                break
            }
            path = (path as NSString).deletingLastPathComponent
        }
        cache[cwd] = found
        return found
    }

    /// A linked worktree's `.git` is a file reading `gitdir: <main>/.git/worktrees/<name>`. Its
    /// work belongs to the main project. A submodule's points into `.git/modules/` instead and
    /// stays a project of its own.
    private func mainCheckout(ofWorktreeMarker marker: String) -> String? {
        guard let contents = try? String(contentsOfFile: marker, encoding: .utf8),
              let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }

        let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard let range = gitdir.range(of: "/.git/worktrees/") else { return nil }
        let root = String(gitdir[..<range.lowerBound])
        return root.hasPrefix("/") ? root : nil
    }
}
