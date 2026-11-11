import SwiftUI

/// Full mode, top to bottom: header, tabs, the 5h session in its own glass tile, then on the glass
/// itself the weekly and per-model windows, the week's curve with today's and the week's totals,
/// the details on demand; the footer last. On a plan billed on usage, the monthly spend takes the
/// session's place and the two windows, which have no quota there, step aside.
struct FullView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var updates: UpdateChecker
    @EnvironmentObject private var portsViewModel: PortsViewModel
    @EnvironmentObject private var agentsViewModel: AgentsViewModel

    private var snapshot: UsageSnapshot { viewModel.snapshot }
    private var lead: UsageWindow { snapshot.primary }
    private var leadTint: Color { Theme.tint(lead.accent, at: lead.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.gap) {
            header
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleMode() }

            TabSwitcher(selection: $viewModel.tab, badge: portsViewModel.orphanCount,
                        agents: agentsViewModel.runningCount, waiting: agentsViewModel.waiting.count)

            switch viewModel.tab {
            case .usage: usageTab
            case .ports: PortsView()
            case .sessions: SessionsView()
            }
        }
        .padding(Theme.Metric.panelPadding)
        .frame(width: Theme.Metric.fullWidth)
        .onChange(of: viewModel.tab) { tab in
            portsViewModel.setVisible(tab == .ports)
        }
    }

    /// One block only, the lead window: the figure people come for. The two weekly windows and
    /// the week's curve lie on the glass itself, apart by a hairline, so the card does not read as
    /// boxes stacked on boxes.
    private var usageTab: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.gap) {
            sessionBlock
                .tile(leadTint, strength: 0.18)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleMode() }
                .help("Click for minimal mode")

            if snapshot.spend == nil {
                HStack(alignment: .top, spacing: 14) {
                    StatColumn(window: snapshot.weekly)
                    Hairline(isVertical: true)
                        .padding(.vertical, -6)
                    StatColumn(window: snapshot.sonnet)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Hairline()
            }

            SparklineChart(title: "Usage · 7 days", samples: snapshot.history,
                           tint: Theme.Accent.coral.color,
                           today: snapshot.todayTokens, week: snapshot.weekTokens)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            if viewModel.isDetailsExpanded {
                Hairline()
                DetailsSection()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            UpdateRow()

            HStack(spacing: 8) {
                DetailsToggle()
                Spacer(minLength: 0)
                FooterView(
                    sessionCount: snapshot.sessionCount,
                    updatedAt: snapshot.updatedAt,
                    isRefreshing: viewModel.isRefreshing,
                    onRefresh: { Task { await viewModel.refresh(userInitiated: true) } }
                )
            }
            .padding(.leading, 6)
            .padding(.trailing, 2)
        }
        .animation(Theme.Motion.accordion, value: viewModel.isDetailsExpanded)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Group {
                if updates.isGreeting && !snapshot.isOverloaded {
                    ClaudyWaving(tint: leadTint, cell: 1)
                } else {
                    ClaudyTyping(isTyping: snapshot.session.isRunning, isOverloaded: snapshot.isOverloaded)
                }
            }
            .frame(width: 30 * ClaudyTyping.aspectRatio, height: 30)

            Text("Claudy")
                .font(Theme.Font.label(16, .semibold))
                .foregroundStyle(.primary)

            if updates.available != nil {
                UpdateDot()
            }

            if !snapshot.activeModel.isEmpty {
                Text(snapshot.activeModel)
                    .font(Theme.Font.label(12, .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let badge = snapshot.quotaSource.badge {
                Text(badge.prefix(1).uppercased() + badge.dropFirst())
                    .font(Theme.Font.label(12, .semibold))
                    .ink(.amber)
                    .help(Self.sourceExplanation(snapshot.quotaSource))
            }

            if let message = viewModel.errorMessage {
                Text("Error")
                    .font(Theme.Font.label(12, .semibold))
                    .ink(.danger)
                    .help(message)
            }

            Spacer(minLength: 0)

            AvatarButton(
                account: snapshot.account,
                isActive: viewModel.isProfileVisible,
                action: viewModel.toggleProfile
            )
        }
        .frame(height: 34)
    }

    /// What each origin badge means, in one sentence. On hover the user must be able to tell
    /// whether the number they are reading comes from their account or from somewhere else.
    /// For a stale reading the age matters more than the clock time: "reading from 14:32" does
    /// not say whether it is ten minutes or three days old.
    private static func sourceExplanation(_ source: QuotaSource) -> String {
        switch source {
        case .api:
            "Account quotas, identical to claude.ai ▸ Usage."
        case .bridge:
            "Counters relayed by Claude Code's status line: same values, no request."
        case .stale(let date):
            "Account momentarily unreachable. Reading from \(UsageViewModel.age(since: date)) ago."
        case .unavailable:
            "Quotas unavailable: no figure is shown rather than an estimate."
        case .demo:
            "Claude Code was not found on this machine: sample data."
        }
    }

    /// "27 pts ahead of pace" next to the token count pushed it to an ellipsis: the tile says
    /// "27 pts ahead", as the weekly tiles do.
    private static func shortPace(_ text: String) -> String {
        let short = text
            .replacingOccurrences(of: " of pace", with: "")
            .replacingOccurrences(of: "behind pace", with: "behind")
        return short.prefix(1).uppercased() + short.dropFirst()
    }

    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(leadTint)
                            .frame(width: 7, height: 7)
                        Text("\(lead.title) · \(lead.window)")
                            .sectionLabel()
                    }
                    Figure(window: lead, size: 44)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(lead.isActive ? "Resets \(UsageViewModel.resetTime(lead.resetDate))"
                                       : (lead.isMeasured ? "Session inactive" : "Quota unavailable"))
                        .font(Theme.Font.value(13, .semibold))
                        .foregroundStyle(.primary)
                    if lead.isActive {
                        Text("in \(UsageViewModel.countdown(to: lead.resetDate))")
                            .meta()
                    }
                }
                .padding(.bottom, 8)
            }

            UsageBar(percent: lead.percent, tint: leadTint, height: 8,
                     pace: lead.isActive ? lead.elapsed : nil)

            HStack(spacing: 6) {
                Text(lead.amount.map { UsageViewModel.spent($0) }
                     ?? "\(UsageViewModel.tokens(lead.tokensUsed)) tokens on this machine")
                    .meta()
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let pace = UsageViewModel.pace(lead) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(pace.ink.color(.dark))
                            .frame(width: 6, height: 6)
                        Text(Self.shortPace(pace.text))
                            .font(Theme.Font.label(11, .semibold))
                            .ink(pace.ink)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
