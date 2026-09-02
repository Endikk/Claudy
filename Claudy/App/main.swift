import AppKit

/// Deliberately an AppKit entry point rather than `@main struct ClaudyApp: App`.
///
/// Claudy owns no standard window. Under a SwiftUI life cycle the residual `Settings` scene
/// fights the AppDelegate-driven floating panel, producing an AppKit ↔ SwiftUI layout recursion
/// that ends in SIGSEGV (stack overflow) within seconds. Here the AppDelegate owns the window alone.

/// Global rather than a local: `NSApplication.delegate` is a weak reference.
let claudyDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = claudyDelegate
    application.run()
}
