import SwiftUI

/// One quota as a ring: the arc fills to the percentage, the dot on the track marks how much of
/// the window has elapsed. Arc past the dot means ahead of pace. The arc grows from zero each
/// time the ring appears, so opening the popover replays it.
struct QuotaRing: View {
    let window: UsageWindow
    /// Stagger between rings, in seconds.
    var delay: Double = 0

    @State private var shown: Double = 0

    private static let diameter: CGFloat = 60
    private static let lineWidth: CGFloat = 6

    private var tint: Color { Theme.tint(window.accent, at: window.percent) }
    private var target: Double { window.isMeasured ? min(max(window.percent, 0), 1) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: Self.lineWidth)

                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.45), radius: 4)

                if window.isActive {
                    paceDot
                }

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
            .frame(width: Self.diameter, height: Self.diameter)

            VStack(spacing: 1) {
                Text("\(window.title) · \(window.window)")
                    .microLabel(0.55)
                    .lineLimit(1)
                Text(window.isActive ? "in \(UsageViewModel.countdown(to: window.resetDate))"
                                     : (window.isMeasured ? "inactive" : "unavailable"))
                    .font(Theme.Font.label(9.5, .medium))
                    .foregroundStyle(.primary.opacity(0.4))
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
            .fill(.primary.opacity(0.75))
            .frame(width: 4, height: 4)
            .offset(y: -Self.diameter / 2)
            .rotationEffect(.degrees(window.elapsed * 360))
    }

    private var helpText: String {
        guard window.isActive else { return "\(window.title) · \(window.window)" }
        return "\(window.title) · \(window.window) — resets at \(UsageViewModel.clock(window.resetDate)). "
            + "The dot marks the time elapsed in the window."
    }
}
