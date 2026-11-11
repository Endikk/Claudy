import SwiftUI

enum CardTab: String, CaseIterable {
    case usage, ports, sessions
}

/// The card's tabs: a capsule of glass, the chosen tab a brighter lens sliding between them.
/// The counts are the only things allowed to raise their voice, and only when something is
/// actually happening: ports left open and sessions waiting for the user in amber, agents at
/// work in coral.
struct TabSwitcher: View {
    @Binding var selection: CardTab
    let badge: Int
    var agents: Int = 0
    var waiting: Int = 0

    @Environment(\.colorScheme) private var scheme
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CardTab.allCases, id: \.self) { tab in
                segment(tab)
            }
        }
        .padding(3)
        .modifier(CapsuleGlass())
    }

    private func segment(_ tab: CardTab) -> some View {
        let isSelected = selection == tab

        return HStack(spacing: 6) {
            Text(tab.rawValue.prefix(1).uppercased() + tab.rawValue.dropFirst())
                .font(Theme.Font.label(12, .semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)

            if tab == .ports, badge > 0 {
                CountBadge(value: badge, ink: .amber)
                    .help(badge == 1 ? "1 orphan to clean up" : "\(badge) orphans to clean up")
            }
            if tab == .sessions, waiting > 0 {
                CountBadge(value: waiting, ink: .amber, systemImage: "hand.raised.fill")
                    .help(waiting == 1 ? "1 session waits for you" : "\(waiting) sessions wait for you")
            } else if tab == .sessions, agents > 0 {
                CountBadge(value: agents, ink: .coral)
                    .help(agents == 1 ? "1 agent running" : "\(agents) agents running")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Metric.tabHeight)
        .background {
            if isSelected {
                Capsule()
                    .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.85))
                    .overlay(Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.2 : 0.6), lineWidth: 0.5))
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 1, y: 1)
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

/// A count tied to its label: a small capsule washed with its colour, the figure in that colour,
/// and what is counted as a symbol inside the same capsule. A bare figure beside a label read as
/// if it had landed there by mistake.
struct CountBadge: View {
    let value: Int
    let ink: Theme.Ink
    var systemImage: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text("\(value)")
                .font(Theme.Font.value(11, .semibold))
        }
        .foregroundStyle(ink.color(scheme))
        .padding(.horizontal, 6)
        .frame(minWidth: 18, minHeight: 18)
        .background(Capsule().fill(ink.color(.dark).opacity(scheme == .dark ? 0.22 : 0.16)))
    }
}

/// A capsule of glass behind a group of controls. Before macOS 26, a quiet fill.
struct CapsuleGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        // Liquid Glass needs the macOS 26 SDK: an older Xcode builds the fallback alone.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(Capsule().fill(.primary.opacity(0.06)))
        }
        #else
        content.background(Capsule().fill(.primary.opacity(0.06)))
        #endif
    }
}
