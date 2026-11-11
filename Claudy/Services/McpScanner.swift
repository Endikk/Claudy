import Darwin
import Foundation

/// What the MCP scan asks the kernel about one process, behind closures so the orphan rule can
/// be tested without any live process.
struct ProcessProbe {
    let isOwnedByUser: (pid_t) -> Bool
    let executablePath: (pid_t) -> String?
    let markers: (pid_t) -> ProcessEnvironment.Markers?
    let residentBytes: (pid_t) -> UInt64?

    static let system = ProcessProbe(
        isOwnedByUser: { SystemProbe.owner(of: $0) == getuid() },
        executablePath: { ProcessIdentity.executablePath(of: $0) },
        markers: { ProcessEnvironment.markers(pid: $0) },
        residentBytes: { SystemProbe.residentBytes(of: $0) }
    )
}

/// The two `proc_pidinfo` reads the scan needs that `ProcessIdentity` does not offer.
private enum SystemProbe {

    static func owner(of pid: pid_t) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_uid
    }

    static func residentBytes(of pid: pid_t) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return info.pti_resident_size
    }
}

/// Finds the MCP servers Claude Code left running.
///
/// Claude Code talks to an MCP server over its stdin and stdout, so the server opens no port and
/// the ports scan never sees it. When the session exits badly, launchd adopts the server and it
/// keeps its memory, often hundreds of megabytes, for as long as the Mac stays up. As with ports,
/// attribution comes from the environment; the tree only says whether a session still owns it.
struct McpScanner {

    /// What marks a path component as an MCP server's: `chrome-devtools-mcp`, `mcp_server_git`,
    /// and the official `@modelcontextprotocol` scope, which spells the protocol out.
    private static let serverSignatures = ["mcp", "modelcontextprotocol"]
    private static let scriptExtensions: Set<String> = ["js", "cjs", "mjs", "py"]

    private let loadTable: () -> ProcessTable?
    private let probe: ProcessProbe
    private let liveSessionIDs: () -> Set<String>

    init(
        loadTable: @escaping () -> ProcessTable? = { ProcessTable.load() },
        probe: ProcessProbe = .system,
        liveSessionIDs: @escaping () -> Set<String> = { LiveSessions.ids() }
    ) {
        self.loadTable = loadTable
        self.probe = probe
        self.liveSessionIDs = liveSessionIDs
    }

    /// `portPIDs` are the processes the ports list already shows, never listed twice.
    func scan(excluding portPIDs: Set<pid_t>) -> [McpOrphan] {
        guard let table = loadTable() else { return [] }
        return Self.orphans(table: table, excluding: portPIDs, probe: probe, liveSessionIDs: liveSessionIDs)
    }

    // MARK: - The orphan rule

    private struct Attributed {
        let process: RunningProcess
        let markers: ProcessEnvironment.Markers
    }

    /// When a process dies, launchd adopts its children.
    private static let launchd: pid_t = 1

    /// A server is an orphan when it looks like one, belongs to the user, runs outside any app,
    /// was launched by Claude Code, has no live Claude Code above it, and its session, when it
    /// names one, is not live.
    ///
    /// It must also have been adopted by launchd, which is what happens to a server whose Claude
    /// Code died. That makes the row the top of the orphaned tree, the rest of the tree being
    /// part of it, and it spares the servers a live daemon still manages: the claude-mem worker
    /// runs its own `chroma-mcp` and hands it its Claude markers.
    ///
    /// Everything is injected so the rule can be tested without a live process. The checks run
    /// cheapest first, and the live sessions are only read once something needs them.
    static func orphans(
        table: ProcessTable,
        excluding portPIDs: Set<pid_t>,
        probe: ProcessProbe,
        liveSessionIDs: () -> Set<String>
    ) -> [McpOrphan] {
        let attributed = table.processes.values
            .filter { isShortlisted($0, table: table, portPIDs: portPIDs, probe: probe) }
            .compactMap { process -> Attributed? in
                guard let markers = probe.markers(process.pid), markers.isClaude else { return nil }
                return Attributed(process: process, markers: markers)
            }
        guard !attributed.isEmpty else { return [] }

        let live = liveSessionIDs()
        return attributed
            .filter { server in
                guard let session = server.markers.sessionID else { return true }
                return !live.contains(session)
            }
            .map { orphan($0, table: table, probe: probe) }
            .sorted(by: isListedBefore)
    }

    /// The half of the rule the table and one cheap syscall can answer. Only what passes has
    /// its environment read: `KERN_PROCARGS2` costs a `kern.argmax` buffer per call.
    private static func isShortlisted(
        _ process: RunningProcess,
        table: ProcessTable,
        portPIDs: Set<pid_t>,
        probe: ProcessProbe
    ) -> Bool {
        guard process.pid > launchd,
              process.parent == launchd,
              !portPIDs.contains(process.pid),
              looksLikeMcpServer(process.arguments),
              table.claudeSessionRoot(of: process.pid) == nil,
              probe.isOwnedByUser(process.pid),
              let executable = probe.executablePath(process.pid)
        else { return false }
        // An app ships and supervises its own helpers: their lifetime is the app's business.
        return !executable.contains(".app/")
    }

