import AppKit
import SwiftUI

/// Drives every face of the sessions and their agents: the card's Sessions tab, the popover's and
/// the island's short lists and waiting rows, the menu bar item's count.
///
/// The scan is cheap once each transcript has been read through (a few file sizes, a few appended
/// lines), so it runs every few seconds while a session works or agents are listed, the tracks
/// moving with them, and slows down when everything rests.
@MainActor
final class AgentsViewModel: ObservableObject {

    @Published private(set) var agents: [RunningAgent] = []
    /// Every Claude Code session open on this Mac, background ones included.
    @Published private(set) var sessions: [ClaudeSession] = []
    /// The moment of the last pass. Rows read their elapsed time and their track against it, so
    /// they all agree and move together.
    @Published private(set) var now = Date()
    /// The agent whose row is unfolded in the card: what it wrote, its last calls.
    @Published var expandedID: String?
    /// The session unfolded in the card: where it runs, the way to its window, the interrupt.
    @Published var expandedSessionID: String?
    /// The session an interrupt is being confirmed for.
    @Published var interruptPending: String?
    /// One line under the list after an action: sent, or why not. Clears itself.
    @Published private(set) var notice: String?

    /// Called after each pass with what it found: the notifications read it.
    var onPass: ((ClaudeActivity) -> Void)?

