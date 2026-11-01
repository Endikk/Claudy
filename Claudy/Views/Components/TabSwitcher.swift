import SwiftUI

enum CardTab: String, CaseIterable {
    case usage, ports, agents
}

/// Quiet segments in the card header. The badges are the only things allowed to raise their
/// voice, and only when something is actually running: ports left open in amber, agents at work
/// in coral.
struct TabSwitcher: View {
    @Binding var selection: CardTab
    let badge: Int
    var agents: Int = 0

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
                CountBadge(value: badge, tint: Theme.Accent.amber.color)
            }
            if tab == .agents, agents > 0 {
                CountBadge(value: agents, tint: Theme.Accent.coral.color)
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

/// A small count in a tinted capsule.
struct CountBadge: View {
    let value: Int
    let tint: Color

    var body: some View {
        Text("\(value)")
            .font(Theme.Font.value(8.5, .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.18)))
    }
}
