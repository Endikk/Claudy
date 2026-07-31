import SwiftUI

/// Mode compact : une bande horizontale — marque, pourcentage de la fenêtre 5h, heure de reset.
struct MinimalView: View {
    @EnvironmentObject private var viewModel: UsageViewModel

    private var session: UsageWindow { viewModel.snapshot.session }
    private var tint: Color { Theme.tint(session.accent, at: session.percent) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                ClaudeMark()
                    .fill(tint)
                    .frame(width: 16, height: 16)
                    .shadow(color: tint.opacity(0.45), radius: 5)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(session.percent * 100))")
                        .font(Theme.Font.hero(28))
                        .foregroundStyle(.primary.opacity(0.95))
                    Text("%")
                        .font(Theme.Font.label(13, .medium))
                        .foregroundStyle(.primary.opacity(0.4))
                }

                if let message = viewModel.errorMessage {
                    Circle()
                        .fill(Theme.danger)
                        .frame(width: 5, height: 5)
                        .help(message)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(session.isActive ? "reset" : "session")
                        .microLabel(0.35)
                    Text(session.isActive ? UsageViewModel.clock(session.resetDate) : "inactive")
                        .font(Theme.Font.value(12, .medium))
                        .foregroundStyle(.primary.opacity(0.65))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 8)

            // Barre affleurant le bord bas : la carte elle-même sert de jauge.
            UsageBar(percent: session.percent, tint: tint, height: 3, showsGlow: false,
                     pace: session.isActive ? session.elapsed : nil)
        }
        .frame(width: Theme.Metric.minimalWidth)
        .contentShape(Rectangle())
        // Un seul clic suffit pour agrandir — le glisser, lui, déplace toujours la carte.
        .onTapGesture { viewModel.toggleMode() }
        .help("Clic : mode complet")
    }
}
