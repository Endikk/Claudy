import SwiftUI

/// One agent in the card's Agents tab, on two lines: its Claudy, what it was asked and for how
/// long; then its track over the last ten minutes and the file it is touching.
struct AgentRow: View {
    let agent: RunningAgent
    @EnvironmentObject private var viewModel: AgentsViewModel

    private var status: RunningAgent.Status { agent.status(at: viewModel.now) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AgentClaudy(agent: agent, status: status, height: 27)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(agent.title)
                        .font(Theme.Font.label(11, .medium))
                        .foregroundStyle(.primary.opacity(0.86))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(viewModel.elapsed(agent))
                        .font(Theme.Font.value(10, .semibold))
                        .foregroundStyle(.primary.opacity(0.5))
                        .fixedSize()
                }
                HStack(spacing: 8) {
                    AgentTrack(slots: agent.track(at: viewModel.now))
                        .frame(height: AgentTrack.height)
                    AgentTouching(agent: agent, status: status, size: 10)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help(viewModel.details(agent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentClaudy.spoken(agent, status: status))
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
        case .done: "done"
        }
        return "\(agent.title), \(agent.sessionName), \(state)"
    }
}

/// The file an agent is touching, in coral while it writes it; "done" once it has finished.
struct AgentTouching: View {
    let agent: RunningAgent
    let status: RunningAgent.Status
    let size: CGFloat

    private static let maxWidth: CGFloat = 96

    var body: some View {
        Text(status == .done ? "done" : agent.touching)
            .font(Theme.Font.label(size, .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
            // Its own width up to the cap, never more: the title takes what is left.
            .frame(maxWidth: Self.maxWidth, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var color: Color {
        if status == .done { return Theme.Accent.sage.color }
        if agent.isWriting && status == .working { return Theme.Accent.coral.color }
        return .primary.opacity(0.42)
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
