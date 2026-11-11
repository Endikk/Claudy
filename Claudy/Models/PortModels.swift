import Foundation

/// One TCP socket in the LISTEN state, as reported by lsof.
struct Listener: Equatable {
    let pid: pid_t
    let command: String
    let port: Int
    let address: String
}

enum PortAttribution: Equatable {
    /// A Claude session that is still running owns this port.
    case live
    /// Claude launched it, and the session that did is gone. The reason this tab exists.
    case orphan
}

struct ListeningPort: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let port: Int
    let command: String
    let projectName: String?
    let startedAt: Date
    let attribution: PortAttribution
    let sessionRootPID: pid_t?
}

/// An MCP server Claude Code launched over stdio and left running when its session ended.
/// It holds no port, so lsof never sees it: its environment and command line give it away.
struct McpOrphan: Identifiable, Equatable {
    let id: String
    /// The top of the orphaned tree: `npm exec`, not the `node` it spawned.
    let pid: pid_t
    let startedAt: Date
    let name: String
    let projectName: String?
    /// Resident memory of the top process and everything under it, in bytes: what a kill gives
    /// back.
    let residentBytes: UInt64
}

enum PortScanState: Equatable {
    case scanning
    /// `isDegraded` marks a scan that could not read process environments and fell back to
    /// the process tree: live sessions still show, orphans cannot.
    case ready([ListeningPort], isDegraded: Bool)
    /// The scan could not run at all; the string is shown to the user as the reason.
    case unavailable(String)
}
