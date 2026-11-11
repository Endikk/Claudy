import SwiftUI

/// Compact mode: one strip, the mark, the 5h window percentage and the reset time, the gauge
/// underneath.
struct MinimalView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var updates: UpdateChecker

    /// The 5h session, or the monthly spend on a plan billed on usage.
    private var lead: UsageWindow { viewModel.snapshot.primary }
    private var tint: Color { Theme.tint(lead.accent, at: lead.percent) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Group {
                    if updates.isGreeting && !viewModel.snapshot.isOverloaded {
                        ClaudyWaving(tint: tint, cell: 1)
                    } else {
                        ClaudyTyping(tint: tint, isTyping: viewModel.snapshot.session.isRunning,
                                     isOverloaded: viewModel.snapshot.isOverloaded)
                    }
                }
                .frame(width: 28 * ClaudyTyping.aspectRatio, height: 28)

                Figure(window: lead, size: 28)

                if updates.available != nil {
                    UpdateDot(size: 5)
                }

                if let message = viewModel.errorMessage {
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 6, height: 6)
                        .help(message)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(lead.isActive ? "Resets" : (lead.isMeasured ? "Session" : "Quota"))
                        .meta()
                    Text(lead.isActive ? UsageViewModel.resetTime(lead.resetDate)
                                       : (lead.isMeasured ? "Inactive" : "Unavailable"))
                        .font(Theme.Font.value(13, .semibold))
                        .foregroundStyle(.primary)
                }
            }

            UsageBar(percent: lead.percent, tint: tint, height: 5,
                     pace: lead.isActive ? lead.elapsed : nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: Theme.Metric.minimalWidth)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleMode() }
        .help("Click for full mode")
    }
}
