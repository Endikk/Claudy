import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let viewModel = UsageViewModel()
    private var panel: FloatingPanel?
    private var cancellables = Set<AnyCancellable>()

    /// Garde-fou : `setFrame` depuis `windowDidResize` renotifie.
    private var isAdjustingFrame = false

    // MARK: - Cycle de vie

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        let controller = NSHostingController(rootView: RootView().environmentObject(viewModel))
        // La fenêtre suit la taille intrinsèque de SwiftUI : bascule de mode et
        // ouverture de l'accordéon redimensionnent la carte sans mesure manuelle.
        controller.sizingOptions = [.preferredContentSize]

        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 220))
        panel.contentViewController = controller
        panel.delegate = self
        panel.level = viewModel.isAlwaysOnTop ? .floating : .normal
        self.panel = panel

        restoreFrame(for: panel)
        panel.orderFrontRegardless()

        bind()
        Task { await viewModel.refresh() }
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

    // MARK: - Position

    private func restoreFrame(for panel: NSPanel) {
        let defaults = UserDefaults.standard

        guard defaults.object(forKey: Keys.originX) != nil else {
            panel.center()
            return
        }

        // Seule l'origine est restaurée : la taille réelle n'est connue qu'après la première
        // passe de layout SwiftUI. Le recadrage à l'écran est fait par `windowDidResize`,
        // qui lui travaille sur la taille définitive.
        let origin = CGPoint(
            x: defaults.double(forKey: Keys.originX),
            y: defaults.double(forKey: Keys.originY)
        )
        panel.setFrame(clamped(NSRect(origin: origin, size: panel.frame.size), for: panel), display: false)
    }

    /// Ramène la carte dans la zone utile de l'écran.
    /// Sans ça : widget hors champ après un moniteur externe débranché, ou carte qui plonge
    /// sous le bas de l'écran quand l'accordéon la fait grandir.
    private func clamped(_ frame: NSRect, for window: NSWindow) -> NSRect {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return frame }

        var frame = frame
        frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        // Une carte plus haute que l'écran est alignée en haut plutôt que tronquée en bas.
        if frame.height >= visible.height {
            frame.origin.y = visible.maxY - frame.height
        } else {
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        return frame
    }

    private func saveOrigin(_ origin: CGPoint) {
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: Keys.originX)
        defaults.set(origin.y, forKey: Keys.originY)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame, let window = notification.object as? NSWindow else { return }
        saveOrigin(window.frame.origin)
    }

    /// Quand la carte change de taille (bascule de mode, accordéon), AppKit conserve déjà le coin
    /// *haut* gauche — `NSHostingController` passe par `setContentSize`. Il reste à empêcher la
    /// carte de plonger sous le bas de l'écran en grandissant.
    func windowDidResize(_ notification: Notification) {
        guard !isAdjustingFrame, let window = notification.object as? NSWindow else { return }

        let frame = clamped(window.frame, for: window)
        guard frame != window.frame else {
            saveOrigin(window.frame.origin)
            return
        }

        isAdjustingFrame = true
        window.setFrame(frame, display: true)
        isAdjustingFrame = false
        saveOrigin(frame.origin)
    }

    // MARK: - Menu

    /// `LSUIElement` supprime la barre de menus : sans ce menu minimal, ⌘Q et ⌘R ne répondraient pas.
    private func installMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Rafraîchir", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quitter Claudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appItem = NSMenuItem()
        appItem.submenu = appMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func refreshNow() {
        Task { await viewModel.refresh() }
    }

    private enum Keys {
        static let originX = "claudy.window.x"
        static let originY = "claudy.window.y"
    }
}
