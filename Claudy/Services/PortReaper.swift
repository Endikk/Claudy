import Foundation

/// The signalling side effects, behind a protocol so the guardrails can be tested without
/// ever signalling a real process.
protocol SignalSending {
    func send(_ signal: Int32, to pid: pid_t) -> Bool
    func sendToGroup(_ signal: Int32, pgid: pid_t) -> Bool
    func processGroup(of pid: pid_t) -> pid_t?
    func isRunning(_ pid: pid_t) -> Bool
}

struct SystemSignals: SignalSending {
    func send(_ signal: Int32, to pid: pid_t) -> Bool { Darwin.kill(pid, signal) == 0 }
    func sendToGroup(_ signal: Int32, pgid: pid_t) -> Bool { killpg(pgid, signal) == 0 }
    func processGroup(of pid: pid_t) -> pid_t? {
        let group = getpgid(pid)
        return group == -1 ? nil : group
    }
    /// EPERM means the process exists and belongs to someone else — alive, not absent.
    func isRunning(_ pid: pid_t) -> Bool { Darwin.kill(pid, 0) == 0 || errno == EPERM }
}

enum KillRefusal: Error, Equatable {
    case identityChanged
    case protectedProcess
    case liveClaudeSession
    case systemRefused
    case survivedKill
}

/// What a kill takes down besides the process it names.
enum KillScope {
    /// A port's server and its process group, when the group is safe to signal.
    case group
    /// An MCP server and every process under it. Its group is only used when the server leads
    /// it: Claude Code does not detach the servers it spawns, so they keep the group of the
    /// session that died, and that group still holds everything else the session left behind.
    case tree
}

/// Kills a process Claude left behind, or refuses and says why.
///
/// Every refusal here is a case where killing would be worse than leaving the process running:
/// signalling the wrong process after a PID reuse, taking down Claudy, or taking down the
/// Claude session the user is currently talking to.
struct PortReaper {
    private let signals: SignalSending
    private let ownPID: pid_t
    private let graceSeconds: TimeInterval = 3
    private let pollSeconds: TimeInterval = 0.1

    init(signals: SignalSending = SystemSignals(), ownPID: pid_t = getpid()) {
        self.signals = signals
        self.ownPID = ownPID
    }

    func kill(_ port: ListeningPort, table: ProcessTable) -> Result<Void, KillRefusal> {
        kill(pid: port.pid, startedAt: port.startedAt, table: table, scope: .group)
    }

    func kill(_ server: McpOrphan, table: ProcessTable) -> Result<Void, KillRefusal> {
        kill(pid: server.pid, startedAt: server.startedAt, table: table, scope: .tree)
    }

    /// The process is named by its pid and start time together: the pid alone may have been
    /// handed to another process since the scan.
    func kill(pid: pid_t, startedAt: Date, table: ProcessTable, scope: KillScope = .group) -> Result<Void, KillRefusal> {
        if let refusal = refusal(pid: pid, startedAt: startedAt, table: table, scope: scope) {
            return .failure(refusal)
        }
        let plan = plan(pid: pid, table: table, scope: scope)

        guard deliver(SIGTERM, to: plan) else { return .failure(.systemRefused) }
        if waitForExit(plan.members) { return .success(()) }

        guard deliver(SIGKILL, to: plan) else { return .failure(.systemRefused) }
        return waitForExit(plan.members) ? .success(()) : .failure(.survivedKill)
    }

    private func refusal(pid: pid_t, startedAt: Date, table: ProcessTable, scope: KillScope) -> KillRefusal? {
        guard pid > 1, pid != ownPID else { return .protectedProcess }

        guard let process = table.processes[pid], process.startedAt == startedAt else { return .identityChanged }

        if table.ancestors(of: ownPID).contains(where: { $0.pid == pid }) {
            return .protectedProcess
        }
        if isLiveClaude(process) {
            return .liveClaudeSession
        }
        guard scope == .tree else { return nil }

        // The scan found no live session above the server. Checked again on the fresh table:
        // the tree may have changed between the render and the click.
        if table.claudeSessionRoot(of: pid) != nil {
            return .liveClaudeSession
        }
        // A server that drives Claude Code holds a live session somewhere in its tree.
        if table.descendants(of: pid).contains(where: isLiveClaude) {
            return .liveClaudeSession
        }
        return nil
    }

    private func isLiveClaude(_ process: RunningProcess) -> Bool {
        ProcessTable.isClaudeBinary(process.arguments) && signals.isRunning(process.pid)
    }

    // MARK: - Signalling

    private struct Plan {
        let root: pid_t
        /// Set when the group is signalled instead of the processes one by one.
        let group: pid_t?
        /// The descendants signalled one by one, when no group carries them.
        let descendants: [pid_t]

        var members: [pid_t] { [root] + descendants }
    }

    /// A dev server is usually a tree, and the group carries the children with it. The group is
    /// only signalled when it is neither Claudy's own nor launchd's, and for an MCP server only
    /// when the server leads it. Without a group, a tree is signalled process by process.
    private func plan(pid: pid_t, table: ProcessTable, scope: KillScope) -> Plan {
        let ownGroup = signals.processGroup(of: ownPID)
        let group = signals.processGroup(of: pid).flatMap { group -> pid_t? in
            guard group > 1, group != ownGroup else { return nil }
            return scope == .tree && group != pid ? nil : group
        }
        let descendants = scope == .tree && group == nil ? table.descendants(of: pid).map(\.pid) : []
        return Plan(root: pid, group: group, descendants: descendants)
    }

    /// Only the root's delivery is required. A descendant may well have exited with its parent,
    /// and one already gone is not signalled again.
    private func deliver(_ signal: Int32, to plan: Plan) -> Bool {
        if let group = plan.group {
            return signals.sendToGroup(signal, pgid: group)
        }
        var isRootRefused = false
        for pid in plan.members where signals.isRunning(pid) {
            let delivered = signals.send(signal, to: pid)
            if pid == plan.root, !delivered { isRootRefused = true }
        }
        return !isRootRefused
    }

    private func waitForExit(_ pids: [pid_t]) -> Bool {
        let deadline = Date().addingTimeInterval(graceSeconds)
        while Date() < deadline {
            if !pids.contains(where: signals.isRunning) { return true }
            Thread.sleep(forTimeInterval: pollSeconds)
        }
        return !pids.contains(where: signals.isRunning)
    }
}
