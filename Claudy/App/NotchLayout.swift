import CoreGraphics

/// Where the island's window goes: hung from the top edge of the notched screen, centred on the
/// notch, never past the screen's sides.
struct NotchLayout: Equatable {
    let geometry: NotchGeometry

    /// Width of each ear: the mascot on the left of the notch, the percentage on its right.
    static let earWidth: CGFloat = 48

    /// The notch plus one ear on each side, the notch's height.
    var restingSize: CGSize {
        CGSize(width: geometry.notch.width + 2 * Self.earWidth, height: geometry.notch.height)
    }

    var restingFrame: CGRect { frame(for: restingSize) }

    /// The window for a shape of `size`, open or not.
    func frame(for size: CGSize) -> CGRect {
        let screen = geometry.screenFrame
        let width = min(size.width, screen.width)
        let height = min(size.height, screen.height)
        let x = min(max(geometry.notch.midX - width / 2, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }

    /// The frame to take now and the one to settle on once the shape stops moving. Both frames
    /// hang from the same top edge, so their union is the larger one: growing is immediate and
    /// the opening shape is never cut, shrinking waits until the closing shape fits.
    static func step(from current: CGRect, to target: CGRect) -> (now: CGRect, settle: CGRect) {
        (current.isEmpty ? target : current.union(target), target)
    }
}
