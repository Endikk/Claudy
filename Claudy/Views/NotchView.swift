import SwiftUI

/// The island's state, shared by `NotchController` and `NotchView`.
@MainActor
final class NotchModel: ObservableObject {
    /// Hover opened it: the popover content hangs under the ears.
    @Published var isOpen = false
    /// The notch the ears hug, in points.
    @Published var notchSize: CGSize = .zero
    /// The island's size as last laid out. The controller fits the window to it.
    @Published var shapeSize: CGSize = .zero
}

/// Claudy around the notch. At rest a band the notch's height extends it on both sides, in the
/// card's glass: the mascot in the left ear, the lead percentage in the right one. Open, the
/// island's own view (`NotchActivityView`) hangs underneath on the same glass.
struct NotchView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var updates: UpdateChecker
    @ObservedObject var model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The mascot and the percentage fly between the ears and the popover in this namespace.
    @Namespace private var flight

    private static let restingRadius: CGFloat = 9
    private static let openRadius: CGFloat = 20
    /// The mascot and the figure are drawn at their landed size and scaled down into the ears:
    /// growing into place is then a scale, and the pixel art stays whole on the way.
    private static let mascotRestScale: CGFloat = 1.0 / 3
    /// The figure at rest: 13 points.
    private static let percentRestScale: CGFloat = 13 / IslandPercent.size

    /// The 5h session, or the monthly spend on a plan billed on usage.
    private var lead: UsageWindow { viewModel.snapshot.primary }
    private var tint: Color { Theme.tint(lead.accent, at: lead.percent) }
    private var percent: String { lead.isMeasured ? "\(Int(lead.percent * 100))%" : "—" }
    private var shape: NotchShape {
        NotchShape(bottomRadius: model.isOpen ? Self.openRadius : Self.restingRadius,
                   shoulder: NotchLayout.shoulder)
    }

    /// Hung from the window's top edge whatever the window's size. A flexible frame took the
    /// island's own height while the window was still the ears' size, so the first frames of the
    /// opening started from the middle and slid up.
    var body: some View {
        Color.clear
            .overlay(alignment: .top) { island }
    }

    private var island: some View {
        VStack(spacing: 0) {
            ears
            if model.isOpen {
                NotchActivityView()
                    .environment(\.notchFlight, flight)
                    .transition(contentTransition)
            }
        }
        // Room for the shoulders: the glass flares out beside the ears, along the top edge only.
        .padding(.horizontal, NotchLayout.shoulder)
        .background(framedGlass)
        .clipShape(shape)
        // The card's shadow, open only: at rest the ears merge with the notch, and a margin
        // around them would take clicks from the menu bar next to them.
        .background(OutlineShadow(outline: shape).opacity(model.isOpen ? 1 : 0))
        .padding(model.isOpen ? Self.shadowMargin : EdgeInsets())
        .environment(\.colorScheme, .dark)
        // Its own size whatever the window's: the controller sizes the window from it.
        .fixedSize()
        // Reported from the geometry itself: a preference set here reached the parent as its
        // default value only, and the window never followed the shape.
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { model.shapeSize = proxy.size }
                .onChange(of: proxy.size) { size in model.shapeSize = size }
        })
    }

    /// Width of the notch's black, carried round the island as a thin inner frame: the notch
    /// seems to open onto the glass, instead of the glass meeting it edge to edge.
    private static let frameWidth: CGFloat = 4
    /// The glass pane's top corners, inside the frame.
    private static let paneTopRadius: CGFloat = 6
    /// Room around the pane: the frame, plus the shoulders on the sides.
    private static let paneInsets = EdgeInsets(
        top: frameWidth,
        leading: NotchLayout.shoulder + frameWidth,
        bottom: frameWidth,
        trailing: NotchLayout.shoulder + frameWidth
    )

    private var pane: IslandPane {
        IslandPane(topRadius: Self.paneTopRadius,
                   bottomRadius: max((model.isOpen ? Self.openRadius : Self.restingRadius) - Self.frameWidth, 2))
    }

    /// The card's glass, glow and hairline, set in the notch's black. On a transparent menu bar a
    /// fully black island read as a block on the wallpaper; fully glass, it met the notch with no
    /// transition. The frame joins the two.
    private var framedGlass: some View {
        ZStack {
            Color.black
            glass
                .clipShape(pane)
                .overlay(
                    pane.stroke(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                )
                .padding(Self.paneInsets)
        }
    }

    private var glass: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
            LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.015)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.Accent.coral.color.opacity(0.16), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 240)
        }
    }

    /// Room for the shadow on the sides and below. The top is the screen's edge.
    private static let shadowMargin = EdgeInsets(
        top: 0,
        leading: Theme.Metric.shadowInset,
        bottom: Theme.Metric.shadowInset,
        trailing: Theme.Metric.shadowInset
    )

    /// The content settles in just after the shape starts to drop, from a touch smaller and
    /// blurred, and leaves first on the way back so the shape closes on nothing.
    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: Settling(amount: 1), identity: Settling(amount: 0))
                .animation(.easeOut(duration: 0.28).delay(0.05)),
            removal: .opacity.animation(.easeIn(duration: 0.12))
        )
    }

    /// Open, the mascot and the percentage leave their ears and grow into the open view, which
    /// only marks the spots (`notchLanding`): the ears draw both the whole way, above the fading
    /// content.
    private var ears: some View {
        HStack(spacing: 0) {
            mascot
                .scaleEffect(model.isOpen ? 1 : Self.mascotRestScale)
                .matchedGeometryEffect(id: NotchFlight.mascot, in: flight,
                                       properties: .position, isSource: !model.isOpen)
                .frame(width: NotchLayout.earWidth)
            Color.clear
                .frame(width: model.notchSize.width)
            reading
        }
        .frame(height: model.notchSize.height)
        .zIndex(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claudy, \(lead.title) \(percent)")
    }

    private var mascot: some View {
        Group {
            if updates.isGreeting && !viewModel.snapshot.isOverloaded {
                ClaudyWaving(tint: tint, cell: NotchFlight.mascotCell)
            } else {
                ClaudyTyping(tint: tint, isTyping: viewModel.snapshot.session.isRunning,
                             isOverloaded: viewModel.snapshot.isOverloaded)
            }
        }
        .frame(width: NotchFlight.mascotSize * ClaudyTyping.aspectRatio, height: NotchFlight.mascotSize)
    }

    private var reading: some View {
        IslandPercent(window: lead)
            // Its landed size whatever the ear's width, or the figure is cut to "…".
            .fixedSize()
            .scaleEffect(model.isOpen ? 1 : Self.percentRestScale)
            .matchedGeometryEffect(id: NotchFlight.percent, in: flight,
                                   properties: .position, isSource: !model.isOpen)
            .frame(width: NotchLayout.earWidth)
            // At the ear's outer edge, apart from the figure: laid out at its landed size, the
            // figure is wider than the ear, and dots placed after it fell outside the island.
            .overlay(alignment: .trailing) {
                // The open view carries its own update row and error line.
                if !model.isOpen {
                    dots
                }
            }
    }

    private var dots: some View {
        VStack(spacing: 3) {
            if updates.available != nil {
                UpdateDot(size: 5)
            }
            if let message = viewModel.errorMessage {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 5, height: 5)
                    .help(message)
            }
        }
        .padding(.trailing, 2)
    }
}

