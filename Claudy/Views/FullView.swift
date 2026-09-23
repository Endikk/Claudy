import SwiftUI

/// Full mode, top to bottom: header, 5h session, weekly and per-model columns, totals,
/// sparkline, "Details" accordion, footer. On a plan billed on usage, the monthly spend takes
/// the session's place and the two columns, which have no quota there, step aside.
struct FullView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var updates: UpdateChecker
    @EnvironmentObject private var portsViewModel: PortsViewModel

    private var snapshot: UsageSnapshot { viewModel.snapshot }
    private var lead: UsageWindow { snapshot.primary }
    private var leadTint: Color { Theme.tint(lead.accent, at: lead.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleMode() }

            TabSwitcher(selection: $viewModel.tab, badge: portsViewModel.orphanCount)

            switch viewModel.tab {
            case .usage: usageTab
            case .ports: PortsView()
            }
        }
        .padding(.horizontal, Theme.Metric.padding)
        .padding(.vertical, 14)
        .frame(width: Theme.Metric.fullWidth)
        .onChange(of: viewModel.tab) { tab in
            portsViewModel.setVisible(tab == .ports)
        }
    }

    /// The card's original content, unchanged: the tab switch only chooses between this and
    /// the ports annex.
    private var usageTab: some View {
        VStack(alignment: .leading, spacing: 11) {
            sessionBlock
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleMode() }
                .help("Click for minimal mode")

            if snapshot.spend == nil {
                HStack(spacing: 9) {
                    StatColumn(window: snapshot.weekly)
                    StatColumn(window: snapshot.sonnet)
                }
            }

            totals
            hairline
            chart
            hairline
            DetailsSection()
            hairline

            UpdateRow()

            FooterView(
                sessionCount: snapshot.sessionCount,
                updatedAt: snapshot.updatedAt,
                isRefreshing: viewModel.isRefreshing,
                onRefresh: { Task { await viewModel.refresh(userInitiated: true) } }
            )
        }
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
            .frame(width: 27 * ClaudyTyping.aspectRatio, height: 27)

            Text("Claudy")
                .font(Theme.Font.label(14, .semibold))
                .foregroundStyle(.primary.opacity(0.9))

            if updates.available != nil {
                UpdateDot()
            }

            if !snapshot.activeModel.isEmpty {
                pill(snapshot.activeModel, tint: nil)
            }

            if let badge = snapshot.quotaSource.badge {
                pill(badge, tint: Theme.Accent.amber.color)
                    .help(Self.sourceExplanation(snapshot.quotaSource))
            }

            if let message = viewModel.errorMessage {
                pill("error", tint: Theme.danger)
                    .help(message)
            }

            Spacer(minLength: 0)

            AvatarButton(
                account: snapshot.account,
                isActive: viewModel.isProfileVisible,
                action: viewModel.toggleProfile
            )
        }
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

    private func pill(_ text: String, tint: Color?) -> some View {
        Text(text)
            .font(Theme.Font.label(9.5, .semibold))
            .foregroundStyle(tint ?? .primary.opacity(0.6))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint?.opacity(0.16) ?? .primary.opacity(0.08)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.09), lineWidth: 1))
    }


    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(lead.title) · \(lead.window)")
                        .microLabel(0.55)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(lead.isMeasured ? "\(Int(lead.percent * 100))" : "—")
                            .font(Theme.Font.hero(40))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: lead.isMeasured
                                        ? [.primary, .primary.opacity(0.72)]
                                        : [.primary.opacity(0.4), .primary.opacity(0.28)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        if lead.isMeasured {
                            Text("%")
                                .font(Theme.Font.label(17, .medium))
                                .foregroundStyle(.primary.opacity(0.38))
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(lead.isActive ? "reset" : (lead.isMeasured ? "session" : "quota"))
                        .microLabel(0.35)
                    Text(lead.isActive ? UsageViewModel.resetTime(lead.resetDate)
                                          : (lead.isMeasured ? "inactive" : "unavailable"))
                        .font(Theme.Font.value(14, .semibold))
                        .foregroundStyle(.primary.opacity(0.8))
                    if lead.isActive {
                        Text("in \(UsageViewModel.countdown(to: lead.resetDate))")
                            .font(Theme.Font.label(9.5, .medium))
                            .foregroundStyle(.primary.opacity(0.35))
                    }
                }
                .padding(.top, 12)
            }

            UsageBar(percent: lead.percent, tint: leadTint, height: 8,
                     pace: lead.isActive ? lead.elapsed : nil)

            HStack(spacing: 6) {
                Text(lead.amount.map { UsageViewModel.spent($0) }
                     ?? "\(UsageViewModel.tokens(lead.tokensUsed)) tokens on this machine")
                    .font(Theme.Font.value(9.5, .medium))
                    .foregroundStyle(.primary.opacity(0.35))

                Spacer(minLength: 0)

                if let pace = UsageViewModel.pace(lead) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(pace.color)
                            .frame(width: 4, height: 4)
                        Text(pace.text)
                            .font(Theme.Font.label(9.5, .medium))
                            .foregroundStyle(pace.color.opacity(0.9))
                    }
                }
            }
        }
    }


    private var totals: some View {
        HStack(spacing: 0) {
            total("Today", snapshot.todayTokens, tint: Theme.Accent.coral.color)
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(width: 1, height: 26)
            total("7 days", snapshot.weekTokens, tint: Theme.Accent.sky.color)
        }
    }

    private func total(_ title: String, _ value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .microLabel(0.4)
            Text(UsageViewModel.tokens(value))
                .font(Theme.Font.value(15, .semibold))
                .foregroundStyle(tint.opacity(0.95))
        }
        .frame(maxWidth: .infinity)
    }


    private var chart: some View {
        SparklineChart(title: "Usage · 7 days", samples: snapshot.history,
                       tint: Theme.Accent.coral.color)
    }

    private var hairline: some View {
        Rectangle()
            .fill(.primary.opacity(0.07))
            .frame(height: 1)
    }
}
