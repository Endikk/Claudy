import SwiftUI

/// The "Details" switch, in the card's footer row.
struct DetailsToggle: View {
    @EnvironmentObject private var viewModel: UsageViewModel

    var body: some View {
        Button(action: viewModel.toggleDetails) {
            HStack(spacing: 6) {
                Text("Details")
                    .font(Theme.Font.label(12, .semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(viewModel.isDetailsExpanded ? 0 : -90))
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(viewModel.isDetailsExpanded ? "Hide the split by model and project" : "Split by model and project")
    }
}

/// What "Details" unfolds to: the week split by model and by project.
struct DetailsSection: View {
    @EnvironmentObject private var viewModel: UsageViewModel

    private var snapshot: UsageSnapshot { viewModel.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.models.isEmpty && snapshot.projects.isEmpty {
                Text("No activity recorded over the last 7 days")
                    .meta()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Shares follow what each token costs, not the raw count: cache reads
                // are most of the volume but weigh a tenth, and Opus weighs five Haiku.
                Text("Last 7 days · share weighted by model price")
                    .meta()

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
                            tint: Theme.Accent.teal.color
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .sectionLabel()
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
                    .font(Theme.Font.label(13, .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(UsageViewModel.tokens(tokens))
                    .meta()

                Text("\(Int((share * 100).rounded()))%")
                    .font(Theme.Font.value(12, .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, alignment: .trailing)
            }

            UsageBar(percent: share, tint: tint, height: 4)
        }
    }
}
