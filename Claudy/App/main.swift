import AppKit

// Point d'entrée AppKit, volontairement : pas de `@main struct ClaudyApp: App`.
//
// Claudy n'a aucune fenêtre standard. Avec un cycle de vie SwiftUI, la scène résiduelle
// (`Settings`) entre en conflit avec le panneau flottant piloté par l'AppDelegate et provoque
// une récursion de layout AppKit ↔ SwiftUI qui finit en SIGSEGV (débordement de pile) après
// quelques secondes. Ici, l'AppDelegate est seul maître de la fenêtre.

/// Global, et pas une variable locale : `NSApplication.delegate` est une référence faible.
let claudyDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = claudyDelegate
    application.run()
}
