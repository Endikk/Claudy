import Foundation

/// Each kind of notification Claudy sends, each with its own switch in the menu.
enum NotificationKind: String, CaseIterable, Sendable {
    case sessionHigh, limitBeforeReset, sessionBack
    case sessionWaiting, agentSilent, agentDone

    var menuTitle: String {
        switch self {
        case .sessionHigh: "Session at 80%"
        case .limitBeforeReset: "Limit before the reset"
        case .sessionBack: "Session back"
        case .sessionWaiting: "A session waits for you"
        case .agentSilent: "An agent falls silent"
        case .agentDone: "An agent is done"
        }
    }

    var isQuota: Bool {
        switch self {
        case .sessionHigh, .limitBeforeReset, .sessionBack: true
        case .sessionWaiting, .agentSilent, .agentDone: false
        }
    }

    /// On until turned off, except an agent finishing: that happens often enough to be asked for.
    var isOnByDefault: Bool { self != .agentDone }
}

/// One notification to post: what it says, and the event it stands for.
struct Alert: Equatable, Sendable {
    let kind: NotificationKind
    /// Stable per event, so the same event is never posted twice and its banner can be taken
    /// back once it no longer holds.
    let id: String
    let title: String
    let body: String
    /// The session a click on the banner brings forward.
    var sessionID: String?
}

/// When the 5-hour session deserves a notification, worked out reading after reading. Each alert
/// goes once per session window. The first reading after launch only sets the scene: a threshold
/// already crossed then is old news.
@MainActor
struct QuotaAlerts {

    static let highMark = 0.8
    /// The limit must come at least this long before the reset to be worth a warning.
    static let warningMargin: TimeInterval = 10 * 60
    /// Before this share of the quota, a projection says more about one busy minute than about
    /// the window.
    static let projectionFloor = 0.5

    private var previous: UsageWindow?
    private var sent: Set<String> = []
    /// The window seen full, its reset, and since when it was seen full: from a reading below,
    /// or only from launch, in which case how long it lasted is not known.
    private var full: (reset: Date, since: Date, isWitnessed: Bool)?

    /// The alerts this reading of the session window calls for.
    mutating func evaluate(_ window: UsageWindow, now: Date) -> [Alert] {
        guard window.isMeasured else { return [] }
        defer { previous = window }
        var alerts: [Alert] = []

        if let back = sessionBack(window, now: now) { alerts.append(back) }
        if window.percent >= 1, window.resetDate > now, full == nil {
            full = (window.resetDate, now, previous.map { $0.percent < 1 } ?? false)
        }
        guard let previous, window.resetDate > now else { return alerts }
        let key = Self.windowKey(window.resetDate)
        let sameWindow = Self.windowKey(previous.resetDate) == key

        if sameWindow, previous.percent < Self.highMark, window.percent >= Self.highMark, window.percent < 1,
           sent.insert("high@\(key)").inserted {
            alerts.append(high(window, now: now, key: key))
        }
        if let fullAt = Self.projectedFull(window, now: now),
           fullAt < window.resetDate.addingTimeInterval(-Self.warningMargin),
           sent.insert("limit@\(key)").inserted {
            alerts.append(limit(window, fullAt: fullAt, key: key))
        }
        return alerts
    }

    /// When the window fills at the pace it has had so far; nil while too little is used to say,
    /// or once it is full.
    static func projectedFull(_ window: UsageWindow, now: Date) -> Date? {
        let spent = now.timeIntervalSince(window.windowStart)
        guard window.percent >= projectionFloor, window.percent < 1, spent > 0 else { return nil }
        let rate = window.percent / spent
        return now.addingTimeInterval((1 - window.percent) / rate)
    }

    /// Readings of one window disagree on its reset by a few seconds: five-minute buckets.
    private static func windowKey(_ reset: Date) -> Int {
        Int((reset.timeIntervalSince1970 + 150) / 300)
    }

    private func high(_ window: UsageWindow, now: Date, key: Int) -> Alert {
        let fills = Self.projectedFull(window, now: now).map { $0 < window.resetDate } ?? false
        let pace = fills ? "At this pace it fills before then." : "At this pace you stay under the limit."
        return Alert(kind: .sessionHigh, id: "high-\(key)",
                     title: "Session at \(Int(window.percent * 100))%",
                     body: "Resets at \(UsageViewModel.clock(window.resetDate)), "
                         + "in \(UsageViewModel.countdown(to: window.resetDate, now: now)). \(pace)")
    }

    private func limit(_ window: UsageWindow, fullAt: Date, key: Int) -> Alert {
        let early = AgentsViewModel.duration(window.resetDate.timeIntervalSince(fullAt))
        return Alert(kind: .limitBeforeReset, id: "limit-\(key)",
                     title: "The limit comes before the reset",
                     body: "At this pace the session is full around \(UsageViewModel.clock(fullAt)), "
                         + "\(early) before it resets at \(UsageViewModel.clock(window.resetDate)).")
    }

