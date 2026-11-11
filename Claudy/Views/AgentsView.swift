import SwiftUI

/// The agents in short, for the menu bar popover and the open island: one line each with its
/// Claudy, what it was asked, for how long, and where it is. The tracks and the details stay in
/// the card's Sessions tab, one click away.
struct AgentsShortList: View {
    @EnvironmentObject private var viewModel: AgentsViewModel
    @EnvironmentObject private var usage: UsageViewModel
    var limit = 4
    /// The island is wide enough for the running time too; the popover keeps the title whole.
    var showsElapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Agents")
                    .sectionLabel()
                CountBadge(value: viewModel.runningCount, ink: .coral)
            }
            ForEach(viewModel.agents.prefix(limit)) { agent in
                AgentShortRow(agent: agent, showsElapsed: showsElapsed)
            }
            if viewModel.agents.count > limit {
                Button {
                    usage.place(.widget)
                } label: {
                    Text("+\(viewModel.agents.count - limit) more · open the widget")
                        .font(Theme.Font.label(11, .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, AgentShortRow.claudyHeight * ClaudyTyping.aspectRatio + AgentShortRow.spacing)
                .help("The widget lists every agent, with its track and the way to stop it")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.accordion, value: viewModel.agents.map(\.id))
    }
}

struct AgentShortRow: View {
    let agent: RunningAgent
    var showsElapsed = false
    @EnvironmentObject private var viewModel: AgentsViewModel

    /// Half a point per sprite pixel: whole device pixels on Retina, as in the menu bar.
    static let claudyHeight: CGFloat = 13.5
    static let spacing: CGFloat = 7

    var body: some View {
        let status = agent.status(at: viewModel.now)
        HStack(spacing: Self.spacing) {
            AgentClaudy(agent: agent, status: status, height: Self.claudyHeight)
            Text(agent.title)
                .font(Theme.Font.label(11, .medium))
                .foregroundStyle(.primary.opacity(status == .done ? 0.5 : 0.82))
                .lineLimit(1)
            Spacer(minLength: 6)
            if showsElapsed {
                Text(viewModel.elapsed(agent))
                    .font(Theme.Font.value(11, .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            AgentState(agent: agent, status: status, size: 9.5, maxWidth: showsElapsed ? 110 : 96)
        }
        .contentShape(Rectangle())
        .help(viewModel.details(agent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentClaudy.spoken(agent, status: status))
    }
}

/// At rest, in the island's left ear beside Claudy: how many agents are running, in the colour
/// of the one at work. The ear is 13 points tall: a figure reads there, a second mascot did not.
struct AgentsEarBadge: View {
    @EnvironmentObject private var viewModel: AgentsViewModel

    var body: some View {
        let count = viewModel.runningCount
        if count > 0, let lead = viewModel.lead {
            Text("\(count)")
                .font(Theme.Font.value(11, .semibold))
                .foregroundStyle(viewModel.tint(of: lead))
                .help(count == 1 ? "1 agent running" : "\(count) agents running")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(count == 1 ? "1 agent running" : "\(count) agents running")
        }
    }
}
