import SwiftUI

/// The island's state, shared by `NotchController` and `NotchView`.
@MainActor
final class NotchModel: ObservableObject {
    /// Hover opened it: the popover content hangs under the ears.
    @Published var isOpen = false
    /// The notch the ears hug, in points.
    @Published var notchSize: CGSize = .zero
    /// The black shape's size as last laid out. The controller fits the window to it.
    @Published var shapeSize: CGSize = .zero
}

/// Claudy around the notch. At rest a black band the notch's height extends it on both sides:
/// the mascot in the left ear, the lead percentage in the right one. Open, the menu bar popover
/// hangs underneath on the same black. Black to merge with the notch itself.
struct NotchView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var updates: UpdateChecker
    @ObservedObject var model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let restingRadius: CGFloat = 9
    private static let openRadius: CGFloat = 20
    /// Room given to the typing mascot. The sprite snaps to whole device pixels inside it, which
    /// lands on the menu bar icon's size; the rest leaves room for the explosion.
    private static let mascotHeight: CGFloat = 20
    /// The menu bar icon's pixel, for the waving sprite, which takes its cell directly.
    private static let waveCell: CGFloat = 0.5

    /// The 5h session, or the monthly spend on a plan billed on usage.
    private var lead: UsageWindow { viewModel.snapshot.primary }
    private var tint: Color { Theme.tint(lead.accent, at: lead.percent) }
    private var percent: String { lead.isMeasured ? "\(Int(lead.percent * 100))%" : "—" }
    private var shape: NotchShape {
        NotchShape(bottomRadius: model.isOpen ? Self.openRadius : Self.restingRadius)
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
                MenuBarView()
                    .transition(contentTransition)
            }
        }
        .background(shape.fill(Color.black))
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

    private var ears: some View {
        HStack(spacing: 0) {
            mascot
                .frame(width: NotchLayout.earWidth)
            Color.clear
                .frame(width: model.notchSize.width)
            reading
                .frame(width: NotchLayout.earWidth)
        }
        .frame(height: model.notchSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claudy, \(lead.title) \(percent)")
    }

    @ViewBuilder
    private var mascot: some View {
        if updates.isGreeting && !viewModel.snapshot.isOverloaded {
            ClaudyWaving(tint: tint, cell: Self.waveCell)
        } else {
            ClaudyTyping(tint: tint, isTyping: viewModel.snapshot.session.isRunning,
                         isOverloaded: viewModel.snapshot.isOverloaded)
                .frame(width: Self.mascotHeight * ClaudyTyping.aspectRatio, height: Self.mascotHeight)
        }
    }

    private var reading: some View {
        HStack(spacing: 3) {
            Text(percent)
                .font(Theme.Font.value(12.5, .semibold))
                .foregroundStyle(.primary.opacity(lead.isMeasured ? 0.92 : 0.45))
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

/// Square on top, flush with the screen edge; rounded at the bottom. The radius animates between
/// the ears and the open panel.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}
