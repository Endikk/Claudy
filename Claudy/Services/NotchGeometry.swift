import AppKit

/// What macOS says about the top edge of one screen, as plain values.
struct ScreenMetrics: Equatable {
    var frame: CGRect
    /// `safeAreaInsets.top`: the notch's height, zero on a screen without one.
    var safeAreaTop: CGFloat
    /// Width of the menu bar left usable on each side of the notch.
    var leftAreaWidth: CGFloat?
    var rightAreaWidth: CGFloat?
}

extension ScreenMetrics {
    init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width
        )
    }
}

/// The notch of a screen and the screen it sits on, in global screen coordinates.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notch: CGRect

    /// `nil` for a screen without a notch. The notch is what the two usable areas leave between
    /// them. Only their widths are used, so the result does not depend on which coordinate space
    /// macOS reports the areas in.
    init?(_ screen: ScreenMetrics) {
        guard screen.safeAreaTop > 0,
              let left = screen.leftAreaWidth,
              let right = screen.rightAreaWidth else { return nil }
        let width = screen.frame.width - left - right
        guard width > 0 else { return nil }
        screenFrame = screen.frame
        notch = CGRect(
            x: screen.frame.minX + left,
            y: screen.frame.maxY - screen.safeAreaTop,
            width: width,
            height: screen.safeAreaTop
        )
    }

    /// The first notched screen of the list. Only a MacBook's built-in display has one, whether or
    /// not it is the main screen.
    static func find(in screens: [ScreenMetrics]) -> NotchGeometry? {
        screens.lazy.compactMap { NotchGeometry($0) }.first
    }

    static func current() -> NotchGeometry? {
        find(in: NSScreen.screens.map(ScreenMetrics.init))
    }
}
