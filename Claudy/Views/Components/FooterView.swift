import SwiftUI

/// Card footer: session count, last update time, manual refresh.
struct FooterView: View {
    let sessionCount: Int
    let updatedAt: Date
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(sessionCount) session\(sessionCount > 1 ? "s" : "") · \(UsageViewModel.clock(updatedAt))")
                .meta()
                .lineLimit(1)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
                    .frame(width: 28, height: 28)
                    .modifier(RoundGlass())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh, last updated \(UsageViewModel.clock(updatedAt))")
        }
    }
}

/// A small round control in glass, lit by the pointer. Before macOS 26, a quiet disc.
struct RoundGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        // Liquid Glass needs the macOS 26 SDK: an older Xcode builds the fallback alone.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(Circle().fill(.primary.opacity(0.08)))
        }
        #else
        content.background(Circle().fill(.primary.opacity(0.08)))
        #endif
    }
}
