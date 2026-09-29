import AppKit
import SwiftUI

/// The island's window: borderless and non-activating, above the menu bar, on every space and
/// over full-screen apps, where the notch is a black band anyway.
final class NotchPanel: NSPanel {

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        // Key only for the manual sign-in code: a click on a button leaves the front app's focus.
        becomesKeyOnlyIfNeeded = true
        // Dark whatever the system's: the island grows out of the black notch, and its glass,
        // text fields and menus follow the window's appearance.
        appearance = NSAppearance(named: .darkAqua)
    }

    /// Without this a borderless panel never takes the keyboard, and the code could not be typed.
    override var canBecomeKey: Bool { true }

    /// AppKit keeps windows under the menu bar; the island belongs over it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The island's content view. It reports the pointer entering and leaving the whole window, key
/// or not, and answers a right click with Claudy's menu.
final class NotchHostingView<Content: View>: NSHostingView<Content> {

    var onHover: ((Bool) -> Void)?
    var contextMenu: (() -> NSMenu?)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    /// SwiftUI's own hover areas (the chart, the model split) report here too: only the area
    /// covering the whole island speaks for the pointer, or crossing the chart would close it.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === tracking { onHover?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === tracking { onHover?(false) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let menu = contextMenu?() { return menu }
        return super.menu(for: event)
    }

    /// A click on a button of the open island acts at once, key window or not.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
