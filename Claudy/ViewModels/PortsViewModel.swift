import Foundation
import SwiftUI

/// Drives the Ports tab: what is open, how old it is, and what happened to a kill.
///
/// The scan runs off the main actor — `lsof` and `ps` are cheap but not free, and the widget's
/// gauges must never wait on them. The cadence is slower in the background than on screen:
/// the only thing a hidden tab owes the user is a correct badge.
@MainActor
final class PortsViewModel: ObservableObject {

    @Published private(set) var state: PortScanState = .scanning
    /// MCP servers whose session is gone. They hold no port, so they come from their own scan.
    @Published private(set) var mcpOrphans: [McpOrphan] = []
    /// Kill failures, keyed by row id, shown inline on the row that failed.
    @Published private(set) var failures: [String: String] = [:]
    /// Raised while the confirmation is on screen. A bulk kill is the one action here that can
    /// take several processes down at once, so it never fires straight off a click.
    @Published var isConfirmingBulkKill = false

    private let scanner: PortScanning
    private let mcpScanner: McpScanning
    private let reaper: PortReaper
    private var timer: Timer?
    private var isVisible = false

    private let visibleInterval: TimeInterval = 5
    private let backgroundInterval: TimeInterval = 30

    init(
        scanner: PortScanning = PortScanner(),
        mcpScanner: McpScanning = McpScanner(),
        reaper: PortReaper = PortReaper()
    ) {
        self.scanner = scanner
        self.mcpScanner = mcpScanner
        self.reaper = reaper
    }

    var ports: [ListeningPort] {
        if case .ready(let ports, _) = state { return ports }
        return []
    }

    var orphans: [ListeningPort] {
        ports.filter { $0.attribution == .orphan }
    }

    /// Everything Claude left behind, ports and servers alike: the number on the tab's badge.
    var orphanCount: Int { orphans.count + mcpOrphans.count }

    /// What the bulk kill is about to take down, as the confirmation names it: ports by
    /// number, servers by name.
    var bulkKillTargets: String {
        (orphans.map { String($0.port) } + mcpOrphans.map(\.name)).joined(separator: ", ")
    }

    var mcpMemory: UInt64 {
        mcpOrphans.reduce(0) { $0 + $1.residentBytes }
    }

    func requestBulkKill() {
        guard orphanCount > 0 else { return }
        isConfirmingBulkKill = true
    }

    /// Kills what the confirmation named, and nothing that appeared since. Each kill refreshes
    /// the lists, so a target an earlier kill already took down is skipped rather than reported
    /// as a failure.
    func killAllOrphans() async {
        isConfirmingBulkKill = false
        let confirmedPorts = orphans
        let confirmedServers = mcpOrphans
        for port in confirmedPorts where orphans.contains(where: { $0.id == port.id }) {
            await kill(port)
        }
        for server in confirmedServers where mcpOrphans.contains(where: { $0.id == server.id }) {
            await kill(server)
        }
    }

    func start() {
        schedule(interval: backgroundInterval)
        Task { await refresh() }
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
        schedule(interval: isVisible ? visibleInterval : backgroundInterval)
        if isVisible { Task { await refresh() } }
    }

    /// The MCP scan runs after the ports scan because it skips every pid the ports list already
    /// shows. It runs even when the ports scan could not: one does not need the other's tool.
    func refresh() async {
        let scanner = self.scanner
        let mcpScanner = self.mcpScanner
        let (ports, servers) = await Task.detached(priority: .utility) { () -> (PortScanState, [McpOrphan]) in
            let ports = scanner.scan()
            let listed: Set<pid_t>
            if case .ready(let found, _) = ports {
                listed = Set(found.map(\.pid))
            } else {
                listed = []
            }
            return (ports, mcpScanner.scan(excluding: listed))
        }.value
        state = ports
        mcpOrphans = servers
    }

    func kill(_ port: ListeningPort) async {
        let reaper = self.reaper
        await reap(rowID: port.id) { reaper.kill(port, table: $0) }
    }

    func kill(_ server: McpOrphan) async {
        let reaper = self.reaper
        await reap(rowID: server.id) { reaper.kill(server, table: $0) }
    }

    /// The kill reads a fresh table: the one behind the row on screen may be seconds old.
    private func reap(
        rowID: String,
        with attempt: @escaping (ProcessTable) -> Result<Void, KillRefusal>
    ) async {
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, KillRefusal> in
            guard let table = ProcessTable.load() else { return .failure(.identityChanged) }
            return attempt(table)
        }.value

        switch outcome {
        case .success:
            failures[rowID] = nil
        case .failure(let refusal):
            failures[rowID] = Self.explain(refusal)
        }
        await refresh()
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private static func explain(_ refusal: KillRefusal) -> String {
        switch refusal {
        case .identityChanged: "the process changed, nothing was killed"
        case .protectedProcess: "protected process"
        case .liveClaudeSession: "live Claude session"
        case .systemRefused: "refused by the system"
        case .survivedKill: "still alive after SIGKILL"
        }
    }

    /// Age in the largest unit that still reads at a glance.
    static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "\(max(seconds, 0)) s"
        case ..<3600: return "\(seconds / 60) min"
        case ..<86400: return "\(seconds / 3600) h"
        default: return "\(seconds / 86400) d"
        }
    }

    private static let bytesPerMegabyte: UInt64 = 1 << 20
    private static let megabytesPerGigabyte: UInt64 = 1 << 10

    /// Memory in binary units, as Activity Monitor counts it: whole megabytes, then gigabytes
    /// with one decimal once the megabytes no longer read at a glance.
    static func memory(_ bytes: UInt64) -> String {
        let megabytes = (bytes + bytesPerMegabyte / 2) / bytesPerMegabyte
        guard megabytes >= megabytesPerGigabyte else { return "\(megabytes) MB" }
        let gigabytes = Double(bytes) / Double(bytesPerMegabyte * megabytesPerGigabyte)
        return String(format: "%.1f GB", gigabytes)
    }
}
