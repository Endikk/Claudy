import SwiftUI

/// Pied de carte : nombre de sessions, dernière mise à jour, rafraîchissement manuel.
struct FooterView: View {
    let sessionCount: Int
    let updatedAt: Date
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(sessionCount) session\(sessionCount > 1 ? "s" : "")")
            Text("·")
                .foregroundStyle(.primary.opacity(0.25))
            Text("maj \(UsageViewModel.clock(updatedAt))")

            Spacer(minLength: 0)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.45))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rafraîchir")
        }
        .font(Theme.Font.label(9.5, .medium))
        .foregroundStyle(.primary.opacity(0.4))
    }
}
