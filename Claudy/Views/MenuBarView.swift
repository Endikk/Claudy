import SwiftUI
import Charts

/// The popover under the menu bar item, built around charts rather than the widget's gauges:
/// the three quotas as rings with their pace, seven days as bars, and the weekly split by
/// model. Details and ports stay in the widget.
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    /// Model under the pointer, in the split bar or its legend.
    @State private var hoveredModel: String?

    private var snapshot: UsageSnapshot { viewModel.snapshot }
    /// The 5h session, or the monthly spend on a plan billed on usage.
    private var lead: UsageWindow { snapshot.primary }
    private var leadTint: Color { Theme.tint(lead.accent, at: lead.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if viewModel.isSignedIn || snapshot.isDemo {
                HStack(alignment: .top, spacing: 4) {
                    QuotaRing(window: lead)
                    // A plan billed on usage has no weekly or per-model quota to ring.
                    if snapshot.spend == nil {
                        QuotaRing(window: snapshot.weekly, delay: 0.08)
                        QuotaRing(window: snapshot.sonnet, delay: 0.16)
                    }
                }
                hairline
                WeekBarsChart(samples: snapshot.history, tint: Theme.Accent.coral.color)
                if !snapshot.models.isEmpty {
                    hairline
                    modelSplit
                }
                if viewModel.isSignedIn {
                    hairline
                    accountRow
                }
            } else if viewModel.hasLoaded {
                // Before the first reading, a signed-in user would see the way in flash by.
                signedOut
            }
            UpdateRow()
            footer
        }
        .padding(Theme.Metric.padding)
        .frame(width: Theme.Metric.menuBarWidth)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ClaudyTyping(tint: leadTint, isTyping: snapshot.session.isRunning, isOverloaded: snapshot.isOverloaded)
                .frame(width: 27 * ClaudyTyping.aspectRatio, height: 27)

            Text("Claudy")
                .font(Theme.Font.label(14, .semibold))
                .foregroundStyle(.primary.opacity(0.9))

            Spacer(minLength: 0)

            if let message = viewModel.errorMessage {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 6, height: 6)
                    .help(message)
            }

            if !snapshot.activeModel.isEmpty {
                Text(snapshot.activeModel)
                    .font(Theme.Font.label(9.5, .semibold))
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.primary.opacity(0.08)))
            }
        }
    }

    /// The week's tokens split by model: one stacked bar, then one legend row per model, so
    /// names stay whole however many models the week used.
    private var modelSplit: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("By model · 7d")
                .microLabel(0.55)

            Chart(snapshot.models) { model in
                BarMark(x: .value("Share", model.share), y: .value("Week", "week"))
                    .foregroundStyle(model.accent.color.opacity(modelOpacity(model.id)))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXScale(domain: 0...totalShare)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plot = geometry[proxy.plotAreaFrame]
                                let share: Double? = proxy.value(atX: location.x - plot.origin.x)
                                hoveredModel = share.flatMap(model(atShare:))?.id
                            case .ended:
                                hoveredModel = nil
                            }
                        }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            VStack(spacing: 4) {
                ForEach(snapshot.models) { model in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.accent.color)
                            .frame(width: 6, height: 6)
                        Text(model.name)
                            .font(Theme.Font.label(10.5, .medium))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(UsageViewModel.tokens(model.tokens))
                            .font(Theme.Font.value(10, .medium))
                            .foregroundStyle(.primary.opacity(0.4))
                        Text("\(Int((model.share * 100).rounded())) %")
                            .font(Theme.Font.value(10.5, .semibold))
                            .foregroundStyle(.primary.opacity(0.75))
                            .frame(width: 34, alignment: .trailing)
                    }
                    .opacity(modelOpacity(model.id))
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hoveredModel = model.id } else if hoveredModel == model.id { hoveredModel = nil }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hoveredModel)
    }

    private var totalShare: Double { max(snapshot.models.map(\.share).reduce(0, +), 0.0001) }

    /// Everything stays lit until something is hovered; then only that model does.
    private func modelOpacity(_ id: String) -> Double {
        guard let hoveredModel else { return 1 }
        return id == hoveredModel ? 1 : 0.3
    }

    /// The segment under a position along the stacked bar, in the bar's own share units.
    private func model(atShare share: Double) -> ModelUsage? {
        var start = 0.0
        for model in snapshot.models {
            if share < start + model.share { return model }
            start += model.share
        }
        return snapshot.models.last
    }

    private var hairline: some View {
        Rectangle()
            .fill(.primary.opacity(0.07))
            .frame(height: 1)
    }

    /// No gauges without a session, same rule as the widget: say so and offer the way in.
    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not signed in to Claude")
                .font(Theme.Font.label(12, .medium))
                .foregroundStyle(.primary.opacity(0.7))
            SignInControls()
        }
    }

    /// Whose quotas these are, and the way out. Signing out leaves Claude Code signed in.
    private var accountRow: some View {
        HStack(spacing: 8) {
            Text(snapshot.account.email.isEmpty ? snapshot.account.name : snapshot.account.email)
                .font(Theme.Font.label(10.5, .medium))
                .foregroundStyle(.primary.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button("Sign out", action: viewModel.signOut)
                .buttonStyle(.borderless)
                .font(Theme.Font.label(11, .medium))
                .help("Claudy stops reading your quotas until you sign back in. Claude Code stays signed in.")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("updated \(UsageViewModel.clock(snapshot.updatedAt))")
                .font(Theme.Font.label(9.5, .medium))
                .foregroundStyle(.primary.opacity(0.35))

            Spacer(minLength: 0)

            Button {
                Task { await viewModel.refresh(userInitiated: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshing)
            .help("Refresh")

            Button("Floating widget", action: viewModel.toggleMenuBar)
                .help("Leave the menu bar and show the widget on the desktop")
        }
        .buttonStyle(.borderless)
        .font(Theme.Font.label(11, .medium))
    }
}
