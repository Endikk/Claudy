import SwiftUI

/// The agent room's window: the card's glass around the open space of one project. On top, the
/// projects with a session open; underneath, the session's line as the Sessions tab writes it.
struct RoomView: View {
    @ObservedObject var room: RoomViewModel
    let close: () -> Void
    @EnvironmentObject private var agents: AgentsViewModel
    /// Noon until told otherwise: the room is first seen in daylight.
    @AppStorage(RoomLight.storageKey) private var lightChoice = RoomLight.noon.rawValue

    private var light: RoomLight { RoomLight(rawValue: lightChoice) ?? .noon }

    var body: some View {
        VStack(spacing: Theme.Metric.gap) {
            header
            RoomCanvas(room: room, light: light)
                .overlay(alignment: .topLeading) { summary }
                .overlay(alignment: .topLeading) { agentCard }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.tileCorner, style: .continuous))
            footer
        }
        .padding(Theme.Metric.panelPadding)
        .cardSurface(corner: Theme.Metric.cardCorner)
        .background(CardShadow(corner: Theme.Metric.cardCorner))
        .padding(Theme.Metric.shadowInset)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Agents")
                .font(Theme.Font.label(15, .semibold))
                .foregroundStyle(.primary)
            if !room.projects.isEmpty {
                RoomSwitcher(room: room)
            }
            Spacer(minLength: 8)
            lightMenu
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close the room")
            .accessibilityLabel("Close")
        }
        .frame(height: 44)
        .padding(.horizontal, 6)
    }

    /// The hour the room is lit for: the Mac's clock, or one held still.
    private var lightMenu: some View {
        Menu {
            ForEach(RoomLight.allCases) { choice in
                Button {
                    lightChoice = choice.rawValue
                } label: {
                    if choice == light {
                        Label(choice.title, systemImage: "checkmark")
                    } else {
                        Text(choice.title)
                    }
                }
            }
        } label: {
            Label(light.title, systemImage: light == .clock ? "clock" : "sun.max")
                .font(Theme.Font.label(11, .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("The hour the room is lit for")
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if let project = room.selected, let lead = project.lead {
                Circle()
                    .fill(dot(of: lead))
                    .frame(width: 7, height: 7)
                Text(lead.name)
                    .font(Theme.Font.label(13, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if lead.name != project.id {
                    Text(project.id)
                        .font(Theme.Font.label(11, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                let tally = RoomTally(project, at: agents.now)
                if tally.working > 0 { RoomBadge(text: "\(tally.working) working", ink: .coral) }
                if tally.waiting > 0 { RoomBadge(text: "\(tally.waiting) waiting", ink: .amber) }
                if tally.stuck > 0 { RoomBadge(text: "\(tally.stuck) stuck", ink: .danger) }
                if tally.done > 0 { RoomBadge(text: "\(tally.done) done", ink: .positive) }
                if let age = agents.age(lead) {
                    Text(age)
                        .font(Theme.Font.value(11, .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No Claude Code session open")
                    .font(Theme.Font.label(12, .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 8)
    }

    private func dot(of session: ClaudeSession) -> Color {
        switch session.status {
        case .busy: Theme.Accent.coral.color
        case .waiting: Theme.Accent.amber.color
        case .idle, .unknown: Theme.idle
        }
    }

    // MARK: - Summary

    /// Beside the desk of the agent a click chose.
    @ViewBuilder
    private var agentCard: some View {
        if let agent = room.selectedAgent, let place = room.place(of: agent.id) {
            let origin = RoomAgentCard.origin(beside: CGPoint(x: place.x * RoomCanvas.unit, y: place.y * RoomCanvas.unit),
                                              in: RoomCanvas.size)
            RoomAgentCard(agent: agent) { room.selectedAgentID = nil }
                .offset(x: origin.x, y: origin.y)
                .transition(.opacity)
        }
    }

    /// Under Claudy's desk, between the two lower areas.
    @ViewBuilder
    private var summary: some View {
        if room.isSummaryOpen, let project = room.selected {
            RoomSummary(project: project)
                .frame(width: 360)
                .offset(x: 300, y: 322)
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        }
    }
}

/// How many agents of a project are in each state, and how many of its sessions wait.
struct RoomTally: Equatable {
    var working = 0
    var stuck = 0
    var done = 0
    var waiting = 0
    /// The longest silence among the stuck ones.
    var longestSilence: TimeInterval = 0

    init(_ project: RoomViewModel.Project, at now: Date) {
        for agent in project.agents {
            switch agent.status(at: now) {
            case .working: working += 1
            case .stalled:
                stuck += 1
                longestSilence = max(longestSilence, agent.silence(at: now))
            case .done: done += 1
            case .idle: break
            }
        }
        waiting = project.sessions.filter { $0.isWaiting && !$0.isBackground }.count
    }
}

/// The projects with a session open, as the card's tabs: a capsule of glass, the chosen one a
/// brighter lens, a count beside each name only when something happens there.
private struct RoomSwitcher: View {
    @ObservedObject var room: RoomViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(room.projects) { project in
                    segment(project)
                }
            }
            .padding(3)
            .modifier(CapsuleGlass())
        }
        .frame(maxWidth: 620)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segment(_ project: RoomViewModel.Project) -> some View {
        let isSelected = room.selected?.id == project.id
        return HStack(spacing: 6) {
            Text(project.id)
                .font(Theme.Font.label(12, .semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
            if project.isWaiting {
                CountBadge(value: project.sessions.filter(\.isWaiting).count, ink: .amber, systemImage: "hand.raised.fill")
            } else if project.runningCount > 0 {
                CountBadge(value: project.runningCount, ink: .coral)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.Metric.tabHeight)
        .background {
            if isSelected {
                Capsule()
                    .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.85))
                    .overlay(Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.2 : 0.6), lineWidth: 0.5))
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(Theme.Motion.mode) { room.selectedID = project.id }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A count with its word, in a capsule washed with its colour.
struct RoomBadge: View {
    let text: String
    let ink: Theme.Ink
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(Theme.Font.value(11, .semibold))
            .foregroundStyle(ink.color(scheme))
            .padding(.horizontal, 7)
            .frame(minHeight: 18)
            .background(Capsule().fill(ink.color(.dark).opacity(scheme == .dark ? 0.22 : 0.16)))
    }
}