    /// The full window has reset: work can start again.
    private mutating func sessionBack(_ window: UsageWindow, now: Date) -> Alert? {
        guard let full, window.percent < 1 || now >= full.reset else { return nil }
        let isNewWindow = Self.windowKey(window.resetDate) != Self.windowKey(full.reset) || now >= full.reset
        guard isNewWindow else { return nil }
        self.full = nil
        var body = "The 5-hour quota reset at \(UsageViewModel.clock(full.reset))."
        if full.isWitnessed {
            body += " You were stopped for \(AgentsViewModel.duration(full.reset.timeIntervalSince(full.since)))."
        }
        return Alert(kind: .sessionBack, id: "back-\(Self.windowKey(full.reset))",
                     title: "Your session is back", body: body)
    }
}

/// When sessions and agents deserve a notification, worked out pass after pass: a session that
/// waits for the user, an agent that falls silent, an agent that ends. Each event goes once; a
/// session's waiting banner is taken back once it no longer waits, or asks something new. As
/// for the quota, the first pass only sets the scene: what was already so at launch is old news.
@MainActor
struct ActivityAlerts {

    /// Someone watching the session answers within this: no banner for them.
    static let waitingDelay: TimeInterval = 20

    private var sent: Set<String> = []
    /// Banners of sessions waiting now, by session: taken back once they stop.
    private var waitingBanners: [String: String] = [:]
    /// When each waiting session was first seen waiting, for a file that does not say since when.
    private var firstSeenWaiting: [String: Date] = [:]
    /// Agents seen at work: only those are said to be done, not the ones found finished.
    private var seenRunning: Set<String> = []
    private var hasSetTheScene = false

    mutating func evaluate(sessions: [ClaudeSession], agents: [RunningAgent],
                           now: Date) -> (post: [Alert], withdraw: [String]) {
        var post: [Alert] = []
        var withdraw: [String] = []

        let waiting = sessions.filter { $0.isWaiting && !$0.isBackground }
        let stillWaiting = Set(waiting.map(\.id))
        firstSeenWaiting = firstSeenWaiting.filter { stillWaiting.contains($0.key) }
        for session in waiting {
            let since = session.statusSince ?? firstSeenWaiting[session.id] ?? now
            firstSeenWaiting[session.id] = firstSeenWaiting[session.id] ?? since
            let id = "waiting-\(session.id)-\(Int(since.timeIntervalSince1970))"
            guard now.timeIntervalSince(since) >= Self.waitingDelay, sent.insert(id).inserted else { continue }
            // A new question replaces the last one: its banner goes.
            if let previous = waitingBanners[session.id] { withdraw.append(previous) }
            waitingBanners[session.id] = id
            post.append(Alert(kind: .sessionWaiting, id: id, title: "\(session.name) is waiting for you",
                              body: Self.waitingBody(session), sessionID: session.id))
        }
        withdraw += waitingBanners.filter { !stillWaiting.contains($0.key) }.values.sorted()
        waitingBanners = waitingBanners.filter { stillWaiting.contains($0.key) }

        // A program's own session has nobody at it: its agents are not worth a banner either.
        let unattended = Set(sessions.filter(\.isBackground).map(\.id))
        for agent in agents where !unattended.contains(agent.sessionID) {
            switch agent.status(at: now) {
            case .stalled:
                let id = "silent-\(agent.id)-\(Int(agent.lastActivity.timeIntervalSince1970))"
                guard sent.insert(id).inserted else { continue }
                post.append(Alert(kind: .agentSilent, id: id, title: "An agent is silent",
                                  body: "\u{201C}\(agent.title)\u{201D} has said nothing for "
                                      + "\(AgentsViewModel.duration(agent.silence(at: now))). \(agent.sessionName)",
                                  sessionID: agent.sessionID))
            case .done:
                let id = "done-\(agent.id)"
                guard seenRunning.contains(agent.id), sent.insert(id).inserted else { continue }
                post.append(Alert(kind: .agentDone, id: id, title: "Agent done",
                                  body: Self.doneBody(agent), sessionID: agent.sessionID))
            case .working, .idle:
                break
            }
            if !agent.isFinished { seenRunning.insert(agent.id) }
        }
        let listed = Set(agents.map(\.id))
        seenRunning = seenRunning.filter { listed.contains($0) }
        guard hasSetTheScene else {
            // Marked as said, not said: nothing in the first pass is news.
            hasSetTheScene = true
            waitingBanners = [:]
            return ([], [])
        }
        return (post, withdraw)
    }

    private static func waitingBody(_ session: ClaudeSession) -> String {
        [session.waitingReason ?? "Waiting for you", session.folderName, session.host?.shortName]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private static func doneBody(_ agent: RunningAgent) -> String {
        let took = AgentsViewModel.duration(agent.lastActivity.timeIntervalSince(agent.startedAt))
        let head = "\u{201C}\(agent.title)\u{201D} in \(took)."
        return agent.editedFiles.isEmpty ? head : head + " Wrote " + agent.editedFiles.joined(separator: ", ")
    }
}
