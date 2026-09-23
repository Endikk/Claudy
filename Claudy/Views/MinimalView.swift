import SwiftUI

/// Compact mode: one horizontal strip — the mark, the 5h window percentage, the reset time.
struct MinimalView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var updates: UpdateChecker

    /// The 5h session, or the monthly spend on a plan billed on usage.
    private var lead: UsageWindow { viewModel.snapshot.primary }
    private var tint: Color { Theme.tint(lead.accent, at: lead.percent) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Group {
                    if updates.isGreeting && !viewModel.snapshot.isOverloaded {
                        ClaudyWaving(tint: tint, cell: 1)
                    } else {
                        ClaudyTyping(tint: tint, isTyping: viewModel.snapshot.session.isRunning,
                                     isOverloaded: viewModel.snapshot.isOverloaded)
                    }
                }
                .frame(width: 27 * ClaudyTyping.aspectRatio, height: 27)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(lead.isMeasured ? "\(Int(lead.percent * 100))" : "—")
                        .font(Theme.Font.hero(28))
                        .foregroundStyle(.primary.opacity(lead.isMeasured ? 0.95 : 0.45))
                    if lead.isMeasured {
                        Text("%")
                            .font(Theme.Font.label(13, .medium))
                            .foregroundStyle(.primary.opacity(0.4))
                    }
                }

                if updates.available != nil {
                    UpdateDot(size: 5)
                }

                if let message = viewModel.errorMessage {
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 5, height: 5)
                        .help(message)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(lead.isActive ? "reset" : (lead.isMeasured ? "session" : "quota"))
                        .microLabel(0.35)
                    Text(lead.isActive ? UsageViewModel.resetTime(lead.resetDate)
                                          : (lead.isMeasured ? "inactive" : "unavailable"))
                        .font(Theme.Font.value(12, .medium))
                        .foregroundStyle(.primary.opacity(0.65))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 8)

            UsageBar(percent: lead.percent, tint: tint, height: 3, showsGlow: false,
                     pace: lead.isActive ? lead.elapsed : nil)
        }
        .frame(width: Theme.Metric.minimalWidth)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleMode() }
        .help("Click for full mode")
    }
}
