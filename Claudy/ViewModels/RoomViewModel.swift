import AppKit
import Combine
import SwiftUI

/// Drives the agent room: one room per project, the sessions open in it as Claudy at the centre
/// desk, their agents at the desks around. It reads what `AgentsViewModel` already knows and
/// adds what a room needs: who sits where, who is walking, who is done and resting on the sofa,
/// which area is changing work.
@MainActor
final class RoomViewModel: ObservableObject {

    /// The sessions open in one folder, and every agent they run.
    struct Project: Identifiable, Equatable {
        let id: String
        let sessions: [ClaudeSession]
        let agents: [RunningAgent]

        /// The session that speaks for the project: the one waiting first, as the card sorts them.
        var lead: ClaudeSession? { sessions.first }
        var isWaiting: Bool { sessions.contains { $0.isWaiting && !$0.isBackground } }
        var runningCount: Int { agents.filter { !$0.isFinished }.count }
    }

    private struct Walk {
        let route: [CGPoint]
        let startedAt: Date

        var duration: TimeInterval { TimeInterval(RoomGeometry.length(of: route) / RoomGeometry.pace) }

        func position(at date: Date) -> CGPoint? {
            let elapsed = date.timeIntervalSince(startedAt)
            guard elapsed < duration else { return nil }
            return RoomGeometry.point(on: route, at: CGFloat(max(0, elapsed)) * RoomGeometry.pace)
        }
    }

    private struct Flip {
        let from: WorkFamily?
        let startedAt: Date
    }

    /// A Claudy on its way out: it is no longer listed, so it carries what the scene needs.
    private struct Leave {
        let project: String
        let tint: Color
        let walk: Walk
    }

    /// The rooms on show: every project with a session open, less the ones put away.
    @Published private(set) var projects: [Project] = []
    /// The rooms put away, in the order their projects are listed: the menu brings one back.
    @Published private(set) var hidden: [String] = []
    @Published var selectedID: String?
    @Published var isSummaryOpen = false
    /// The agent whose card is open over the room.
    @Published var selectedAgentID: String?
    /// Every project at once, each a small room, instead of one room.
    @Published var isOverview = false

    /// The room is on screen. Opening it seats everyone at once: nobody walks in for a room that
    /// was already at work.
    var isVisible = false {
        didSet {
            guard isVisible != oldValue else { return }
            walks = [:]
            flips = [:]
            leaving = [:]
            if isVisible { sync() }
        }
    }

    /// An agent that just crossed the room stays put this long, whatever its next calls are.
    static let settleTime: TimeInterval = 20
    /// How long an area takes to change work.
    static let flipTime: TimeInterval = 0.7
    /// How long a screen lights up when its agent's work changes.
    static let flashTime: TimeInterval = 0.4
    /// Past this, the session's last call no longer says what it is doing.
    static let freshCall: TimeInterval = 120

    static let hiddenKey = "roomHidden"

    private let agents: AgentsViewModel
    private let store: UserDefaults
    /// Every project with a session open, put away or not.
    private var open: [Project] = []
    private var hiddenIDs: Set<String>
    private let clock: () -> Date
    private let reducesMotion: () -> Bool
    private var plans: [String: RoomPlan] = [:]
    /// Who sits where on each project's sofa.
    private var lounges: [String: [String: Int]] = [:]
    /// Agents that were done with no place left on the sofa: they went out and are not shown again.
    private var departed: Set<String> = []
    private var leaving: [String: Leave] = [:]
    private var walks: [String: Walk] = [:]
    private var flips: [String: [Int: Flip]] = [:]
    private var lastMove: [String: Date] = [:]
    private var lastWork: [String: AgentWork] = [:]
    private var flashes: [String: Date] = [:]
    private var tints: [String: Color] = [:]
    private var subscription: AnyCancellable?

