import SwiftUI

/// One quota as a ring: the arc fills to the percentage, the dot on the track marks how much of
/// the window has elapsed. Arc past the dot means ahead of pace. The arc grows from zero each
/// time the ring appears, so opening the popover replays it.
struct QuotaRing: View {
    let window: UsageWindow
    /// Stagger between rings, in seconds.
    var delay: Double = 0

    @State private var shown: Double = 0

    private static let diameter: CGFloat = 64
    private static let lineWidth: CGFloat = 7

    private var tint: Color { Theme.tint(window.accent, at: window.percent) }
    private var target: Double { window.isMeasured ? min(max(window.percent, 0), 1) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.12), lineWidth: Self.lineWidth)

                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                if window.isActive {
                    paceDot
                }

                Figure(window: window, size: 19)
            }
            .frame(width: Self.diameter, height: Self.diameter)

            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text(window.title)
                        .font(Theme.Font.label(11, .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(window.isActive ? "in \(UsageViewModel.countdown(to: window.resetDate))"
                                     : (window.isMeasured ? "Inactive" : "Unavailable"))
                    .meta()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .help(helpText)
        .onAppear {
            withAnimation(Theme.Motion.gauge.delay(delay)) { shown = target }
        }
        .onDisappear { shown = 0 }
        .onChange(of: target) { value in
            withAnimation(Theme.Motion.gauge) { shown = value }
        }
    }

    private var paceDot: some View {
        Circle()
            .fill(.primary)
            .frame(width: 5, height: 5)
            .offset(y: -Self.diameter / 2)
            .rotationEffect(.degrees(window.elapsed * 360))
    }

    private var helpText: String {
        guard window.isActive else { return "\(window.title) · \(window.window)" }
        return "\(window.title) · \(window.window), resets \(UsageViewModel.resetTime(window.resetDate)). "
            + "The dot marks the time elapsed in the window."
    }
}
