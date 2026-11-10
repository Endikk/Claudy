import Foundation
import SwiftUI

/// Drives every face of the agents list: the card's Agents tab, the popover's and the island's
/// short list, the menu bar item's count.
///
/// The scan is cheap once each transcript has been read through (a few file sizes, a few appended
/// lines), so it runs every few seconds while agents are listed, the track moving with them, and
/// slows down when none is.
@MainActor
final class AgentsViewModel: ObservableObject {

    @Published private(set) var agents: [RunningAgent] = []
    /// The moment of the last pass. Rows read their elapsed time and their track against it, so
    /// they all agree and move together.
    @Published private(set) var now = Date()
    /// The agent whose row is unfolded in the card: its session, what it wrote, the way to stop it.
    @Published var expandedID: String?
    /// The session an interrupt is being confirmed for.
    @Published var interruptPending: String?
    /// One line under the list after an interrupt: sent, or why not. Clears itself.
    @Published private(set) var notice: String?

    private let scanner: AgentScanning
    /// Whether a session's process is still that session, checked again the moment a signal is
    /// about to go out: the list may be seconds old and a pid is reused. Injected for the tests.
    private let isLive: @Sendable (Int32, Date?) -> Bool
    /// Sends a signal to a process: 0, or `errno`. Injected so the tests send none.
    private let signal: @Sendable (Int32, Int32) -> Int32
    /// Each pass is numbered: a pass that finishes after a newer one changes nothing.
    private var generation = 0
    /// Each running agent's place in `Theme.agentTints`, kept for as long as it is listed.
    private var colours: [String: Int] = [:]
    private var timer: Timer?
    private var interval: TimeInterval?
    private var noticeTask: Task<Void, Never>?

    static let busyInterval: TimeInterval = 3
    static let quietInterval: TimeInterval = 10
    static let noticeDuration: TimeInterval = 5

    init(scanner: AgentScanning = AgentScanner(),
         isLive: @escaping @Sendable (Int32, Date?) -> Bool = { ProcessIdentity.isSession(pid: $0, startedAt: $1) },
         signal: @escaping @Sendable (Int32, Int32) -> Int32 = { ProcessIdentity.send($1, to: $0) }) {
        self.scanner = scanner
        self.isLive = isLive
        self.signal = signal
    }

    func start() {
        Task { await refresh() }
    }

    func refresh() async {
        generation += 1
        let pass = generation
        let found = await scanner.scan()
        guard pass == generation else { return }
        // Nothing running, nothing to move: the views that read `now` are not redrawn for it.
        if !found.isEmpty || !agents.isEmpty { now = Date() }
        assignColours(to: found)
        if found != agents { agents = found }
        if let expandedID, !found.contains(where: { $0.id == expandedID }) { self.expandedID = nil }
        // The confirmation goes with the last agent of its session that could still be stopped.
        if let interruptPending, !found.contains(where: { $0.sessionID == interruptPending && !$0.isFinished }) {
            self.interruptPending = nil
        }
        schedule(found.isEmpty ? Self.quietInterval : Self.busyInterval)
    }

    /// How many are not done: what the badges count. Finished agents stay listed a while, but
    /// they are not running.
    var runningCount: Int {
        agents.filter { !$0.isFinished }.count
    }

    /// The agent whose small Claudy speaks for the group in the menu bar and the notch: one at
    /// work, else the oldest still running.
    var lead: RunningAgent? {
        agents.first { $0.status(at: now) == .working } ?? agents.first { !$0.isFinished }
    }

    /// Agents of more than one Claude Code session are listed: each row says whose it is.
    var spansSessions: Bool {
        Set(agents.map(\.sessionID)).count > 1
    }

    /// Its colour in `Theme.agentTints`. An agent not seen yet takes the first one.
    func colourIndex(of agent: RunningAgent) -> Int { colours[agent.id] ?? 0 }

    /// Its Claudy's colour, grey once it falls silent.
    func tint(of agent: RunningAgent) -> Color {
        switch agent.status(at: now) {
        case .idle, .stalled: Theme.idle
        case .working, .done: Theme.agentTints[colourIndex(of: agent)]
        }
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

    // MARK: - Words

    /// How long it has been running, in the largest unit that still reads at a glance.
    func elapsed(_ agent: RunningAgent) -> String {
        Self.duration(now.timeIntervalSince(agent.startedAt))
    }

    /// What its row says on the right: the file it touches while it works, its silence once that
    /// silence is worth a look, what it wrote once it is done.
    func state(_ agent: RunningAgent) -> String {
        switch agent.status(at: now) {
        case .working: agent.touching
        case .idle: "waiting"
        case .stalled: "silent \(Self.duration(agent.silence(at: now)))"
        case .done: agent.editedFiles.isEmpty ? "done" : "done · \(Self.files(agent.editedFiles.count))"
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

    /// Its last few tool calls, newest first, as "Edit AgentScanner.swift".
    func lastCalls(_ agent: RunningAgent, limit: Int = 3) -> [String] {
        agent.recent.suffix(limit).reversed().map { action in
            [action.tool, action.file].compactMap { $0 }.joined(separator: " ")
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let seconds = Int(seconds)
        switch seconds {
        case ..<60: return "<1 min"
        case ..<3600: return "\(seconds / 60) min"
        default: return "\(seconds / 3600) h \(String(format: "%02d", seconds % 3600 / 60))"
        }
    }

    static func files(_ count: Int) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }

    // MARK: - Actions

    /// Folding or unfolding any row drops a pending confirmation: it was asked for the row it
    /// showed in, and must not greet the next one armed.
    func toggleExpanded(_ agent: RunningAgent) {
        expandedID = expandedID == agent.id ? nil : agent.id
        interruptPending = nil
    }

    /// Asks before interrupting: the signal reaches the whole session, every agent of it.
    func askToInterrupt(_ agent: RunningAgent) {
        interruptPending = agent.sessionID
    }

    func cancelInterrupt() {
        interruptPending = nil
    }

    /// Interrupts the agent's Claude Code session with the signal Ctrl+C sends in its terminal:
    /// the turn stops and every agent the session runs with it, and the session stays open, at
    /// its prompt or mid-turn alike (checked on real sessions: five signals, five survivors).
    /// Agents have no process of their own, so there is nothing narrower to stop. A command an
    /// agent had already started, a long `sleep` say, runs to its end on its own.
    func interrupt(_ agent: RunningAgent) {
        interruptPending = nil
        // Checked again now, not when the list was last read: the pid may belong to someone else.
        guard agent.sessionPID > 1, isLive(agent.sessionPID, agent.sessionStartedAt) else {
            show("Not sent: \(agent.sessionName) has closed.")
            return
        }
        switch signal(agent.sessionPID, SIGINT) {
        case 0: show("Ctrl+C sent to \(agent.sessionName).")
        case EPERM: show("Not sent: \(agent.sessionName) runs under another user.")
        default: show("Not sent: \(agent.sessionName) has closed.")
        }
    }

    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.noticeDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
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
