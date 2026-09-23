import SwiftUI

/// The widget card's drop shadow, drawn from the card's outline rather than from its content.
///
/// A shadow computed from the content follows the content: glass that lets the desktop through,
/// a mascot redrawn on every frame. The outline never changes, so this shadow looks the same on
/// every Mac, whatever the wallpaper or the transparency settings.
///
/// Only the ring around the card is painted: nothing sits under the translucent glass.
struct CardShadow: View {
    let corner: CGFloat

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            outline
                .fill(.black)
                .shadow(color: .black.opacity(Theme.Shadow.opacity), radius: Theme.Shadow.radius, y: Theme.Shadow.offset)
            outline
                .fill(.black)
                .shadow(color: .black.opacity(Theme.Shadow.contactOpacity), radius: Theme.Shadow.contactRadius)
        }
        .mask(
            AroundCard(corner: corner, reach: Theme.Metric.shadowInset)
                .fill(style: FillStyle(eoFill: true))
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Everything within `reach` points of the card, the card itself left out.
private struct AroundCard: Shape {
    let corner: CGFloat
    let reach: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -reach, dy: -reach))
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        return path
    }
}
