import SwiftUI

/// La marque Claude, dessinée en vectoriel : rayons effilés à pointes arrondies,
/// longueurs volontairement irrégulières. Aucun asset image, donc aucun catalogue à gérer.
struct ClaudeMark: Shape {

    /// (angle en degrés, longueur relative, demi-largeur relative)
    private static let rays: [(angle: Double, length: Double, width: Double)] = [
        (0, 1.00, 0.150), (33, 0.76, 0.120), (72, 0.94, 0.140),
        (104, 0.68, 0.112), (145, 1.00, 0.150), (180, 0.80, 0.128),
        (212, 0.94, 0.140), (250, 0.70, 0.112), (288, 1.00, 0.150),
        (320, 0.78, 0.126), (350, 0.66, 0.108)
    ]

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * 0.06

        var path = Path()

        for ray in Self.rays {
            let radians = ray.angle * .pi / 180
            let direction = CGVector(dx: cos(radians), dy: sin(radians))
            let normal = CGVector(dx: -direction.dy, dy: direction.dx)

            let outerRadius = radius * ray.length
            let baseHalf = radius * ray.width
            let tipHalf = baseHalf * 0.34

            func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
                CGPoint(
                    x: center.x + direction.dx * along + normal.dx * across,
                    y: center.y + direction.dy * along + normal.dy * across
                )
            }

            path.move(to: point(innerRadius, baseHalf))
            path.addLine(to: point(outerRadius - tipHalf, tipHalf))
            // Pointe arrondie.
            path.addQuadCurve(
                to: point(outerRadius - tipHalf, -tipHalf),
                control: point(outerRadius + tipHalf * 0.6, 0)
            )
            path.addLine(to: point(innerRadius, -baseHalf))
            path.closeSubpath()
        }

        return path
    }
}
