import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let viewModel = UsageViewModel()
    private var panel: FloatingPanel?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?

    /// Garde-fou : `setFrame` depuis `windowDidResize` renotifie.
    private var isAdjustingFrame = false

    /// Coin **bas-droit** de la carte — son point d'ancrage. C'est lui qui reste fixe quand
    /// la carte change de taille : elle grandit vers le haut et la gauche, jamais sous le
    /// bord de l'écran. Réinitialisé en bas à droite de l'écran à chaque lancement.
    private var anchor: CGPoint = .zero

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

        // Position de départ : coin bas-droit de l'écran principal, à chaque lancement.
        // C'est la place du widget ; un déplacement à la souris vaut pour la session.
        anchor = homeAnchor(on: NSScreen.main)
        applyAnchor()
        panel.orderFrontRegardless()

        // Moniteur débranché ou résolution changée : sans ce recadrage, la carte peut rester
        // hors champ sans aucun moyen de la récupérer (pas de Dock, pas de barre de menus).
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            // La notification arrive pendant la reconfiguration : les frames d'écran ne sont
            // parfois pas encore définitives, d'où le différé.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    (NSApp.delegate as? AppDelegate)?.clampPanelToScreen()
                }
            }
        }

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

    /// Coin bas-droit **visuel** que la carte doit occuper sur un écran donné.
    /// L'ombre portée vit dans une marge transparente : sans la retrancher, la carte
    /// flotterait à 14 pt du bord au lieu d'être collée au coin.
    private func homeAnchor(on screen: NSScreen?) -> CGPoint {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? panel?.frame ?? .zero
        return CGPoint(
            x: visible.maxX - Theme.Metric.screenMargin,
            y: visible.minY + Theme.Metric.screenMargin
        )
    }

    /// Replace la carte sur son ancre bas-droit puis recadre à l'écran. Appelé à chaque
    /// changement de taille : la croissance part du bas, donc vers le haut — l'interface
    /// entière reste toujours visible.
    private func applyAnchor() {
        guard let panel else { return }
        let inset = Theme.Metric.shadowInset

        // `anchor` désigne le coin bas-droit de la carte *visible* ; la fenêtre déborde
        // de `inset` sur chaque bord (marge d'ombre transparente).
        var frame = panel.frame
        frame.origin.x = anchor.x + inset - frame.width
        frame.origin.y = anchor.y - inset
        frame = clamped(frame, for: panel)
        guard frame != panel.frame else { return }

        isAdjustingFrame = true
        panel.setFrame(frame, display: true)
        isAdjustingFrame = false
    }

    /// Ramène la carte dans la zone utile de l'écran.
    /// Sans ça : widget hors champ après un moniteur externe débranché, ou carte qui plonge
    /// sous le bas de l'écran quand l'accordéon la fait grandir.
    ///
    /// Le recadrage porte sur le rectangle **visuel** (fenêtre moins la marge d'ombre) :
    /// clamper la fenêtre entière laisserait une bande vide de 14 pt le long des bords.
    private func clamped(_ frame: NSRect, for window: NSWindow) -> NSRect {
        guard let screen = (window.screen ?? NSScreen.main) else { return frame }

        let inset = Theme.Metric.shadowInset
        let margin = Theme.Metric.screenMargin
        let bounds = screen.visibleFrame.insetBy(dx: margin, dy: margin)
        var visual = frame.insetBy(dx: inset, dy: inset)

        visual.origin.x = min(max(visual.minX, bounds.minX), max(bounds.minX, bounds.maxX - visual.width))
        // Une carte plus haute que l'écran est alignée en haut plutôt que tronquée en bas.
        if visual.height >= bounds.height {
            visual.origin.y = bounds.maxY - visual.height
        } else {
            visual.origin.y = min(max(visual.minY, bounds.minY), bounds.maxY - visual.height)
        }
        return visual.insetBy(dx: -inset, dy: -inset)
    }

    /// Écran débranché ou résolution changée : replace sur l'ancre, recadre, puis adopte
    /// la position réellement obtenue comme nouvelle ancre (l'ancienne peut pointer sur un
    /// écran qui n'existe plus).
    private func clampPanelToScreen() {
        applyAnchor()
        if let panel {
            anchor = visualAnchor(of: panel)
        }
    }

    /// Coin bas-droit de la carte visible, déduit de la fenêtre courante.
    private func visualAnchor(of window: NSWindow) -> CGPoint {
        let inset = Theme.Metric.shadowInset
        return CGPoint(x: window.frame.maxX - inset, y: window.frame.minY + inset)
    }

    // MARK: - NSWindowDelegate

    /// Déplacement à la souris : le coin bas-droit de la nouvelle position devient l'ancre.
    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame, let panel, notification.object as? NSWindow === panel else { return }
        anchor = visualAnchor(of: panel)
    }

    /// Changement de taille (bascule de mode, accordéon, onboarding) : la carte revient
    /// **systématiquement** à sa place attitrée — le coin bas-droit de l'écran où elle se
    /// trouve — quelle que soit la position où elle avait été glissée entre-temps.
    func windowDidResize(_ notification: Notification) {
        guard !isAdjustingFrame, let panel, notification.object as? NSWindow === panel else { return }
        anchor = homeAnchor(on: panel.screen)
        applyAnchor()
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
}
