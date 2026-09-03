import Foundation

/// Lists the TCP ports Claude Code is holding open on this machine.
///
/// Attribution comes from the process environment, never from the process tree: an orphaned
/// server has no Claude ancestor left, yet it is exactly the one worth killing. The tree only
/// answers a second question — is the owning session still alive.
struct PortScanner {

    /// A container runtime publishes ports for everything it hosts. Killing it would take the
    /// runtime down with the container, so it is never attributed, whatever its environment.
    private static let deniedCommands = ["orbstack", "docker", "com.docker.backend"]

    private static let executable = "/usr/sbin/lsof"
    private static let timeout: TimeInterval = 6

    /// lsof exits 1 when nothing matches the filter, which is an empty list, not a failure.
    private static let acceptedStatuses: Set<Int32> = [0, 1]

    private static var arguments: [String] {
        ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", String(getuid()), "-F", "pcn"]
    }

    func scan() -> PortScanState {
        guard let output = Subprocess.run(
            Self.executable, Self.arguments,
            timeout: Self.timeout, acceptedStatuses: Self.acceptedStatuses
        ) else {
            return .unavailable("lsof did not respond")
        }
        guard let table = ProcessTable.load() else {
            return .unavailable("ps did not respond")
        }
        let ports = Self.attribute(
            listeners: Self.parseListeners(output),
            table: table,
            markers: { ProcessEnvironment.markers(pid: $0) }
        )
        return .ready(ports.sorted { $0.port < $1.port })
    }

    /// lsof's field output: one field per line, prefixed by its letter. `p` opens a process
    /// block, `c` names it, `n` describes one socket. Any other field — `f` among them — is
    /// ignored rather than assumed absent.
    ///
    /// A server holds one descriptor per address family and per accepting socket, and lsof
    /// reports each of them: on this machine every listener appeared twice. Collapsing on
    /// (pid, port) is what keeps `ListeningPort.id` unique.
    static func parseListeners(_ output: String) -> [Listener] {
        var listeners: [Listener] = []
        var seen: Set<String> = []
        var pid: pid_t?
        var command = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = pid_t(value)
            case "c": command = value
            case "n":
                guard let pid, let (address, port) = splitEndpoint(value) else { continue }
                guard seen.insert("\(pid)-\(port)").inserted else { continue }
                listeners.append(Listener(pid: pid, command: command, port: port, address: address))
            default: continue
            }
        }
        return listeners
    }

    /// `127.0.0.1:4000`, `*:3001` and `[::1]:3000` all split at the last colon.
    private static func splitEndpoint(_ endpoint: String) -> (String, Int)? {
        guard let separator = endpoint.lastIndex(of: ":"),
              let port = Int(endpoint[endpoint.index(after: separator)...])
        else { return nil }
        return (String(endpoint[..<separator]), port)
    }

    static func isDenied(command: String) -> Bool {
        let lowered = command.lowercased()
        return deniedCommands.contains { lowered.contains($0) }
    }

    /// `markers` is injected so attribution can be tested without any live process.
    static func attribute(
        listeners: [Listener],
        table: ProcessTable,
        markers: (pid_t) -> ProcessEnvironment.Markers?
    ) -> [ListeningPort] {
        listeners.compactMap { listener in
            guard !isDenied(command: listener.command),
                  let marker = markers(listener.pid), marker.isClaude,
                  let process = table.processes[listener.pid]
            else { return nil }

            let root = table.claudeSessionRoot(of: listener.pid)
            return ListeningPort(
                id: "\(listener.pid)-\(listener.port)",
                pid: listener.pid,
                port: listener.port,
                command: listener.command,
                projectName: marker.projectDirectory.map { ($0 as NSString).lastPathComponent },
                startedAt: process.startedAt,
                attribution: root == nil ? .orphan : .live,
                sessionRootPID: root?.pid
            )
        }
    }
}
