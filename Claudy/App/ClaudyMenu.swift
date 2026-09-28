import AppKit

/// The right-click menu of the menu bar item and of the island: refresh, the other placements,
/// the account, quit. Its items target this object, so each owner keeps its own alive.
@MainActor
final class ClaudyMenu: NSObject {

    private let viewModel: UsageViewModel

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    /// The menu for Claudy as it stands now.
    func make() -> NSMenu {
        make(showing: viewModel.placement, hasNotch: viewModel.hasNotchedScreen)
    }

    func make(showing placement: Placement, hasNotch: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(entry("Refresh", #selector(refresh)))
        for offered in placement.offered(hasNotch: hasNotch) {
            let item = entry(offered.menuTitle, #selector(place(_:)))
            item.representedObject = offered
            menu.addItem(item)
        }
        if let account = accountItem() {
            menu.addItem(.separator())
            menu.addItem(account)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    private func entry(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Sign in or out, whichever applies. Nothing before the first reading, which has yet to say
    /// which; nothing on the demo set, which has no account. An item without an action shows
    /// disabled while a sign-in is already under way.
    private func accountItem() -> NSMenuItem? {
        if viewModel.isSignedIn {
            return entry("Sign out of Claude", #selector(signOut))
        }
        guard viewModel.hasLoaded, !viewModel.snapshot.isDemo else { return nil }
        return entry("Sign in to Claude…", viewModel.isSigningIn ? nil : #selector(signIn))
    }

    @objc private func refresh() {
        Task { await viewModel.refresh(userInitiated: true) }
    }

    @objc private func place(_ sender: NSMenuItem) {
        guard let placement = sender.representedObject as? Placement else { return }
        viewModel.place(placement)
    }

    @objc private func signIn() {
        viewModel.startSignIn()
    }

    @objc private func signOut() {
        viewModel.signOut()
    }
}
