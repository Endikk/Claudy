import AppKit

/// The widget window: borderless, transparent, floating, draggable from anywhere on the card.
///
/// `.nonactivatingPanel` keeps a click on the widget from stealing focus from the front app,
/// and the system shadow stays off because it tracks rounded corners poorly on a transparent
/// window and flickers while resizing — SwiftUI draws the shadow instead.
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    /// Without this override a `.borderless` panel never becomes key: no keyboard, and no
    /// reliable context menu.
    override var canBecomeKey: Bool { true }

    // MARK: - Dragging

    /// Distance the pointer travels before a press becomes a drag. Below it, the press stays a
    /// click and reaches the SwiftUI views as usual.
    private static let dragThreshold: CGFloat = 3

    private var pressEvent: NSEvent?

    /// Moves the card from anywhere on it. `isMovableByWindowBackground` only works where the
    /// view under the pointer agrees to move the window, which SwiftUI decides view by view. Since
    /// the animated mascot arrived, the card no longer followed the pointer. Watching the drag
    /// here does not depend on any view.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pressEvent = event
        case .leftMouseDragged:
            if let press = pressEvent, distance(from: press, to: event) >= Self.dragThreshold {
                pressEvent = nil
                performDrag(with: press)
                releasePress(press)
                return
            }
        case .leftMouseUp:
            pressEvent = nil
        default:
            break
        }
        super.sendEvent(event)
    }

    private func distance(from press: NSEvent, to event: NSEvent) -> CGFloat {
        hypot(event.locationInWindow.x - press.locationInWindow.x,
              event.locationInWindow.y - press.locationInWindow.y)
    }

    /// The drag loop swallows the mouse-up, so the views that saw the press would wait for it
    /// forever. They get one far from the press, which ends the gesture without counting as a
    /// click: dropping the card must not also switch its mode.
    private func releasePress(_ press: NSEvent) {
        let far = NSPoint(x: press.locationInWindow.x + 10_000, y: press.locationInWindow.y + 10_000)
        guard let release = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: far,
            modifierFlags: press.modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: press.eventNumber,
            clickCount: press.clickCount,
            pressure: 0
        ) else { return }
        super.sendEvent(release)
    }
}
