import SwiftUI

/// "Details" accordion: split by model and top projects.
struct DetailsSection: View {
    @EnvironmentObject private var viewModel: UsageViewModel

    private var snapshot: UsageSnapshot { viewModel.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: viewModel.toggleDetails) {
                HStack(spacing: 6) {
                    Text("Details")
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
                        Text("No activity recorded over the last 7 days.")
                            .font(Theme.Font.label(10.5, .regular))
                            .foregroundStyle(.primary.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // Shares follow what each token costs, not the raw count: cache reads
                        // are most of the volume but weigh a tenth, and Opus weighs five Haiku.
                        Text("Last 7 days · share weighted by model price")
                            .font(Theme.Font.label(9, .regular))
                            .foregroundStyle(.primary.opacity(0.35))

                        group("By model") {
                            ForEach(snapshot.models) { model in
                                MiniBarRow(
                                    name: model.name,
                                    tokens: model.tokens,
                                    share: model.share,
                                    tint: model.accent.color
                                )
                            }
                        }

                        group("Top projects") {
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

/// One split row: name, volume, share, and a thin full-width bar.
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
