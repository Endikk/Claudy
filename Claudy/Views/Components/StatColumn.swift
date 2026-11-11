import SwiftUI

/// Secondary column: "Weekly · 7d", "Sonnet · 7d".
struct StatColumn: View {
    let window: UsageWindow

    private var tint: Color { Theme.tint(window.accent, at: window.percent) }

    /// Distance from the expected pace, in percentage points.
    private var points: Int { Int((abs(window.paceDelta) * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text("\(window.title) · \(window.window)")
                    .sectionLabel()
                    .lineLimit(1)
            }

            Figure(window: window, size: 26)

            UsageBar(percent: window.percent, tint: tint, height: 5,
                     pace: window.isActive ? window.elapsed : nil)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.isMeasured ? UsageViewModel.tokens(window.tokensUsed) + " here" : "No quota")
                    .meta()
                    .lineLimit(1)
                if let pace = UsageViewModel.pace(window), window.paceDelta.magnitude >= 0.04 {
                    Text(window.paceDelta > 0 ? "\(points) pts ahead" : "\(points) pts behind")
                        .font(Theme.Font.label(11, .semibold))
                        .ink(pace.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
