import SwiftUI

/// What the notch island flies from its ears into the open popover, and back: the mascot to the
/// header, the lead percentage to its ring. The island draws them itself the whole way; the
/// popover only marks where they land.
enum NotchFlight: Hashable {
    case mascot, percent
}

private struct NotchFlightKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The island's namespace, set on the popover it hosts. `nil` under the menu bar item.
    var notchFlight: Namespace.ID? {
        get { self[NotchFlightKey.self] }
        set { self[NotchFlightKey.self] = newValue }
    }
}

extension View {
    /// In the island, where a flying element lands: hidden, since the island draws the element,
    /// and only its place counts. Under the menu bar item, the view as it is.
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
                .matchedGeometryEffect(id: flight, in: namespace, properties: .position, isSource: true)
        } else {
            content
        }
    }
}

/// A quota's percentage as the rings show it: the figure, then a small "%". The island's right
/// ear shows the same, scaled down, so it can grow into the ring without changing shape.
struct QuotaPercent: View {
    let window: UsageWindow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(window.isMeasured ? "\(Int(window.percent * 100))" : "—")
                .font(Theme.Font.value(16, .semibold))
                .foregroundStyle(.primary.opacity(window.isMeasured ? 0.92 : 0.4))
            if window.isMeasured {
                Text("%")
                    .font(Theme.Font.label(9, .medium))
                    .foregroundStyle(.primary.opacity(0.4))
            }
        }
    }
}
