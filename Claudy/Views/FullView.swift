import SwiftUI

/// Mode détaillé, de haut en bas : en-tête, session 5h, colonnes hebdo/Sonnet,
/// totaux, sparkline, accordéon « Détails », pied de carte.
struct FullView: View {
    @EnvironmentObject private var viewModel: UsageViewModel

    private var snapshot: UsageSnapshot { viewModel.snapshot }
    private var session: UsageWindow { snapshot.session }
    private var sessionTint: Color { Theme.tint(session.accent, at: session.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            sessionBlock

            HStack(spacing: 9) {
                StatColumn(window: snapshot.weekly)
                StatColumn(window: snapshot.sonnet)
            }

            totals
            hairline
            chart
            hairline
            DetailsSection()
            hairline

            FooterView(
                sessionCount: snapshot.sessionCount,
                updatedAt: snapshot.updatedAt,
                isRefreshing: viewModel.isRefreshing,
                onRefresh: { Task { await viewModel.refresh() } }
            )
        }
        .padding(.horizontal, Theme.Metric.padding)
        .padding(.vertical, 14)
        .frame(width: Theme.Metric.fullWidth)
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 8) {
            ClaudeMark()
                .fill(Theme.Accent.coral.color)
                .frame(width: 17, height: 17)
                .shadow(color: Theme.Accent.coral.color.opacity(0.5), radius: 6)

            Text("claudy")
                .font(Theme.Font.label(14, .semibold))
                .foregroundStyle(.primary.opacity(0.9))

            if !snapshot.activeModel.isEmpty {
                pill(snapshot.activeModel, tint: nil)
            }

            if snapshot.isDemo {
                // Claude Code absent de la machine : on l'annonce plutôt que de faire passer
                // des valeurs de démonstration pour un relevé.
                pill("démo", tint: Theme.Accent.amber.color)
                    .help("Claude Code n'a pas été trouvé sur cette machine — données d'exemple.")
            }

            if let message = viewModel.errorMessage {
                pill("erreur", tint: Theme.danger)
                    .help(message)
            }

            if snapshot.quotaStale {
                pill("⟳", tint: Theme.Accent.amber.color)
                    .help("Quotas momentanément injoignables — dernière valeur connue affichée.")
            }

            Spacer(minLength: 0)

            AvatarButton(
                account: snapshot.account,
                isActive: viewModel.isProfileVisible,
                action: viewModel.toggleProfile
            )
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

    // MARK: - Bloc principal

    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(session.title) · \(session.window)")
                        .microLabel(0.55)

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(session.percent * 100))")
                            .font(Theme.Font.hero(40))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.primary, .primary.opacity(0.72)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("%")
                            .font(Theme.Font.label(17, .medium))
                            .foregroundStyle(.primary.opacity(0.38))
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(session.isActive ? "reset" : "session")
                        .microLabel(0.35)
                    Text(session.isActive ? UsageViewModel.clock(session.resetDate) : "inactive")
                        .font(Theme.Font.value(14, .semibold))
                        .foregroundStyle(.primary.opacity(0.8))
                    if session.isActive {
                        Text("dans \(UsageViewModel.countdown(to: session.resetDate))")
                            .font(Theme.Font.label(9.5, .medium))
                            .foregroundStyle(.primary.opacity(0.35))
                    }
                }
                .padding(.top, 12)
            }

            UsageBar(percent: session.percent, tint: sessionTint, height: 8,
                     pace: session.isActive ? session.elapsed : nil)

            HStack(spacing: 6) {
                Text("\(UsageViewModel.tokens(session.tokensUsed)) sur \(UsageViewModel.tokens(session.tokensLimit)) tokens")
                    .font(Theme.Font.value(9.5, .medium))
                    .foregroundStyle(.primary.opacity(0.35))

                Spacer(minLength: 0)

                if let pace = UsageViewModel.pace(session) {
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

    // MARK: - Totaux

    private var totals: some View {
        HStack(spacing: 0) {
            total("Aujourd'hui", snapshot.todayTokens, tint: Theme.Accent.coral.color)
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(width: 1, height: 26)
            total("7 jours", snapshot.weekTokens, tint: Theme.Accent.sky.color)
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

    // MARK: - Graphique

    private var chart: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Usage · 7 jours")
                .microLabel(0.55)
            SparklineChart(samples: snapshot.history, tint: Theme.Accent.coral.color)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(.primary.opacity(0.07))
            .frame(height: 1)
    }
}
