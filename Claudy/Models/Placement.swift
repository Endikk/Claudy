import Foundation

/// Where Claudy shows itself: the floating card, the menu bar item, or the island around the
/// notch. One at a time.
enum Placement: String, CaseIterable {
    case widget, menuBar, notch

    /// The placement saved under `claudy.placement`. Before that key existed only the menu bar
    /// flag did, and it still decides until a placement is saved: an update leaves Claudy where
    /// the user kept it.
    static func stored(raw: String?, legacyInMenuBar: Bool) -> Placement {
        if let raw, let placement = Placement(rawValue: raw) { return placement }
        return legacyInMenuBar ? .menuBar : .widget
    }

    /// What is actually shown. The island needs a notch: without one Claudy waits in the menu
    /// bar, and the choice itself is kept for when the screen comes back.
    func effective(hasNotch: Bool) -> Placement {
        self == .notch && !hasNotch ? .menuBar : self
    }

    /// What a menu proposes: every placement but the one on screen, the notch only when a
    /// screen has one. Measured from the effective placement, so the menu bar item standing in
    /// for the island does not offer the menu bar.
    func offered(hasNotch: Bool) -> [Placement] {
        let shown = effective(hasNotch: hasNotch)
        return Placement.allCases.filter { $0 != shown && ($0 != .notch || hasNotch) }
    }

    var menuTitle: String {
        switch self {
        case .widget: "Show floating widget"
        case .menuBar: "Show in menu bar"
        case .notch: "Show in notch"
        }
    }

    /// The SF Symbol beside the entry in the card's context menu.
    var systemImage: String {
        switch self {
        case .widget: "macwindow"
        case .menuBar: "menubar.arrow.up.rectangle"
        case .notch: "rectangle.topthird.inset.filled"
        }
    }
}