    private static func orphan(_ top: Attributed, table: ProcessTable, probe: ProcessProbe) -> McpOrphan {
        let tree = [top.process] + table.descendants(of: top.process.pid)
        return McpOrphan(
            id: "mcp-\(top.process.pid)",
            pid: top.process.pid,
            startedAt: top.process.startedAt,
            name: displayName(arguments: top.process.arguments),
            projectName: top.markers.projectDirectory.map { ($0 as NSString).lastPathComponent },
            residentBytes: tree.reduce(0) { $0 + (probe.residentBytes($1.pid) ?? 0) }
        )
    }

    /// The heaviest first: that is the one worth killing.
    private static func isListedBefore(_ lhs: McpOrphan, _ rhs: McpOrphan) -> Bool {
        if lhs.residentBytes != rhs.residentBytes { return lhs.residentBytes > rhs.residentBytes }
        return lhs.pid < rhs.pid
    }

    // MARK: - Command line

    /// Some argument names an MCP server. Flags do not count: `--mcp-config` configures a client.
    /// Claude Code itself is excluded, `claude mcp serve` included: the reaper never kills it.
    static func looksLikeMcpServer(_ arguments: String) -> Bool {
        !ProcessTable.isClaudeBinary(arguments) && mcpPackage(in: arguments) != nil
    }

    /// The server's name, from the first argument path component that names it, without its
    /// version or script extension: `npm exec chrome-devtools-mcp@latest` and
    /// `node …/chrome-devtools-mcp/build/src/index.js` both give `chrome-devtools-mcp`. A scoped
    /// package keeps its scope, which alone names nothing and without which `@playwright/mcp`
    /// would read `mcp`. Falls back to the executable's file name.
    static func displayName(arguments: String) -> String {
        if let package = mcpPackage(in: arguments) { return package }
        let executable = arguments.split(separator: " ").first.map(String.init) ?? arguments
        return (executable as NSString).lastPathComponent
    }

    private static func mcpPackage(in arguments: String) -> String? {
        for token in arguments.split(separator: " ") where !token.hasPrefix("-") {
            let components = token.split(separator: "/").map(String.init)
            for (index, component) in components.enumerated() {
                guard let name = signedName(in: component) else { continue }
                return package(name, at: index, in: components)
            }
        }
        return nil
    }

    /// Within a component, the run of characters a package or module name is made of that
    /// carries a signature. It cuts the name out of what surrounds it: the pin of
    /// `chroma-mcp==0.2.6`, or the quotes and calls of an inline `node -e` script.
    private static func signedName(in component: String) -> String? {
        nameRuns(in: component).first { run in
            let lowered = run.lowercased()
            return serverSignatures.contains { lowered.contains($0) }
        }
    }

    private static func nameRuns(in component: String) -> [String] {
        component
            .split { !($0.isLetter || $0.isNumber || "@._-".contains($0)) }
            .map(String.init)
    }

    private static func package(_ name: String, at index: Int, in components: [String]) -> String {
        if name.hasPrefix("@"), index + 1 < components.count, let package = nameRuns(in: components[index + 1]).first {
            return "\(name)/\(bareName(package))"
        }
        if index > 0, components[index - 1].hasPrefix("@") {
            return "\(components[index - 1])/\(bareName(name))"
        }
        return bareName(name)
    }

    /// `chrome-devtools-mcp@latest` gives `chrome-devtools-mcp`, `mcp-server.cjs` gives
    /// `mcp-server`. A leading `@` is a scope, not a version.
    private static func bareName(_ component: String) -> String {
        let unversioned = component.lastIndex(of: "@")
            .flatMap { $0 == component.startIndex ? nil : String(component[..<$0]) } ?? component
        let name = unversioned as NSString
        return scriptExtensions.contains(name.pathExtension.lowercased())
            ? name.deletingPathExtension
            : unversioned
    }
}

/// Injected into the view model so its state machine can be tested without touching the machine.
protocol McpScanning {
    func scan(excluding portPIDs: Set<pid_t>) -> [McpOrphan]
}

extension McpScanner: McpScanning {}

/// The Claude Code sessions running right now, from the files Claude Code keeps in `sessions/`:
/// one per process, named after its pid.
enum LiveSessions {

    private struct SessionFile: Decodable {
        let pid: Int32
        let sessionId: String
        /// "Tue Nov 10 13:33:34 2026": when the process started, which tells a reused pid apart.
        let procStart: String?
    }

    /// An unreadable or missing folder means no session is known to be live. The ancestry check
    /// still protects every server a live session spawned; only a session that outlived its
    /// link to its servers goes unrecognised.
    static func ids(
        in directory: URL = ClaudeHome.configDirectory.appendingPathComponent("sessions", isDirectory: true),
        isLive: (Int32, Date?) -> Bool = { ProcessIdentity.isSession(pid: $0, startedAt: $1) }
    ) -> Set<String> {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let ids = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { id(from: $0, isLive: isLive) } }
        return Set(ids)
    }

    /// The session a file describes, when its process still runs; nil for a malformed file.
    static func id(from data: Data, isLive: (Int32, Date?) -> Bool) -> String? {
        guard let file = try? JSONDecoder().decode(SessionFile.self, from: data) else { return nil }
        let startedAt = file.procStart.flatMap(ProcessIdentity.date(fromProcStart:))
        return isLive(file.pid, startedAt) ? file.sessionId : nil
    }
}
