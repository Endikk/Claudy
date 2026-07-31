import SwiftUI

/// Accordéon « Détails » : répartition par modèle et top projets.
struct DetailsSection: View {
    @EnvironmentObject private var viewModel: UsageViewModel

    private var snapshot: UsageSnapshot { viewModel.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: viewModel.toggleDetails) {
                HStack(spacing: 6) {
                    Text("Détails")
                        .microLabel(0.6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.4))
                        .rotationEffect(.degrees(viewModel.isDetailsExpanded ? 0 : -90))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if viewModel.isDetailsExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if snapshot.models.isEmpty && snapshot.projects.isEmpty {
                        Text("Aucune activité relevée sur les 7 derniers jours.")
                            .font(Theme.Font.label(10.5, .regular))
                            .foregroundStyle(.primary.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        group("Par modèle") {
                            ForEach(snapshot.models) { model in
                                MiniBarRow(
                                    name: model.name,
                                    tokens: model.tokens,
                                    share: model.share,
                                    tint: model.accent.color
                                )
                            }
                        }

                        group("Top projets") {
                            ForEach(snapshot.projects) { project in
                                MiniBarRow(
                                    name: project.name,
                                    tokens: project.tokens,
                                    share: project.share,
                                    tint: Theme.Accent.sage.color
                                )
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(Theme.Font.label(9, .semibold))
                .foregroundStyle(.primary.opacity(0.35))
            content()
        }
    }
}

/// Ligne de répartition : nom, volume, part, et une barre fine sur toute la largeur.
struct MiniBarRow: View {
    let name: String
    let tokens: Int
    let share: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(name)
                    .font(Theme.Font.label(11, .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(UsageViewModel.tokens(tokens))
                    .font(Theme.Font.value(10.5, .medium))
                    .foregroundStyle(.primary.opacity(0.55))

                Text("\(Int((share * 100).rounded())) %")
                    .font(Theme.Font.value(10.5, .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, alignment: .trailing)
            }

            UsageBar(percent: share, tint: tint, height: 3, showsGlow: false)
        }
    }
}
