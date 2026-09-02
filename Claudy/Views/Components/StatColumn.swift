import SwiftUI

/// Secondary column: "Weekly · 7d", "Sonnet · 7d".
struct StatColumn: View {
    let window: UsageWindow

    private var tint: Color { Theme.tint(window.accent, at: window.percent) }

    /// Distance from the expected pace, in percentage points.
    private var points: Int { Int((abs(window.paceDelta) * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                Text("\(window.title) · \(window.window)")
                    .microLabel(0.6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(window.isMeasured ? "\(Int(window.percent * 100))" : "—")
                    .font(Theme.Font.value(19, .semibold))
                if window.isMeasured {
                    Text("%")
                        .font(Theme.Font.label(11, .medium))
                        .foregroundStyle(.primary.opacity(0.45))
                }
            }
            .foregroundStyle(.primary.opacity(window.isMeasured ? 0.92 : 0.4))

            UsageBar(percent: window.percent, tint: tint, height: 5, showsGlow: false,
                     pace: window.isActive ? window.elapsed : nil)

            HStack(spacing: 4) {
                Text(window.isMeasured ? UsageViewModel.tokens(window.tokensUsed) + " here" : "no quota")
                    .font(Theme.Font.value(9.5, .medium))
                    .foregroundStyle(.primary.opacity(0.38))

                Spacer(minLength: 0)

                if let pace = UsageViewModel.pace(window), window.paceDelta.magnitude >= 0.04 {
                    Text(window.paceDelta > 0 ? "+\(points)" : "−\(points)")
                        .font(Theme.Font.value(9.5, .semibold))
                        .foregroundStyle(pace.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(0.05))
        )
    }
}
