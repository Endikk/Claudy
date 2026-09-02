import AppKit

/// The widget window: borderless, transparent, floating, draggable by its background.
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

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    /// Without this override a `.borderless` panel never becomes key: no keyboard, and no
    /// reliable context menu.
    override var canBecomeKey: Bool { true }
}
