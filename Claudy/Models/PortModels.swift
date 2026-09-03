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

enum PortScanState: Equatable {
    case scanning
    case ready([ListeningPort])
    /// The scan could not run at all; the string is shown to the user as the reason.
    case unavailable(String)
}
