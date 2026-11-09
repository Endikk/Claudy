import SwiftUI

/// One agent in the card's Agents tab, on two lines: its Claudy, what it was asked and for how
/// long; then its track over the last ten minutes and where it is. A click unfolds it: whose
/// agent it is, what it wrote, its last calls, and the way to interrupt its session.
struct AgentRow: View {
    let agent: RunningAgent
    let isExpanded: Bool
    @EnvironmentObject private var viewModel: AgentsViewModel
    @State private var isHovered = false

    private var status: RunningAgent.Status { agent.status(at: viewModel.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if isExpanded {
                AgentDetails(agent: agent, status: status)
                    .padding(.leading, 27 * ClaudyTyping.aspectRatio + 8)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(isExpanded ? 0.06 : isHovered ? 0.035 : 0))
        )
        .padding(.horizontal, -6)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 8) {
            AgentClaudy(agent: agent, status: status, height: 27)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(agent.title)
                        .font(Theme.Font.label(11, .medium))
                        .foregroundStyle(.primary.opacity(status == .done ? 0.55 : 0.86))
                        .lineLimit(1)
                    if viewModel.spansSessions {
                        Text(agent.sessionName)
                            .font(Theme.Font.label(9, .semibold))
                            .foregroundStyle(.primary.opacity(0.45))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.primary.opacity(0.07)))
                    }
                    Spacer(minLength: 0)
                    Text(viewModel.elapsed(agent))
                        .font(Theme.Font.value(10, .semibold))
                        .foregroundStyle(.primary.opacity(0.5))
                        .fixedSize()
                }
                HStack(spacing: 8) {
                    AgentTrack(slots: agent.track(at: viewModel.now))
                        .frame(height: AgentTrack.height)
                    AgentState(agent: agent, status: status, size: 10, maxWidth: 110)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleExpanded(agent) }
        .help(isExpanded ? "Click to fold" : viewModel.details(agent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentClaudy.spoken(agent, status: status))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Folds the agent" : "Unfolds the agent: session, files written, interrupt")
    }
}

/// What a row unfolds to. The interrupt is two clicks: the first one asks, naming the session and
/// saying what the signal does, since it reaches every agent of that session.
struct AgentDetails: View {
    let agent: RunningAgent
    let status: RunningAgent.Status
    @EnvironmentObject private var viewModel: AgentsViewModel

    private var isConfirming: Bool { viewModel.interruptPending == agent.sessionID }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            line("\(agent.sessionName) · \(agent.actionCount) actions · started \(UsageViewModel.clock(agent.startedAt))")
            if !agent.editedFiles.isEmpty {
                line("Wrote " + agent.editedFiles.joined(separator: ", "), tint: Theme.Accent.coral.color.opacity(0.9))
                    .lineLimit(2)
            }
            let calls = viewModel.lastCalls(agent)
            if !calls.isEmpty {
                line("Last: " + calls.joined(separator: " · "), truncation: .tail)
                    .lineLimit(1)
            }
            if status != .done {
                interruptRow
                    .padding(.top, 2)
            }
        }
        .font(Theme.Font.label(10, .medium))
    }

    private func line(_ text: String, tint: Color = .primary.opacity(0.55),
                      truncation: Text.TruncationMode = .middle) -> some View {
        Text(text)
            .foregroundStyle(tint)
            .truncationMode(truncation)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var interruptRow: some View {
        if isConfirming {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sends Ctrl+C to \(agent.sessionName): every agent of that session stops. A session sitting at its prompt closes instead.")
                    .foregroundStyle(.primary.opacity(0.65))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel", action: viewModel.cancelInterrupt)
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Interrupt \(agent.sessionName)") { viewModel.interrupt(agent) }
                        .buttonStyle(QuietButtonStyle(tint: Theme.danger))
                        .keyboardShortcut(.defaultAction)
                }
            }
        } else {
            HStack {
                Spacer(minLength: 0)
                Button {
                    viewModel.askToInterrupt(agent)
                } label: {
                    Label("Interrupt session", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(QuietButtonStyle(tint: Theme.danger))
                .help("Sends Ctrl+C to the Claude Code session that runs this agent")
            }
        }
    }
}

