import SwiftUI

/// The Sessions tab: every Claude Code session open on this Mac, the ones waiting for the user
/// first, each with the agents it runs underneath, its window one click away and the way to stop
/// it when it went wrong.
///
/// Built like the ports annex. Programs driving Claude Code through the Agent SDK only show
/// while they run agents: nobody sits at them.
struct SessionsView: View {
    @EnvironmentObject private var viewModel: AgentsViewModel

    var body: some View {
        let groups = viewModel.groups
        // A waiting session is its own amber tile, first: it is an alert. The others lie on the
        // glass.
        let waiting = groups.filter { $0.session.isWaiting }
        let others = groups.filter { !$0.session.isWaiting }

        VStack(alignment: .leading, spacing: Theme.Metric.gap) {
            if groups.isEmpty {
                Text("No Claude Code session open")
                    .font(Theme.Font.label(12, .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
            } else {
                header(count: groups.count)
                    .padding(.horizontal, 6)

                ForEach(waiting) { group in
                    SessionRow(group: group)
                }

                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(others) { group in
                            SessionRow(group: group)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            // Outside the list: an interrupt that closed the session empties it at once.
            if let notice = viewModel.notice {
                Text(notice)
                    .font(Theme.Font.label(11, .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.accordion, value: groups.map(\.id))
        .animation(Theme.Motion.accordion, value: viewModel.agents.map(\.id))
        .animation(Theme.Motion.accordion, value: viewModel.expandedID)
        .animation(Theme.Motion.accordion, value: viewModel.expandedSessionID)
        .animation(Theme.Motion.accordion, value: viewModel.interruptPending)
        .animation(.easeOut(duration: 0.2), value: viewModel.notice)
    }

    /// The section title, and what the tracks mean once agents are listed: ten minutes, writes in
    /// coral.
    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(count == 1 ? "1 session open" : "\(count) sessions open")
                .sectionLabel()
            Spacer(minLength: 8)
            if !viewModel.agents.isEmpty {
                AgentTrackLegend()
            }
        }
    }
}
