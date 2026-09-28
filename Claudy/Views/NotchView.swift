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

    var body: some View {
        VStack(spacing: 0) {
            ears
            if model.isOpen {
                MenuBarView()
                    .transition(.opacity)
            }
        }
        .background(shape.fill(Color.black))
        .clipShape(shape)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
