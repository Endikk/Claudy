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

/// Kills a port's process, or refuses and says why.
///
/// Every refusal here is a case where killing would be worse than leaving the port open:
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
        guard port.pid > 1, port.pid != ownPID else { return .failure(.protectedProcess) }

        guard let process = table.processes[port.pid] else { return .failure(.identityChanged) }
        guard process.startedAt == port.startedAt else { return .failure(.identityChanged) }

        if table.ancestors(of: ownPID).contains(where: { $0.pid == port.pid }) {
            return .failure(.protectedProcess)
        }
        if ProcessTable.isClaudeBinary(process.arguments), signals.isRunning(port.pid) {
            return .failure(.liveClaudeSession)
        }

        guard terminate(port.pid, using: SIGTERM) else { return .failure(.systemRefused) }
        if waitForExit(port.pid) { return .success(()) }

        guard terminate(port.pid, using: SIGKILL) else { return .failure(.systemRefused) }
        return waitForExit(port.pid) ? .success(()) : .failure(.survivedKill)
    }

    /// A dev server is usually a tree — the group carries the children with it. The group is
    /// only signalled when it is neither Claudy's own nor launchd's.
    private func terminate(_ pid: pid_t, using signal: Int32) -> Bool {
        let ownGroup = signals.processGroup(of: ownPID)
        if let group = signals.processGroup(of: pid), group > 1, group != ownGroup {
            return signals.sendToGroup(signal, pgid: group)
        }
        return signals.send(signal, to: pid)
    }

    private func waitForExit(_ pid: pid_t) -> Bool {
        let deadline = Date().addingTimeInterval(graceSeconds)
        while Date() < deadline {
            if !signals.isRunning(pid) { return true }
            Thread.sleep(forTimeInterval: pollSeconds)
        }
        return !signals.isRunning(pid)
    }
}
