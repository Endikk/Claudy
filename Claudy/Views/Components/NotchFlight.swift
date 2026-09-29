import SwiftUI

/// What the notch island flies from its ears into its open view, and back: the mascot and the
/// lead percentage. The island draws them itself the whole way; the open view only marks where
/// they land.
enum NotchFlight: Hashable {
    case mascot, percent

    /// 1.5 points per sprite pixel once landed: whole device pixels on a Retina screen. At rest
    /// the mascot is scaled to a third, the menu bar icon's half point.
    static let mascotCell: CGFloat = 1.5
    /// The mascot's height once landed: the sprite is 27 pixels tall.
    static let mascotSize: CGFloat = 27 * mascotCell
}

private struct NotchFlightKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The island's namespace, set on the open view it hosts. `nil` anywhere else.
    var notchFlight: Namespace.ID? {
        get { self[NotchFlightKey.self] }
        set { self[NotchFlightKey.self] = newValue }
    }
}

extension View {
    /// In the island, where a flying element lands: hidden, since the island draws the element,
    /// and only its place counts. Anywhere else, the view as it is.
    func notchLanding(_ flight: NotchFlight) -> some View {
        modifier(NotchLanding(flight: flight))
    }
}

private struct NotchLanding: ViewModifier {
    let flight: NotchFlight
    @Environment(\.notchFlight) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content
                .opacity(0)
                // The island's ears already say it: VoiceOver would read the figure twice.
                .accessibilityHidden(true)
                .matchedGeometryEffect(id: flight, in: namespace, properties: .position, isSource: true)
        } else {
            content
        }
    }
}

/// The lead percentage as the open island shows it: a large figure, then a small "%". The right
/// ear shows the same, scaled down, so it grows into place without changing shape.
struct IslandPercent: View {
    let window: UsageWindow

    /// The figure's size once landed.
    static let size: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(window.isMeasured ? "\(Int(window.percent * 100))" : "—")
                .font(Theme.Font.hero(Self.size))
                .foregroundStyle(.primary.opacity(window.isMeasured ? 0.95 : 0.45))
            if window.isMeasured {
                Text("%")
                    .font(Theme.Font.label(16, .medium))
                    .foregroundStyle(.primary.opacity(0.4))
            }
        }
    }
}
