import SwiftUI

/// What the open island says, worked out from a reading: the lead quota in large, the others in
/// small, and when the lead one resets.
@MainActor
struct NotchActivity {
    let lead: UsageWindow
    /// Weekly then per model, as on the card. None on a plan billed on usage, which has neither.
    let others: [UsageWindow]
    /// "reset 14:30 · in 4 h 5 min", or why there is no countdown: never one to a reset
    /// already past.
    let resetLine: String
    /// "$46.31 of $500.00" when the lead is a spend cap.
    let spentLine: String?

    init(snapshot: UsageSnapshot, now: Date = Date()) {
        let lead = snapshot.primary
        self.lead = lead
        others = snapshot.spend == nil ? [snapshot.weekly, snapshot.sonnet] : []
        if lead.isActive {
            resetLine = "reset \(UsageViewModel.resetTime(lead.resetDate, now: now))"
                + " · in \(UsageViewModel.countdown(to: lead.resetDate))"
        } else {
            resetLine = lead.isMeasured ? "inactive" : "unavailable"
        }
        spentLine = lead.amount.map { UsageViewModel.spent($0) }
    }
}

/// The open island, laid out for the notch rather than under an icon: wide and low, like a
/// Live Activity. The session leads in large, the other quotas sit small on the right, and the
/// window's bar and its reset close it. The mascot and the figure are flown in by the island
/// from its ears: here they only mark where they land.
struct NotchActivityView: View {
    @EnvironmentObject private var viewModel: UsageViewModel

    private var snapshot: UsageSnapshot { viewModel.snapshot }
    private var activity: NotchActivity { NotchActivity(snapshot: snapshot) }
    private var lead: UsageWindow { activity.lead }
    private var tint: Color { Theme.tint(lead.accent, at: lead.percent) }
    /// No quotas without a Claude session, same rule as the card: the way in instead.
    private var showsQuotas: Bool { viewModel.isSignedIn || snapshot.isDemo }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            top
            if showsQuotas {
                window
            } else if viewModel.hasLoaded {
                signedOut
            }
            if let message = viewModel.errorMessage {
                errorLine(message)
            }
            UpdateRow()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(width: Theme.Metric.islandWidth, alignment: .leading)
    }

    // MARK: - Lead

    private var top: some View {
        HStack(alignment: .center, spacing: 14) {
            Color.clear
                .frame(width: NotchFlight.mascotSize * ClaudyTyping.aspectRatio, height: NotchFlight.mascotSize)
                .notchLanding(.mascot)

            VStack(alignment: .leading, spacing: 1) {
                IslandPercent(window: lead)
                    .notchLanding(.percent)
                Text("\(lead.title) · \(lead.window)")
                    .microLabel(0.5)
            }

            Spacer(minLength: 12)

            side
        }
    }

    /// The model at work, then the money or the other quotas.
    private var side: some View {
        VStack(alignment: .trailing, spacing: 7) {
            if !snapshot.activeModel.isEmpty {
                Text(snapshot.activeModel)
                    .font(Theme.Font.label(9.5, .semibold))
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.primary.opacity(0.1)))
            }
            if showsQuotas {
                if let spent = activity.spentLine {
                    Text(spent)
                        .font(Theme.Font.value(11, .medium))
                        .foregroundStyle(.primary.opacity(0.65))
                }
                ForEach(activity.others, id: \.title) { window in
                    smallQuota(window)
                }
            }
        }
    }

    private func smallQuota(_ window: UsageWindow) -> some View {
        HStack(spacing: 8) {
            Text(window.title)
                .font(Theme.Font.label(10.5, .medium))
                .foregroundStyle(.primary.opacity(0.55))
                .lineLimit(1)
            UsageBar(percent: window.isMeasured ? window.percent : 0,
                     tint: Theme.tint(window.accent, at: window.percent),
                     height: 4, showsGlow: false,
                     pace: window.isActive ? window.elapsed : nil)
                .frame(width: 64)
            Text(window.isMeasured ? "\(Int(window.percent * 100))%" : "—")
                .font(Theme.Font.value(11, .semibold))
                .foregroundStyle(.primary.opacity(window.isMeasured ? 0.85 : 0.4))
                .frame(width: 32, alignment: .trailing)
        }
        .help(window.isActive ? "\(window.title) · \(window.window), resets \(UsageViewModel.resetTime(window.resetDate))"
                              : "\(window.title) · \(window.window)")
    }

    // MARK: - Window

    /// The lead window as a bar, the pace marker on it, then where that leaves the user.
    private var window: some View {
        VStack(spacing: 7) {
            UsageBar(percent: lead.isMeasured ? lead.percent : 0, tint: tint, height: 6,
                     pace: lead.isActive ? lead.elapsed : nil)
            HStack(spacing: 8) {
                if let pace = UsageViewModel.pace(lead) {
                    Text(pace.text)
                        .foregroundStyle(pace.color)
                }
                Spacer(minLength: 8)
                Text(activity.resetLine)
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .font(Theme.Font.label(10.5, .medium))
            .lineLimit(1)
        }
    }

    // MARK: - Other states

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not signed in to Claude")
                .font(Theme.Font.label(12, .medium))
                .foregroundStyle(.primary.opacity(0.7))
            SignInControls()
        }
    }

    private func errorLine(_ message: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.danger)
                .frame(width: 5, height: 5)
            Text(message)
                .font(Theme.Font.label(10.5, .medium))
                .foregroundStyle(.primary.opacity(0.65))
                .lineLimit(2)
        }
    }
}
