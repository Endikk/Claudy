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
    /// Kill failures, keyed by port id, shown inline on the row that failed.
    @Published private(set) var failures: [String: String] = [:]

    private let scanner: PortScanning
    private let reaper: PortReaper
    private var timer: Timer?
    private var isVisible = false

    private let visibleInterval: TimeInterval = 5
    private let backgroundInterval: TimeInterval = 30

    init(scanner: PortScanning = PortScanner(), reaper: PortReaper = PortReaper()) {
        self.scanner = scanner
        self.reaper = reaper
    }

    var ports: [ListeningPort] {
        if case .ready(let ports, _) = state { return ports }
        return []
    }

    var orphanCount: Int {
        ports.filter { $0.attribution == .orphan }.count
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

    func refresh() async {
        let scanner = self.scanner
        let scanned = await Task.detached(priority: .utility) { scanner.scan() }.value
        state = scanned
    }

    func kill(_ port: ListeningPort) async {
        let reaper = self.reaper
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, KillRefusal> in
            guard let table = ProcessTable.load() else { return .failure(.identityChanged) }
            return reaper.kill(port, table: table)
        }.value

        switch outcome {
        case .success:
            failures[port.id] = nil
        case .failure(let refusal):
            failures[port.id] = Self.explain(refusal)
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
}