    private let scanner: AgentScanning
    /// Whether a session's process is still that session, checked again the moment a signal is
    /// about to go out: the list may be seconds old and a pid is reused. Injected for the tests.
    private let isLive: @Sendable (Int32, Date?) -> Bool
    /// Sends a signal to a process: 0, or `errno`. Injected so the tests send none.
    private let signal: @Sendable (Int32, Int32) -> Int32
    /// Brings an app forward; false when it is not there to open. Injected for the tests.
    private let open: @MainActor (HostApp) -> Bool
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
         signal: @escaping @Sendable (Int32, Int32) -> Int32 = { ProcessIdentity.send($1, to: $0) },
         open: @escaping @MainActor (HostApp) -> Bool = AgentsViewModel.bringForward) {
        self.scanner = scanner
        self.isLive = isLive
        self.signal = signal
        self.open = open
    }

    func start() {
        Task { await refresh() }
    }

    func refresh() async {
        generation += 1
        let pass = generation
        let found = await scanner.scanActivity()
        guard pass == generation else { return }
        // Nothing open, nothing to move: the views that read `now` are not redrawn for it.
        let isQuiet = found.agents.isEmpty && found.sessions.isEmpty
        if !isQuiet || !agents.isEmpty || !sessions.isEmpty { now = Date() }
        assignColours(to: found.agents)
        if found.agents != agents { agents = found.agents }
        if found.sessions != sessions { sessions = found.sessions }
        dropWhatLeft()
        let isBusy = !found.agents.isEmpty || found.sessions.contains { $0.status == .busy || $0.isWaiting }
        schedule(isBusy ? Self.busyInterval : Self.quietInterval)
        onPass?(found)
    }

    /// An unfolded row, or a confirmation, goes with the agent or session it was shown for.
    private func dropWhatLeft() {
        if let expandedID, !agents.contains(where: { $0.id == expandedID }) { self.expandedID = nil }
        let listed = groups.map(\.session)
        if let expandedSessionID, !listed.contains(where: { $0.id == expandedSessionID }) {
            self.expandedSessionID = nil
        }
        if let interruptPending, !listed.contains(where: { $0.id == interruptPending && $0.canBeInterrupted }) {
            self.interruptPending = nil
        }
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

    /// The sessions the card lists, each with its agents: the ones someone sits at, and a
    /// program's own only while it runs agents. Waiting first, the longest wait on top, then at
    /// work, then at rest.
    var groups: [SessionGroup] {
        let byID = Dictionary(grouping: agents, by: \.sessionID)
        var listed = sessions.filter { !$0.isBackground || byID[$0.id] != nil }
        // Agents whose session file was not read in this pass still show, under their session.
        for agent in agents where !listed.contains(where: { $0.id == agent.sessionID }) {
            listed.append(ClaudeSession(id: agent.sessionID, pid: agent.sessionPID,
                                        processStartedAt: agent.sessionStartedAt, name: agent.sessionName,
                                        cwd: nil, openedAt: nil, status: .unknown, statusSince: nil,
                                        isBackground: false, host: nil, lastPrompt: nil))
        }
        return listed.sorted(by: Self.precedes).map { SessionGroup(session: $0, agents: byID[$0.id] ?? []) }
    }

    /// The sessions asking the user something, the longest wait first.
    var waiting: [ClaudeSession] {
        groups.map(\.session).filter { $0.isWaiting && !$0.isBackground }
    }

    private static func precedes(_ first: ClaudeSession, _ second: ClaudeSession) -> Bool {
        let ranks = (rank(first), rank(second))
        if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
        if first.isWaiting {
            return (first.statusSince ?? .distantPast, first.id) < (second.statusSince ?? .distantPast, second.id)
        }
        return (first.name.lowercased(), first.id) < (second.name.lowercased(), second.id)
    }

    private static func rank(_ session: ClaudeSession) -> Int {
        switch session.status {
        case .waiting: 0
        case .busy: 1
        case .unknown: 2
        case .idle: 3
        }
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

    /// Where a session is, on the right of its row.
    func state(_ session: ClaudeSession) -> String {
        switch session.status {
        case .busy: "working"
        case .waiting: "waiting"
        case .unknown: "open"
        case .idle:
            session.statusSince.map { "idle \(Self.duration(now.timeIntervalSince($0)))" } ?? "idle"
        }
    }

    /// How long it has waited for the user.
    func waited(_ session: ClaudeSession) -> String {
        Self.duration(now.timeIntervalSince(session.statusSince ?? now))
    }

    /// How long it has been open, when its file says.
    func age(_ session: ClaudeSession) -> String? {
        session.openedAt.map { Self.duration(now.timeIntervalSince($0)) }
    }

    /// The line under a waiting session's name: what it waits for, its project, its app.
    func waitingDetail(_ session: ClaudeSession) -> String {
        [session.waitingReason ?? "Waiting for you", session.folderName, session.host?.shortName]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// An unfolded session's first line: its folder, its app, when it opened, its agents.
    func details(_ session: ClaudeSession, agents count: Int) -> String {
        var parts: [String] = []
        if let cwd = session.cwd { parts.append(Self.abbreviated(cwd)) }
        if let host = session.host { parts.append(host.shortName) }
        if let opened = session.openedAt { parts.append("started \(UsageViewModel.clock(opened))") }
        parts.append(count == 0 ? "no agent" : count == 1 ? "1 agent" : "\(count) agents")
        return parts.joined(separator: " · ")
    }

    /// A path from the home folder on, as a terminal shows it.
    static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
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

    func toggleExpanded(_ session: ClaudeSession) {
        expandedSessionID = expandedSessionID == session.id ? nil : session.id
        interruptPending = nil
    }

    /// Asks before interrupting: the signal reaches the whole session, every agent of it.
    func askToInterrupt(_ session: ClaudeSession) {
        interruptPending = session.id
    }

    func cancelInterrupt() {
        interruptPending = nil
    }

    /// Interrupts a Claude Code session with the signal Ctrl+C sends in its terminal: the turn
    /// stops and every agent the session runs with it, and the session stays open, at its prompt
    /// or mid-turn alike (checked on real sessions: five signals, five survivors). Agents have no
    /// process of their own, so there is nothing narrower to stop. A command an agent had already
    /// started, a long `sleep` say, runs to its end on its own.
    func interrupt(_ session: ClaudeSession) {
        interruptPending = nil
        // Checked again now, not when the list was last read: the pid may belong to someone else.
        // Without the start time its file records, nothing proves the pid is still the session.
        guard session.pid > 1, let startedAt = session.processStartedAt, isLive(session.pid, startedAt) else {
            show("Not sent: \(session.name) has closed.")
            return
        }
        switch signal(session.pid, SIGINT) {
        case 0: show("Ctrl+C sent to \(session.name).")
        case EPERM: show("Not sent: \(session.name) runs under another user.")
        default: show("Not sent: \(session.name) has closed.")
        }
    }

    /// Brings forward the app the session runs in: its terminal, its editor.
    func focus(_ session: ClaudeSession) {
        guard let host = session.host else {
            show("Claudy cannot tell which app runs \(session.name).")
            return
        }
        if !open(host) { show("\(host.name) could not be opened.") }
    }

    /// The session a notification spoke of, if it is still open.
    func focus(sessionID: String) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        focus(session)
    }

    /// Activates the app, which brings its last window forward. Opening the session's folder with
    /// it would find the right window in an editor, but open a new one in a terminal.
    static func bringForward(_ host: HostApp) -> Bool {
        guard FileManager.default.fileExists(atPath: host.bundleURL.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: host.bundleURL, configuration: configuration)
        return true
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
