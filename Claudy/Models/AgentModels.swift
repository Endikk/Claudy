import Foundation

/// What one tool call did, reduced to what the agents list tells apart: writing a file stands
/// out, everything else is background work.
enum AgentActionKind: Equatable, Sendable {
    case read, edit, run, web, other

    init(tool: String) {
        switch tool {
        case "Read", "Grep", "Glob", "LS", "NotebookRead":
            self = .read
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            self = .edit
        case "Bash", "BashOutput", "KillShell", "KillBash":
            self = .run
        case "WebFetch", "WebSearch":
            self = .web
        default:
            // Browser tools come through MCP servers, under names their plugin chooses.
            let browsing = ["browser", "chrome", "devtools", "playwright"].contains { tool.contains($0) }
            self = tool.hasPrefix("mcp__") && browsing ? .web : .other
        }
    }
}

/// One tool call from an agent's transcript.
struct AgentAction: Equatable, Sendable {
    let date: Date
    let kind: AgentActionKind
    let tool: String
    /// The file's name alone: its full path says nothing more in a 300-point card.
    let file: String?
}

/// One fifteen-second slot of an agent's track.
struct AgentTrackSlot: Equatable, Sendable {
    var edits = 0
    var others = 0
}

/// A subagent Claude Code launched, as the agents list shows it. Built by `AgentScanner` from the
/// agent's own transcript, so it says only what Claude Code wrote down: no progress percentage,
/// which no file holds.
struct RunningAgent: Identifiable, Equatable, Sendable {
    let id: String
    let sessionID: String
    /// The Claude Code process that launched it. Agents have no process of their own: stopping
    /// one means interrupting its session, as Ctrl+C would.
    let sessionPID: Int32
    /// When that process started, as its session file records it: a pid is reused once its
    /// process exits, the start time is not.
    let sessionStartedAt: Date?
    /// `claire-bb`, or the working folder's name when the session has none.
    let sessionName: String
    /// What it was asked, as written when it was launched.
    let title: String
    let startedAt: Date
    /// Last write to its transcript.
    let lastActivity: Date
    let isFinished: Bool
    let actionCount: Int
    /// Tool calls of the last `trackSpan`, oldest first.
    let recent: [AgentAction]
    let lastAction: AgentAction?
    /// Files it wrote, in the order it first touched them.
    let editedFiles: [String]

    /// `idle` is a pause: a long command, a wait on the parent. `stalled` is a pause long enough
    /// to go and look: a permission nobody answered, a hung tool.
    enum Status: Equatable, Sendable { case working, idle, stalled, done }

    /// Past this, a silent agent is shown at rest: waiting on a long command, or on its parent.
    static let idleAfter: TimeInterval = 60
    /// Past this, its silence is called out.
    static let stalledAfter: TimeInterval = 180
    /// The track's reach, cut in `trackSlots` slots.
    static let trackSpan: TimeInterval = 600
    static let trackSlots = 40

    func status(at now: Date) -> Status {
        if isFinished { return .done }
        switch silence(at: now) {
        case ..<Self.idleAfter: return .working
        case ..<Self.stalledAfter: return .idle
        default: return .stalled
        }
    }

    /// How long since it last wrote anything.
    func silence(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(lastActivity))
    }

    /// What it is touching now: the file of its last call, or the kind of work in one word.
    var touching: String {
        guard let lastAction else { return "starting" }
        if let file = lastAction.file { return file }
        switch lastAction.kind {
        case .run: return "terminal"
        case .web: return "web"
        case .read: return "search"
        case .edit, .other: return lastAction.tool.lowercased()
        }
    }

    /// Its last call wrote a file: the file is shown in the accent.
    var isWriting: Bool { lastAction?.kind == .edit && lastAction?.file != nil }

    /// The last `trackSpan` in slots, newest last: writes apart from the rest, so a burst of
    /// edits stands out.
    func track(at now: Date) -> [AgentTrackSlot] {
        var slots = Array(repeating: AgentTrackSlot(), count: Self.trackSlots)
        let width = Self.trackSpan / Double(Self.trackSlots)
        let start = now.addingTimeInterval(-Self.trackSpan)
        for action in recent {
            // A call stamped this very second, or a moment ahead of this Mac's clock, is the newest.
            let index = min(Int(floor(action.date.timeIntervalSince(start) / width)), Self.trackSlots - 1)
            guard index >= 0 else { continue }
            if action.kind == .edit { slots[index].edits += 1 } else { slots[index].others += 1 }
        }
        return slots
    }
}