    init(agents: AgentsViewModel, store: UserDefaults = .standard, clock: @escaping () -> Date = { Date() },
         reducesMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.agents = agents
        self.store = store
        hiddenIDs = Set(store.stringArray(forKey: Self.hiddenKey) ?? [])
        self.clock = clock
        self.reducesMotion = reducesMotion
        subscription = agents.$agents.combineLatest(agents.$sessions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
    }

    var selected: Project? {
        projects.first { $0.id == selectedID } ?? projects.first
    }

    /// The agent whose card is open, while it is still listed in the room on screen.
    var selectedAgent: RunningAgent? {
        selected?.agents.first { $0.id == selectedAgentID }
    }

    /// Shows the room of the project an agent works in, its card open.
    func show(agent id: String) {
        guard let project = open.first(where: { project in project.agents.contains { $0.id == id } }) else { return }
        if hiddenIDs.contains(project.id) { restore(project.id) }
        selectedID = project.id
        selectedAgentID = id
        isOverview = false
        isSummaryOpen = false
    }

    /// Enters the room of one project.
    func enter(_ projectID: String) {
        selectedID = projectID
        isOverview = false
        selectedAgentID = nil
    }

    /// Puts a room away: it leaves the list until it is asked back, or until its sessions close.
    func hide(_ projectID: String) {
        hiddenIDs.insert(projectID)
        store.set(hiddenIDs.sorted(), forKey: Self.hiddenKey)
        sync()
    }

    /// Brings back a room that was put away.
    func restore(_ projectID: String) {
        hiddenIDs.remove(projectID)
        store.set(hiddenIDs.sorted(), forKey: Self.hiddenKey)
        sync()
    }

    func toggleAgent(_ id: String) {
        selectedAgentID = selectedAgentID == id ? nil : id
        if selectedAgentID != nil { isSummaryOpen = false }
    }

    private var animates: Bool { isVisible && !reducesMotion() }

    // MARK: - Seating

    /// Reads the sessions and agents again and seats everyone.
    func sync() {
        let now = clock()
        open = Self.projects(from: agents.groups)
        // A room put away is forgotten once its sessions close: the folder opened again is a
        // room again. Nothing is forgotten on an empty reading, the first one at launch.
        if !open.isEmpty {
            let stillOpen = hiddenIDs.intersection(open.map(\.id))
            if stillOpen != hiddenIDs {
                hiddenIDs = stillOpen
                store.set(hiddenIDs.sorted(), forKey: Self.hiddenKey)
            }
        }
        let found = open.filter { !hiddenIDs.contains($0.id) }
        let away = open.map(\.id).filter(hiddenIDs.contains)
        if away != hidden { hidden = away }
        // Seats are not published one by one: every pass tells the views to read them again.
        objectWillChange.send()
        if found != projects { projects = found }
        if selectedID == nil || !found.contains(where: { $0.id == selectedID }) { selectedID = found.first?.id }

        let listed = Set(found.flatMap(\.agents).map(\.id))
        seeOut(listed: listed, at: now)
        walks = walks.filter { listed.contains($0.key) && $0.value.position(at: now) != nil }
        leaving = leaving.filter { $0.value.walk.position(at: now) != nil }
        departed = departed.filter { listed.contains($0) }
        lastMove = lastMove.filter { listed.contains($0.key) }
        lastWork = lastWork.filter { listed.contains($0.key) }
        flashes = flashes.filter { listed.contains($0.key) }
        tints = tints.filter { listed.contains($0.key) }
        let shown = Set(found.map(\.id))
        plans = plans.filter { shown.contains($0.key) }
        flips = flips.filter { shown.contains($0.key) }
        lounges = lounges.filter { shown.contains($0.key) }
        if let selectedAgentID, !listed.contains(selectedAgentID) { self.selectedAgentID = nil }
        if found.count < 2 { isOverview = false }

        for project in found {
            seat(project, at: now)
        }
    }

    /// An agent that left the list while it sat on the sofa gets up and goes out by the door.
    private func seeOut(listed: Set<String>, at now: Date) {
        for (project, sofa) in lounges {
            for (id, slot) in sofa where !listed.contains(id) {
                lounges[project]?[id] = nil
                guard animates else { continue }
                leaving[id] = Leave(project: project, tint: tints[id] ?? Theme.idle,
                                    walk: Walk(route: RoomGeometry.route(fromSofa: slot), startedAt: now))
            }
        }
    }

    private func seat(_ project: Project, at now: Date) {
        let isNew = plans[project.id] == nil
        let before = plans[project.id] ?? RoomPlan()
        var plan = before
        plan.seat(project.agents.filter { !$0.isFinished }.map { agent in
            let isSettling = lastMove[agent.id].map { now.timeIntervalSince($0) < Self.settleTime } ?? false
            return (agent.id, isSettling ? nil : agent.family(at: now))
        })
        plans[project.id] = plan

        let moves = animates && !isNew
        for agent in project.agents {
            tints[agent.id] = agents.tint(of: agent)
            let work = agent.lastAction?.work
            if let known = lastWork[agent.id], known != work { flashes[agent.id] = now }
            lastWork[agent.id] = work

            if agent.isFinished {
                rest(agent, in: project.id, from: before.seats[agent.id], moves: moves, at: now)
                continue
            }
            guard let seat = plan.seats[agent.id], seat != before.seats[agent.id] else { continue }
            lastMove[agent.id] = now
            if moves {
                walks[agent.id] = Walk(route: RoomGeometry.route(from: before.seats[agent.id], to: seat), startedAt: now)
            }
        }
        guard moves else { return }
        for zone in plan.families.indices where plan.families[zone] != before.families[zone] {
            flips[project.id, default: [:]][zone] = Flip(from: before.families[zone], startedAt: now)
        }
    }

    /// An agent that is done leaves its desk for the sofa, where it stays until it leaves the
    /// list. With the sofa full it goes straight out by the door.
    private func rest(_ agent: RunningAgent, in project: String, from desk: RoomSeat?, moves: Bool, at now: Date) {
        guard lounges[project]?[agent.id] == nil, !departed.contains(agent.id) else { return }
        let taken = Set((lounges[project] ?? [:]).values)
        if let slot = (0..<RoomGeometry.sofaSeats).first(where: { !taken.contains($0) }) {
            lounges[project, default: [:]][agent.id] = slot
            if moves, let desk {
                walks[agent.id] = Walk(route: RoomGeometry.route(from: desk, toSofa: slot), startedAt: now)
            }
        } else {
            departed.insert(agent.id)
            if moves, let desk {
                leaving[agent.id] = Leave(project: project, tint: agents.tint(of: agent),
                                          walk: Walk(route: RoomGeometry.routeOut(from: desk), startedAt: now))
            }
        }
    }

    /// One project per folder, in the order the card lists their sessions.
    static func projects(from groups: [SessionGroup]) -> [Project] {
        var order: [String] = []
        var sessions: [String: [ClaudeSession]] = [:]
        var agents: [String: [RunningAgent]] = [:]
        for group in groups {
            let name = group.session.folderName ?? group.session.name
            if sessions[name] == nil { order.append(name) }
            sessions[name, default: []].append(group.session)
            agents[name, default: []] += group.agents
        }
        return order.map { name in
            Project(id: name, sessions: sessions[name] ?? [],
                    agents: (agents[name] ?? []).sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) })
        }
    }

    // MARK: - The scene

    /// Where a seat is in a scene's list of desks.
    static func deskIndex(of seat: RoomSeat) -> Int {
        seat.zone * RoomPlan.seatsPerZone + seat.index
    }

    /// Where an agent of the room on screen is, in the scene's units: the top left corner of its
    /// desk, or its place on the sofa. `nil` while it walks or once it has gone out.
    func place(of agentID: String) -> CGPoint? {
        guard let project = selected, walks[agentID]?.position(at: clock()) == nil else { return nil }
        if let slot = lounges[project.id]?[agentID] {
            let seat = RoomGeometry.sofa(slot)
            return CGPoint(x: seat.x - 8, y: seat.y - CGFloat(RoomSprite.rows))
        }
        return plans[project.id]?.seats[agentID].map(RoomGeometry.desk)
    }

    /// The room of a project as it stands at `date`. `quota` is the session quota, 0…1.
    /// `withHelp` is for the pass that builds what a pointer is told: the drawing does without.
    func scene(for project: Project?, at date: Date, quota: Double?, withHelp: Bool = true) -> RoomScene {
        let plan = project.flatMap { plans[$0.id] } ?? RoomPlan()
        let sofa = project.flatMap { lounges[$0.id] } ?? [:]
        let turning = project.flatMap { flips[$0.id] } ?? [:]
        let zones = plan.families.indices.map { zone -> RoomZone in
            let progress = turning[zone].map { date.timeIntervalSince($0.startedAt) / Self.flipTime } ?? 1
            let isTurning = progress < 1
            return RoomZone(family: isTurning ? turning[zone]?.from : plan.families[zone],
                            incoming: plan.families[zone], progress: isTurning ? max(0, progress) : 0,
                            count: plan.count(in: zone))
        }
        var scene = RoomScene(zones: zones,
                              desks: [RoomOccupant?](repeating: nil, count: RoomPlan.homes.count * RoomPlan.seatsPerZone),
                              walkers: [], chief: chief(of: project, quota: quota, at: date))
        for agent in project?.agents ?? [] {
            let tint = agents.tint(of: agent)
            let glyph = agent.lastAction.map { RoomGlyph.symbol(for: $0.work) }
            if let position = walks[agent.id]?.position(at: date) {
                scene.walkers.append(RoomWalker(id: agent.id, position: position, tint: tint,
                                                glyph: agent.isFinished ? RoomGlyph.done : glyph))
            } else if let slot = sofa[agent.id] {
                scene.loungers.append(RoomLounger(id: agent.id, slot: slot, tint: tint,
                                                  help: withHelp ? help(for: agent) : ""))
            } else if let seat = plan.seats[agent.id] {
                let index = Self.deskIndex(of: seat)
                scene.desks[index] = occupant(agent, glyph: glyph, at: date, withHelp: withHelp)
                if agent.id == selectedAgentID { scene.selectedDesk = index }
            }
        }
        for (id, leave) in leaving where leave.project == project?.id {
            guard let position = leave.walk.position(at: date) else { continue }
            scene.walkers.append(RoomWalker(id: id, position: position, tint: leave.tint, glyph: nil))
        }
        return scene
    }

    private func occupant(_ agent: RunningAgent, glyph: String?, at date: Date, withHelp: Bool) -> RoomOccupant {
        let state: RoomOccupant.State
        switch agent.status(at: date) {
        case .working: state = .working
        case .idle: state = .idle
        case .stalled: state = .stalled
        case .done: state = .done
        }
        let isFlashing = flashes[agent.id].map { date.timeIntervalSince($0) < Self.flashTime } ?? false
        let phase = agent.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFF }
        return RoomOccupant(id: agent.id, tint: agents.tint(of: agent), state: state, glyph: glyph ?? RoomGlyph.thinking,
                            phase: phase, isFlashing: isFlashing, help: withHelp ? help(for: agent) : "")
    }

    private func help(for agent: RunningAgent) -> String {
        var lines = [agent.title, "\(agents.state(agent).capitalizedFirst) · \(agent.workLabel) · \(agents.elapsed(agent))"]
        if !agent.editedFiles.isEmpty { lines.append("Wrote: " + agent.editedFiles.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }

    /// Claudy at the centre desk. While the session works, its first screen shows its own last
    /// call when that call is fresh; otherwise that it runs agents, or that it thinks.
    private func chief(of project: Project?, quota: Double?, at date: Date) -> RoomChief {
        guard let project, let lead = project.lead else { return RoomChief(state: .away, glyph: nil, quota: quota) }
        switch lead.status {
        case .waiting:
            let reason = lead.waitingReason.map { ": \($0.lowercased())" } ?? ""
            return RoomChief(state: .waiting, glyph: RoomGlyph.waiting, quota: quota,
                             help: "\(lead.name) is waiting for you\(reason)")
        case .busy:
            let own = lead.lastAction.flatMap { date.timeIntervalSince($0.date) < Self.freshCall ? $0 : nil }
            let isDelegating = project.runningCount > 0 && (own == nil || own?.work == .delegating)
            let glyph = isDelegating ? RoomGlyph.delegating : own.map { RoomGlyph.symbol(for: $0.work) } ?? RoomGlyph.thinking
            let doing = isDelegating ? "running its agents"
                : own.map { [$0.work.label, $0.detail ?? $0.file].compactMap { $0 }.joined(separator: " · ") } ?? "thinking"
            return RoomChief(state: .working, glyph: glyph, quota: quota, help: "\(lead.name) · \(doing)")
        case .idle, .unknown:
            return RoomChief(state: .idle, glyph: nil, quota: quota, help: "\(lead.name) is at its prompt")
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
