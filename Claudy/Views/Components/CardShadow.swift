import SwiftUI

/// The widget card's drop shadow, drawn from the card's outline rather than from its content.
///
/// A shadow computed from the content follows the content: glass that lets the desktop through,
/// a mascot redrawn on every frame. The outline never changes, so this shadow looks the same on
/// every Mac, whatever the wallpaper or the transparency settings.
struct CardShadow: View {
    let corner: CGFloat

    var body: some View {
        OutlineShadow(outline: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// The drop shadow of any outline: the card's, and the open notch island's. Only the ring around
/// the outline is painted, within `Theme.Metric.shadowInset` of it: nothing sits under what the
/// outline holds, glass included.
struct OutlineShadow<Outline: Shape>: View {
    let outline: Outline

    var body: some View {
        ZStack {
            outline
                .fill(.black)
                .shadow(color: .black.opacity(Theme.Shadow.opacity), radius: Theme.Shadow.radius, y: Theme.Shadow.offset)
            outline
                .fill(.black)
                .shadow(color: .black.opacity(Theme.Shadow.contactOpacity), radius: Theme.Shadow.contactRadius)
        }
        .mask(
            AroundOutline(outline: outline, reach: Theme.Metric.shadowInset)
                .fill(style: FillStyle(eoFill: true))
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Everything within `reach` points of the outline, the outline itself left out. Animates with
/// the outline, so an island's corners and its shadow's hole stay together.
private struct AroundOutline<Outline: Shape>: Shape {
    var outline: Outline
    let reach: CGFloat

    var animatableData: Outline.AnimatableData {
        get { outline.animatableData }
        set { outline.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -reach, dy: -reach))
        path.addPath(outline.path(in: rect))
        return path
    }
}