/// Content arriving in the island: faded, a touch smaller from the top, blurred.
private struct Settling: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .scaleEffect(1 - 0.06 * amount, anchor: .top)
            .blur(radius: 6 * amount)
    }
}

/// Flush with the screen's top edge, which it meets through a concave shoulder on each side, as
/// the notch does; rounded at the bottom. The bottom radius animates between the ears and the
/// open island. The body sits `shoulder` inside the rect on each side.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var shoulder: CGFloat = 0

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let flare = min(shoulder, rect.width / 4, rect.height / 2)
        let left = rect.minX + flare
        let right = rect.maxX - flare
        let radius = min(bottomRadius, rect.height / 2, (right - left) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if flare > 0 {
            path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + flare), control: CGPoint(x: right, y: rect.minY))
        }
        path.addArc(tangent1End: CGPoint(x: right, y: rect.maxY),
                    tangent2End: CGPoint(x: left, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: left, y: rect.maxY),
                    tangent2End: CGPoint(x: left, y: rect.minY + flare), radius: radius)
        path.addLine(to: CGPoint(x: left, y: rect.minY + flare))
        if flare > 0 {
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

/// The glass pane inside the island's frame: a rectangle with its own top and bottom corner
/// radii. The bottom one animates with the island's.
struct IslandPane: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 2, rect.height / 2)
        let bottom = min(bottomRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: top)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: top)
        path.closeSubpath()
        return path
    }
}
