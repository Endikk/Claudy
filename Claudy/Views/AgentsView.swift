import SwiftUI

/// The Agents tab: what Claude Code launched in its open sessions, and what each one is doing.
///
/// Built like the ports annex. The empty state is the common case, and good news.
struct AgentsView: View {
    @EnvironmentObject private var viewModel: AgentsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.agents.isEmpty {
                Text("No agent running.")
                    .font(Theme.Font.label(11, .medium))
                    .foregroundStyle(.primary.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                Text("Agents launched by Claude")
                    .microLabel(0.55)
                    .padding(.bottom, 4)
                ForEach(viewModel.agents) { agent in
                    AgentRow(agent: agent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.accordion, value: viewModel.agents.map(\.id))
    }
}

/// The agents in short, for the menu bar popover and the open island: one line each with its
/// Claudy, what it was asked and the file it is touching. The tracks and the times stay in the
/// card's Agents tab.
struct AgentsShortList: View {
    @EnvironmentObject private var viewModel: AgentsViewModel
    var limit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Agents")
                    .microLabel(0.55)
                CountBadge(value: viewModel.agents.count, tint: Theme.Accent.coral.color)
            }
            ForEach(viewModel.agents.prefix(limit)) { agent in
                AgentShortRow(agent: agent)
            }
            if viewModel.agents.count > limit {
                Text("+\(viewModel.agents.count - limit) more")
                    .font(Theme.Font.label(9.5, .semibold))
                    .foregroundStyle(.primary.opacity(0.4))
                    .padding(.leading, AgentShortRow.claudyHeight * ClaudyTyping.aspectRatio + AgentShortRow.spacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.accordion, value: viewModel.agents.map(\.id))
    }
}

struct AgentShortRow: View {
    let agent: RunningAgent
    @EnvironmentObject private var viewModel: AgentsViewModel

    /// Half a point per sprite pixel: whole device pixels on Retina, as in the menu bar.
    static let claudyHeight: CGFloat = 13.5
    static let spacing: CGFloat = 7

    var body: some View {
        let status = agent.status(at: viewModel.now)
        HStack(spacing: Self.spacing) {
            AgentClaudy(agent: agent, status: status, height: Self.claudyHeight)
            Text(agent.title)
                .font(Theme.Font.label(10.5, .medium))
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
            Spacer(minLength: 6)
            AgentTouching(agent: agent, status: status, size: 9.5)
        }
        .contentShape(Rectangle())
        .help(viewModel.details(agent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentClaudy.spoken(agent, status: status))
    }
}

/// At rest, in the island's left ear beside Claudy: the lead agent's Claudy and how many agents are
/// running.
struct AgentsEarBadge: View {
    @EnvironmentObject private var viewModel: AgentsViewModel

    var body: some View {
        if let lead = viewModel.lead {
            HStack(spacing: 1) {
                AgentClaudy(agent: lead, status: lead.status(at: viewModel.now), height: AgentShortRow.claudyHeight)
                Text("\(viewModel.agents.count)")
                    .font(Theme.Font.value(10, .bold))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .help(viewModel.agents.count == 1 ? "1 agent running" : "\(viewModel.agents.count) agents running")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.agents.count == 1 ? "1 agent running" : "\(viewModel.agents.count) agents running")
        }
    }
}
