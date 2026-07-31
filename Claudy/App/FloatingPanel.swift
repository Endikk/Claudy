import AppKit

/// La fenêtre du widget : sans bordure, transparente, flottante, déplaçable à la souris.
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // `.nonactivatingPanel` : cliquer le widget ne vole pas le focus de l'app en cours.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        isOpaque = false
        backgroundColor = .clear
        // L'ombre est dessinée côté SwiftUI : l'ombre système d'une fenêtre transparente
        // suit mal les coins arrondis et clignote au redimensionnement.
        hasShadow = false

        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    /// Sans cet override, un panneau `.borderless` ne devient jamais key :
    /// ni clavier, ni menu contextuel fiable.
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }
}
