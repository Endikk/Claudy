import SwiftUI

enum CardTab: String, CaseIterable {
    case usage, ports
}

/// Two quiet segments in the card header. The badge is the only thing allowed to raise its
/// voice, and only when something is actually left running.
struct TabSwitcher: View {
    @Binding var selection: CardTab
    let badge: Int

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CardTab.allCases, id: \.self) { tab in
                segment(tab)
            }
        }
        .padding(2)
        .background(Capsule().fill(.primary.opacity(0.06)))
    }

    private func segment(_ tab: CardTab) -> some View {
        let isSelected = selection == tab

        return HStack(spacing: 4) {
            Text(tab.rawValue)
                .font(Theme.Font.label(9.5, .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.primary.opacity(isSelected ? 0.9 : 0.45))

            if tab == .ports, badge > 0 {
                Text("\(badge)")
                    .font(Theme.Font.value(8.5, .bold))
                    .foregroundStyle(Theme.Accent.amber.color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.Accent.amber.color.opacity(0.18)))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.Metric.tabHeight)
        .background {
            if isSelected {
                Capsule()
                    .fill(.primary.opacity(0.10))
                    .matchedGeometryEffect(id: "tab", in: indicator)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(Theme.Motion.mode) { selection = tab }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
