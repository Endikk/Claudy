import AppKit
import SwiftUI

/// The update bubble's window. A popover from an app in the background stays invisible until
/// the app is activated, and activating would steal focus from whatever the user is typing in:
/// a non-activating panel shows up without taking focus, full-screen spaces included.
final class UpdateBubblePanel: NSPanel {

    /// Where the arrow sits along the top edge, from the bubble's centre.
    final class Layout: ObservableObject {
        @Published var arrowOffset: CGFloat = 0
    }

    private let layout = Layout()
    private static let gap: CGFloat = 2
    private static let screenMargin: CGFloat = 8

    init<Content: View>(content: Content) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = NSHostingView(rootView: BubbleChrome(layout: layout, content: content))
    }

    override var canBecomeKey: Bool { true }

    /// Opens the bubble under a status item, kept on screen, its arrow on the item's image: the
    /// percentage beside it would pull the arrow off Claudy if it aimed at the whole button.
    func show(below button: NSStatusBarButton) {
        guard let window = button.window, let screen = window.screen ?? NSScreen.main,
              let host = contentView else { return }
        let target = Self.imageRect(in: button)
        let item = window.convertToScreen(button.convert(target, to: nil))
        let size = host.fittingSize
        let bounds = screen.visibleFrame
        var origin = NSPoint(x: item.midX - size.width / 2, y: item.minY - Self.gap - size.height)
        origin.x = min(max(origin.x, bounds.minX + Self.screenMargin), bounds.maxX - size.width - Self.screenMargin)
        setFrame(NSRect(origin: origin, size: size), display: true)
        // The arrow keeps pointing at the item when the bubble is pushed back on screen.
        layout.arrowOffset = item.midX - (origin.x + size.width / 2)
        alphaValue = 1
        orderFrontRegardless()
    }

    /// The image's frame inside the button, or the whole button when it has no image. The
    /// cell's own `imageRect(forBounds:)` is off for status items: the image and the title are
    /// laid out as one block centred in the button, image first.
    private static func imageRect(in button: NSStatusBarButton) -> NSRect {
        guard let image = button.image else { return button.bounds }
        let titleWidth = button.attributedTitle.size().width
        let blockWidth = image.size.width + titleWidth
        let x = button.bounds.minX + max(0, (button.bounds.width - blockWidth) / 2)
        return NSRect(x: x, y: button.bounds.midY - image.size.height / 2,
                      width: image.size.width, height: image.size.height)
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        })
    }
}

/// The popover look: one outline, arrow and card together, on the system's popover material.
private struct BubbleChrome<Content: View>: View {
    @ObservedObject var layout: UpdateBubblePanel.Layout
    let content: Content

    var body: some View {
        let shape = BubbleShape(arrowOffset: layout.arrowOffset)
        content
            .padding(.top, BubbleShape.arrowHeight)
            .background(VisualEffectView(material: .popover, blending: .behindWindow))
            .clipShape(shape)
            .fixedSize()
    }
}

private struct BubbleShape: Shape {
    static let arrowHeight: CGFloat = 9
    static let corner: CGFloat = 12
    var arrowOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        let card = CGRect(x: rect.minX, y: rect.minY + Self.arrowHeight,
                          width: rect.width, height: rect.height - Self.arrowHeight)
        var path = Path(roundedRect: card, cornerRadius: Self.corner, style: .continuous)
        let tip = min(max(rect.midX + arrowOffset, card.minX + Self.corner + Self.arrowHeight),
                      card.maxX - Self.corner - Self.arrowHeight)
        path.move(to: CGPoint(x: tip - Self.arrowHeight, y: card.minY))
        path.addLine(to: CGPoint(x: tip, y: rect.minY))
        path.addLine(to: CGPoint(x: tip + Self.arrowHeight, y: card.minY))
        path.closeSubpath()
        return path
    }
}
