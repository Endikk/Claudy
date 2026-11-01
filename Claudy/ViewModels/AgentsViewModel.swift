import Foundation
import SwiftUI

/// Drives every face of the agents list: the card's Agents tab, the popover's and the island's
/// short list, the menu bar item's count.
///
/// The scan is cheap once each transcript has been read through (a few file sizes, a few appended
/// lines), so it runs every few seconds while agents are at work, the track moving with them, and
/// slows down when none is.
@MainActor
final class AgentsViewModel: ObservableObject {

    @Published private(set) var agents: [RunningAgent] = []
    /// The moment of the last pass. Rows read their elapsed time and their track against it, so
    /// they all agree and move together.
    @Published private(set) var now = Date()

    private let scanner: AgentScanning
    /// Each running agent's place in `Theme.agentTints`, kept for as long as it is listed.
    private var colours: [String: Int] = [:]
    private var timer: Timer?
    private var interval: TimeInterval?

    static let busyInterval: TimeInterval = 3
    static let quietInterval: TimeInterval = 10

    init(scanner: AgentScanning = AgentScanner()) {
        self.scanner = scanner
    }

    func start() {
        Task { await refresh() }
    }

    func refresh() async {
        let found = await scanner.scan()
        // Nothing running, nothing to move: the views that read `now` are not redrawn for it.
        if !found.isEmpty || !agents.isEmpty { now = Date() }
        assignColours(to: found)
        if found != agents { agents = found }
        schedule(found.isEmpty ? Self.quietInterval : Self.busyInterval)
    }

    /// The agent whose small Claudy speaks for the group in the menu bar and the notch: one at
    /// work, else the oldest.
    var lead: RunningAgent? {
        agents.first { $0.status(at: now) == .working } ?? agents.first
    }

    /// Its colour in `Theme.agentTints`. An agent not seen yet takes the first one.
    func colourIndex(of agent: RunningAgent) -> Int { colours[agent.id] ?? 0 }

    /// Its Claudy's colour, grey once it falls silent.
    func tint(of agent: RunningAgent) -> Color {
        agent.status(at: now) == .idle ? Theme.idle : Theme.agentTints[colourIndex(of: agent)]
    }

    /// A newcomer takes the least used colour, the first one on a tie, so agents running side by
    /// side differ; one that keeps running never changes colour.
    private func assignColours(to found: [RunningAgent]) {
        let ids = Set(found.map(\.id))
        colours = colours.filter { ids.contains($0.key) }
        for agent in found where colours[agent.id] == nil {
            var uses = Array(repeating: 0, count: Theme.agentTints.count)
            for index in colours.values { uses[index] += 1 }
            colours[agent.id] = uses.indices.min { (uses[$0], $0) < (uses[$1], $1) } ?? 0
        }
    }

    /// How long it has been running, in the largest unit that still reads at a glance.
    func elapsed(_ agent: RunningAgent) -> String {
        let seconds = Int(now.timeIntervalSince(agent.startedAt))
        switch seconds {
        case ..<60: return "<1 min"
        case ..<3600: return "\(seconds / 60) min"
        default: return "\(seconds / 3600) h \(String(format: "%02d", seconds % 3600 / 60))"
        }
    }

    /// The hover text of a row: whose agent it is and everything it wrote.
    func details(_ agent: RunningAgent) -> String {
        var lines = ["\(agent.sessionName) · \(elapsed(agent)) · \(agent.actionCount) actions"]
        if !agent.editedFiles.isEmpty {
            lines.append("Edited: " + agent.editedFiles.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private func schedule(_ interval: TimeInterval) {
        guard interval != self.interval else { return }
        self.interval = interval
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
}
