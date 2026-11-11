import AppKit

/// The right-click menu of the menu bar item and of the island: refresh, the other placements,
/// the notifications, the shortcut, the export, the account, quit. Its items target this object,
/// so each owner keeps its own alive.
@MainActor
final class ClaudyMenu: NSObject {

    private let viewModel: UsageViewModel
    private let notifier: Notifier
    /// Whether ⌃⌥C reaches Claudy: another app may hold it.
    private let isHotKeyActive: @MainActor () -> Bool

    init(viewModel: UsageViewModel, notifier: Notifier,
         isHotKeyActive: @escaping @MainActor () -> Bool = { (NSApp.delegate as? AppDelegate)?.isHotKeyActive ?? false }) {
        self.viewModel = viewModel
        self.notifier = notifier
        self.isHotKeyActive = isHotKeyActive
    }

    /// The menu for Claudy as it stands now.
    func make() -> NSMenu {
        make(showing: viewModel.placement, hasNotch: viewModel.hasNotchedScreen)
    }

    func make(showing placement: Placement, hasNotch: Bool) -> NSMenu {
        notifier.refreshPermission()
        let menu = NSMenu()
        menu.addItem(entry("Refresh", #selector(refresh)))
        for offered in placement.offered(hasNotch: hasNotch) {
            let item = entry(offered.menuTitle, #selector(place(_:)))
            item.representedObject = offered
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let notifications = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        notifications.submenu = notificationsMenu()
        menu.addItem(notifications)
        menu.addItem(showOrHideItem())
        menu.addItem(entry("Export usage as CSV…", #selector(export)))
        if let account = accountItem() {
            menu.addItem(.separator())
            menu.addItem(account)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    /// One switch per kind, in two groups. When the user turned Claudy off in System Settings the
    /// switches can do nothing: the first line says so and leads there.
    private func notificationsMenu() -> NSMenu {
        let menu = NSMenu()
        if notifier.isDenied {
            menu.addItem(entry("Turned off in System Settings…", #selector(openNotificationSettings)))
            menu.addItem(.separator())
        }
        let groups: [(String, [NotificationKind])] = [
            ("Quota", NotificationKind.allCases.filter(\.isQuota)),
            ("Sessions and agents", NotificationKind.allCases.filter { !$0.isQuota }),
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(Self.header(group.0))
            for kind in group.1 {
                let item = entry(kind.menuTitle, #selector(toggleNotification(_:)))
                item.representedObject = kind.rawValue
                item.state = notifier.isEnabled(kind) ? .on : .off
                menu.addItem(item)
            }
        }
        return menu
    }

    private static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) { return .sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Shows the shortcut beside it, or says another app took it.
    private func showOrHideItem() -> NSMenuItem {
        guard isHotKeyActive() else {
            return entry("Show or hide Claudy (\(GlobalHotKey.display) is taken)", #selector(toggleClaudy))
        }
        let item = entry("Show or hide Claudy", #selector(toggleClaudy))
        item.keyEquivalent = GlobalHotKey.keyEquivalent
        item.keyEquivalentModifierMask = GlobalHotKey.modifiers
        return item
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

    @objc private func toggleNotification(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = NotificationKind(rawValue: raw) else { return }
        notifier.toggle(kind)
    }

    @objc private func openNotificationSettings() {
        notifier.openSettings()
    }

    @objc private func toggleClaudy() {
        (NSApp.delegate as? AppDelegate)?.toggleClaudy()
    }

    @objc private func export() {
        viewModel.exportUsage()
    }

    @objc private func signIn() {
        viewModel.startSignIn()
    }

    @objc private func signOut() {
        viewModel.signOut()
    }
}
