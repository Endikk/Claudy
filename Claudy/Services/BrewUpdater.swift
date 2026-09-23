import Foundation
import AppKit

/// Runs a Homebrew upgrade of the Claudy cask.
protocol UpgradeRunner: Sendable {
    /// Runs the upgrade and returns its exit status. When the upgrade succeeds, brew quits this
    /// app on the way and the script relaunches the new version, so the call may never return.
    func upgrade() async -> Int32
    /// Opens the upgrade in Terminal, for the user to follow or answer brew there.
    func openInTerminal() throws
}

/// The upgrade through Homebrew, with the brew installed on this Mac.
struct BrewUpgradeRunner: UpgradeRunner {
    let brew: String

    static let bundleIdentifier = "com.claudy.Claudy"

    /// Homebrew's two standard prefixes, Apple silicon first.
    static func findBrew(fileManager: FileManager = .default) -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// The shell script. Fixed text: the variable parts are the brew path, found above among
    /// two fixed locations and quoted, and a process id. On success it reopens Claudy, but only
    /// if brew quit it: a Claudy still running restarts itself, and opening here too would
    /// launch it twice.
    ///
    /// `brew update` first: on its own, brew refreshes the tap once a day at most, and a tap
    /// that predates the release answers "the latest version is already installed" with status
    /// 0. A failed update does not stop the upgrade, which then says why in the log.
    static func script(brew: String, claudy pid: Int32) -> String {
        """
        "\(brew)" update --quiet
        "\(brew)" upgrade --cask claudy
        status=$?
        if [ "$status" -eq 0 ] && ! kill -0 \(pid) 2>/dev/null; then /usr/bin/open -b \(bundleIdentifier); fi
        exit "$status"
        """
    }

    private static var ownPID: Int32 { ProcessInfo.processInfo.processIdentifier }

    func upgrade() async -> Int32 {
        let brew = brew
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", Self.script(brew: brew, claudy: Self.ownPID)]
            var environment = ProcessInfo.processInfo.environment
            environment["HOMEBREW_NO_ENV_HINTS"] = "1"
            environment["NONINTERACTIVE"] = "1"
            process.environment = environment
            // Output goes to a log, never to a pipe: the process outlives this app when brew
            // quits it, and a pipe with no reader left would kill it.
            process.standardOutput = Self.logHandle()
            process.standardError = process.standardOutput
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }

    func openInTerminal() throws {
        let url = Self.cacheDirectory.appendingPathComponent("Update Claudy.command")
        let script = Data(("#!/bin/sh\n" + Self.script(brew: brew, claudy: Self.ownPID) + "\n").utf8)
        guard Self.createFresh(url, contents: script, permissions: 0o700) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Claudy")
    }

    /// `~/Library/Caches/Claudy/update.log`, rewritten on every attempt.
    private static func logHandle() -> FileHandle {
        let url = cacheDirectory.appendingPathComponent("update.log")
        guard createFresh(url, contents: Data(), permissions: 0o600) else { return .nullDevice }
        return (try? FileHandle(forWritingTo: url)) ?? .nullDevice
    }

    /// Replaces whatever sits at `url`, a symbolic link included (removing one never follows
    /// it), with a new file created directly with its final permissions.
    private static func createFresh(_ url: URL, contents: Data, permissions: Int) -> Bool {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: url)
        return fileManager.createFile(atPath: url.path, contents: contents,
                                      attributes: [.posixPermissions: permissions])
    }
}

#if DEBUG
/// `-ClaudySimulateUpdate`: plays the upgrade without touching the installed app. Add
/// `-ClaudySimulateUpgradeFailure YES` to see the Terminal fallback.
struct SimulatedUpgradeRunner: UpgradeRunner {
    let fails: Bool

    func upgrade() async -> Int32 {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return fails ? 1 : 0
    }

    func openInTerminal() throws {}
}
#endif
