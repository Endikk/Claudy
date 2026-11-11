import Foundation

/// The app a Claude Code session runs in, found up its process tree: what "Open" brings forward.
struct HostApp: Equatable, Sendable {
    /// The bundle's own file name, "Visual Studio Code" or "Terminal": the name its users know,
    /// where `CFBundleName` can be a bare "Code".
    let name: String
    let bundleURL: URL

    /// The name for a button: "VS Code" rather than its bundle's full name.
    var shortName: String {
        switch name {
        case "Visual Studio Code": "VS Code"
        case "Visual Studio Code - Insiders": "VS Code Insiders"
        default: name
        }
    }
}

/// An open Claude Code session, as its session file and its process describe it.
///
/// Claude Code rewrites `<config>/sessions/<pid>.json` as the session changes: `busy` while it
/// works, `idle` at its prompt, `waiting` when it asks the user something, with what it waits
/// for in `waitingFor` ("permission prompt", "input needed"). Nothing is installed in Claude Code
/// to know it.
struct ClaudeSession: Identifiable, Equatable, Sendable {

    enum Status: Equatable, Sendable {
        case busy
        case idle
        /// Claude Code asks the user something. `reason` is its own words for it.
        case waiting(reason: String?)
        /// A Claude Code too old to write its status.
        case unknown

        init(raw: String?, waitingFor: String?) {
            switch raw {
            case "busy": self = .busy
            case "idle": self = .idle
            case "waiting": self = .waiting(reason: waitingFor)
            default: self = raw == nil ? .unknown : .busy
            }
        }
    }

    let id: String
    let pid: Int32
    /// When the process started, as the session file records it: a pid is reused once its process
    /// exits, the start time is not.
    let processStartedAt: Date?
    /// `claudy-a5`, or the working folder's name when the session has none.
    let name: String
    let cwd: String?
    /// When the session opened.
    let openedAt: Date?
    let status: Status
    /// When the status last changed: how long it has been waiting, or idle.
    let statusSince: Date?
    /// Launched by a program through the Agent SDK rather than by someone: nobody sits at it, so
    /// it is only listed while it runs agents, and never said to wait for anyone.
    let isBackground: Bool
    let host: HostApp?
    /// The last thing the user asked it, on one line.
    let lastPrompt: String?

    var isWaiting: Bool {
        if case .waiting = status { return true }
        return false
    }

    /// Ctrl+C means something only while it works or asks: at its prompt there is no turn to stop.
    /// It also takes the process's start time: without it, a pid reused after the session exits
    /// cannot be told apart from the session.
    var canBeInterrupted: Bool {
        guard processStartedAt != nil else { return false }
        switch status {
        case .busy, .waiting, .unknown: return true
        case .idle: return false
        }
    }

    var folderName: String? {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// What it waits for, in a sentence's first words: "Permission prompt", "Input needed".
    var waitingReason: String? {
        guard case .waiting(let reason) = status, let reason, !reason.isEmpty else { return nil }
        return reason.prefix(1).uppercased() + reason.dropFirst()
    }

    /// The session file's `entrypoint` for a program driving Claude Code: `sdk-cli`, `sdk-ts`.
    static func isBackground(entrypoint: String?) -> Bool {
        entrypoint?.hasPrefix("sdk") ?? false
    }
}

/// One pass over Claude Code's files: the sessions open on this Mac and the agents they run.
struct ClaudeActivity: Equatable, Sendable {
    var sessions: [ClaudeSession] = []
    var agents: [RunningAgent] = []
}

/// A session and its agents, as the Sessions tab lists them.
struct SessionGroup: Identifiable, Equatable {
    let session: ClaudeSession
    let agents: [RunningAgent]

    var id: String { session.id }
}
