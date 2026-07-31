import SwiftUI

/// Colonne secondaire : « Hebdo · 7j », « Sonnet · 7j ».
struct StatColumn: View {
    let window: UsageWindow

    private var tint: Color { Theme.tint(window.accent, at: window.percent) }

    /// Écart au rythme en points de pourcentage.
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
                Text("\(Int(window.percent * 100))")
                    .font(Theme.Font.value(19, .semibold))
                Text("%")
                    .font(Theme.Font.label(11, .medium))
                    .foregroundStyle(.primary.opacity(0.45))
            }
            .foregroundStyle(.primary.opacity(0.92))

            UsageBar(percent: window.percent, tint: tint, height: 5, showsGlow: false,
                     pace: window.isActive ? window.elapsed : nil)

            HStack(spacing: 4) {
                Text(UsageViewModel.tokens(window.tokensUsed) + " / " + UsageViewModel.tokens(window.tokensLimit))
                    .font(Theme.Font.value(9.5, .medium))
                    .foregroundStyle(.primary.opacity(0.38))

                Spacer(minLength: 0)

                // Pas de place pour une phrase dans une colonne : l'écart au rythme se résume
                // à un signe et une valeur, le repère sur la barre donnant le détail.
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
