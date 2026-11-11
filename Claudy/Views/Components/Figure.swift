import SwiftUI

/// A percentage set like display type: rounded, tight, its unit small and quiet beside it. A
/// window with no reading shows a dash, and no unit.
struct Figure: View {
    let window: UsageWindow
    var size: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(window.isMeasured ? "\(Int(window.percent * 100))" : "—")
                .font(Theme.Font.hero(size))
                .tracking(-size * 0.02)
                .foregroundStyle(window.isMeasured ? .primary : .tertiary)
            if window.isMeasured {
                Text("%")
                    .font(Theme.Font.label(size * 0.4, .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
