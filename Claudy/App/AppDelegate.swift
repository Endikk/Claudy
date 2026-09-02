import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let viewModel = UsageViewModel()
    private var panel: FloatingPanel?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?

    /// Guard: `setFrame` from `windowDidResize` re-notifies.
    private var isAdjustingFrame = false

    /// The card's **bottom-right** corner, its anchor point. This is what stays fixed when the
    /// card resizes: it grows up and to the left, never under the screen edge. Reset to the
    /// screen's bottom right on every launch.
    private var anchor: CGPoint = .zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        let controller = NSHostingController(rootView: RootView().environmentObject(viewModel))
        controller.sizingOptions = [.preferredContentSize]

        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 220))
        panel.contentViewController = controller
        panel.delegate = self
        panel.level = viewModel.isAlwaysOnTop ? .floating : .normal
        self.panel = panel

        anchor = homeAnchor(on: NSScreen.main)
        applyAnchor()
        panel.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    (NSApp.delegate as? AppDelegate)?.clampPanelToScreen()
                }
            }
        }

        bind()
        Task { await viewModel.refresh() }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func bind() {
        viewModel.$isAlwaysOnTop
            .receive(on: RunLoop.main)
            .sink { [weak self] onTop in
                self?.panel?.level = onTop ? .floating : .normal
            }
            .store(in: &cancellables)
    }

    /// The area the card settles into.
    ///
    /// Left, right and bottom edges come from the **physical** screen, not `visibleFrame`. The
    /// Dock reserves some sixty points at the bottom, but it is a centred pill: the bottom-right
    /// corner is free, and keeping clear of it would leave an unexplainable gap. Only the menu
    /// bar is respected at the top, since it spans the full width.
    private func layoutBounds(on screen: NSScreen?) -> NSRect {
        guard let screen = screen ?? NSScreen.main else { return panel?.frame ?? .zero }
        let full = screen.frame
        return NSRect(
            x: full.minX,
            y: full.minY,
            width: full.width,
            height: screen.visibleFrame.maxY - full.minY
        )
    }

    /// The **visual** bottom-right corner the card should occupy on a given screen. The drop
    /// shadow lives in a transparent margin; without subtracting it the card would float 14 pt
    /// from the edge instead of hugging the corner.
    private func homeAnchor(on screen: NSScreen?) -> CGPoint {
        let bounds = layoutBounds(on: screen)
        return CGPoint(
            x: bounds.maxX - Theme.Metric.screenMargin,
            y: bounds.minY + Theme.Metric.screenMargin
        )
    }

    /// Puts the card back on its bottom-right anchor, then clamps it to the screen. Called on
    /// every size change: growth starts from the bottom and goes upward, so the whole interface
    /// always stays visible.
    private func applyAnchor() {
        guard let panel else { return }
        let inset = Theme.Metric.shadowInset

        var frame = panel.frame
        frame.origin.x = anchor.x + inset - frame.width
        frame.origin.y = anchor.y - inset
        frame = clamped(frame, for: panel)
        guard frame != panel.frame else { return }

        isAdjustingFrame = true
        panel.setFrame(frame, display: true)
        isAdjustingFrame = false
    }

    /// Brings the card back into the usable screen area. Without it: the widget goes off-screen
    /// after an external monitor is unplugged, or the card dives below the bottom edge when the
    /// accordion makes it taller.
    ///
    /// Clamping applies to the **visual** rectangle (window minus the shadow margin); clamping the
    /// whole window would leave an empty 14 pt band along the edges.
    private func clamped(_ frame: NSRect, for window: NSWindow) -> NSRect {
        let inset = Theme.Metric.shadowInset
        let margin = Theme.Metric.screenMargin
        let bounds = layoutBounds(on: window.screen).insetBy(dx: margin, dy: margin)
        var visual = frame.insetBy(dx: inset, dy: inset)

        visual.origin.x = min(max(visual.minX, bounds.minX), max(bounds.minX, bounds.maxX - visual.width))
        if visual.height >= bounds.height {
            visual.origin.y = bounds.maxY - visual.height
        } else {
            visual.origin.y = min(max(visual.minY, bounds.minY), bounds.maxY - visual.height)
        }
        return visual.insetBy(dx: -inset, dy: -inset)
    }

    /// Screen unplugged or resolution changed: reapply the anchor, clamp, then adopt the
    /// position actually reached as the new anchor — the old one may point at a screen that no
    /// longer exists.
    private func clampPanelToScreen() {
        applyAnchor()
        if let panel {
            anchor = visualAnchor(of: panel)
        }
    }

    /// Bottom-right corner of the visible card, derived from the current window.
    private func visualAnchor(of window: NSWindow) -> CGPoint {
        let inset = Theme.Metric.shadowInset
        return CGPoint(x: window.frame.maxX - inset, y: window.frame.minY + inset)
    }

    // MARK: - NSWindowDelegate

    /// Mouse drag: the bottom-right corner of the new position becomes the anchor.
    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame, let panel, notification.object as? NSWindow === panel else { return }
        anchor = visualAnchor(of: panel)
    }

    /// Size change (mode switch, accordion, onboarding): the card **always** returns to its
    /// assigned place — the bottom-right corner of whichever screen it is on — whatever position
    /// it had been dragged to meanwhile.
    func windowDidResize(_ notification: Notification) {
        guard !isAdjustingFrame, let panel, notification.object as? NSWindow === panel else { return }
        anchor = homeAnchor(on: panel.screen)
        applyAnchor()
    }

    // MARK: - Menu

    /// `LSUIElement` removes the menu bar; without this minimal menu, ⌘Q and ⌘R would not respond.
    private func installMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Claudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appItem = NSMenuItem()
        appItem.submenu = appMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func refreshNow() {
        Task { await viewModel.refresh() }
    }
}