/// A small text button on the card's glass: a tinted capsule that only fills when pressed.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color = .primary.opacity(0.7)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.label(10, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.28 : 0.12)))
            .contentShape(Capsule())
    }
}

/// An agent's own Claudy: its own colour, typing while it works, grey and still once it falls
/// silent, faded when it is done.
struct AgentClaudy: View {
    let agent: RunningAgent
    let status: RunningAgent.Status
    let height: CGFloat
    @EnvironmentObject private var viewModel: AgentsViewModel

    var body: some View {
        ClaudyTyping(tint: viewModel.tint(of: agent), isTyping: status == .working)
            .frame(width: height * ClaudyTyping.aspectRatio, height: height)
            .opacity(status == .done ? 0.6 : 1)
    }

    /// What VoiceOver reads for a row: the drawing says nothing to it.
    static func spoken(_ agent: RunningAgent, status: RunningAgent.Status) -> String {
        let state = switch status {
        case .working: "working on \(agent.touching)"
        case .idle: "waiting"
        case .stalled: "silent for a while"
        case .done: "done"
        }
        return "\(agent.title), \(agent.sessionName), \(state)"
    }
}

/// Where an agent is, on the right of its row: the file it touches, in coral while it writes it;
/// its silence in amber once it is worth a look; "done" and what it wrote, in sage.
struct AgentState: View {
    let agent: RunningAgent
    let status: RunningAgent.Status
    let size: CGFloat
    var maxWidth: CGFloat = 96
    @EnvironmentObject private var viewModel: AgentsViewModel

    var body: some View {
        Text(viewModel.state(agent))
            .font(Theme.Font.label(size, .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
            // Its own width up to the cap, never more: the title takes what is left.
            .frame(maxWidth: maxWidth, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var color: Color {
        switch status {
        case .done: Theme.Accent.sage.color
        case .stalled: Theme.Accent.amber.color
        case .working where agent.isWriting: Theme.Accent.coral.color
        case .working, .idle: .primary.opacity(0.42)
        }
    }
}

/// What the tracks mean, in the section header: their reach, and the colour of a write.
struct AgentTrackLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Theme.Accent.coral.color)
                .frame(width: 2, height: 7)
            Text("writes")
                .microLabel(0.4)
            Text("· 10 min")
                .microLabel(0.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tracks cover the last ten minutes; writes are drawn in coral")
    }
}

/// An agent's last ten minutes, one bar per fifteen seconds: a write in coral and tall, any other
/// call a short grey tick. A burst of edits stands out; a flat track is a silent agent.
struct AgentTrack: View {
    let slots: [AgentTrackSlot]

    static let height: CGFloat = 14
    /// Share of a slot the bar fills; the rest is the gap to the next one.
    private static let barShare: CGFloat = 0.62
    private static let editBase: CGFloat = 6
    private static let editStep: CGFloat = 4
    private static let otherBase: CGFloat = 2
    private static let otherStep: CGFloat = 1.5
    private static let otherCap: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                         with: .color(.primary.opacity(0.1)))
            guard !slots.isEmpty else { return }
            let step = size.width / CGFloat(slots.count)
            let width = max(1.2, step * Self.barShare)
            for (index, slot) in slots.enumerated() {
                let x = CGFloat(index) * step + (step - width) / 2
                if slot.edits > 0 {
                    let height = min(size.height, Self.editBase + CGFloat(slot.edits) * Self.editStep)
                    context.fill(Path(CGRect(x: x, y: size.height - height, width: width, height: height)),
                                 with: .color(Theme.Accent.coral.color))
                } else if slot.others > 0 {
                    let height = min(Self.otherCap, Self.otherBase + CGFloat(slot.others) * Self.otherStep)
                    context.fill(Path(CGRect(x: x, y: size.height - height, width: width, height: height)),
                                 with: .color(.primary.opacity(0.32)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
