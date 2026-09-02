import SwiftUI

/// Progress bar: recessed rail, gradient fill, tinted halo, and an optional pace marker.
///
/// The fill has a visibility floor so a tiny value stays readable instead of disappearing, but
/// the floor never applies at exactly zero — on an empty or unmeasured gauge a coloured dot would
/// read as consumption that does not exist.
struct UsageBar: View {
    let percent: Double
    let tint: Color
    let height: CGFloat
    var showsGlow: Bool = true

    /// Marker position, 0…1: the share of the window already elapsed. Fill to the left of the
    /// marker means ahead of the clock, to the right means behind it. `nil` on bars that express
    /// a share rather than a duration.
    var pace: Double?

    private var clamped: Double { min(max(percent, 0), 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.primary.opacity(0.09))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.72), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: clamped <= 0 ? 0 : max(height, geometry.size.width * clamped))
                    .shadow(color: showsGlow ? tint.opacity(0.45) : .clear, radius: 5, y: 1)

                if let pace {
                    marker(in: geometry.size, at: min(max(pace, 0), 1))
                }
            }
        }
        .frame(height: height)
        .animation(Theme.Motion.gauge, value: clamped)
    }

    /// The marker sits either on the fill or on the empty rail; without this switch it vanishes
    /// against one of the two backgrounds, in light mode as in dark.
    private func marker(in size: CGSize, at pace: Double) -> some View {
        let width = max(1.5, height * 0.28)
        let onFill = pace <= clamped

        return RoundedRectangle(cornerRadius: width / 2, style: .continuous)
            .fill(onFill ? Color.white.opacity(0.92) : Color.primary.opacity(0.45))
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(onFill ? 0.35 : 0), radius: 1.5)
            .offset(x: (size.width - width) * pace)
            .animation(Theme.Motion.gauge, value: pace)
    }
}
