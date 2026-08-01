import SwiftUI

/// Fissures de surcharge : la carte se craquèle quand une fenêtre dépasse 95 %.
///
/// Le tracé est **déterministe** (générateur à graine fixe) : les mêmes fissures à chaque
/// rendu, sinon la carte grésillerait à chaque rafraîchissement. Seule l'opacité varie,
/// de 95 % (à peine visible) à 100 % (franc).
struct CrackOverlay: View {
    /// 0…1
    let intensity: Double

    var body: some View {
        ZStack {
            // Deux passes : une ombre floue qui creuse le verre, un éclat fin par-dessus.
            CrackPattern()
                .stroke(.black.opacity(0.5 * intensity),
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .blur(radius: 1.6)

            CrackPattern()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.75 * intensity),
                                 Theme.danger.opacity(0.65 * intensity)],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    ),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                )
        }
        .allowsHitTesting(false)
    }
}

/// Réseau de fêlures façon impact : des rayons partent d'un point de choc, reliés entre eux
/// par des segments concentriques (la « toile »), plus deux longues fêlures traversantes.
///
/// Les segments sont volontairement **longs et rectilignes**, avec des coudes nets : c'est
/// l'angle vif qui fait lire « verre cassé ». Des micro-segments donneraient des cheveux.
private struct CrackPattern: Shape {

    /// Point de choc, en coordonnées relatives. Coin haut-droit, sur l'avatar : c'est la
    /// zone la moins chargée en texte, la carte reste lisible sous les fêlures.
    private static let impact = CGPoint(x: 0.84, y: 0.11)
    /// Éclats courts autour du choc.
    private static let rayCount = 7
    /// Distances relatives des anneaux de toile, en fraction de la longueur des rayons.
    private static let webRings: [Double] = [0.48, 0.84]
    /// Caps des longues fêlures qui s'échappent du choc vers le corps de la carte.
    private static let runners: [Double] = [100, 136, 172]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var random = Seeded(state: 0x0C1A_5EED)
        let diagonal = sqrt(rect.width * rect.width + rect.height * rect.height)

        let center = CGPoint(
            x: rect.minX + Self.impact.x * rect.width,
            y: rect.minY + Self.impact.y * rect.height
        )

        // 1. Éclats courts autour du choc — chacun mémorise ses points pour la toile.
        var rays: [[CGPoint]] = []
        for index in 0..<Self.rayCount {
            let base = Double(index) * 360 / Double(Self.rayCount)
            let angle = base + (random.next() - 0.5) * 24
            let length = diagonal * (0.10 + random.next() * 0.16)
            let points = polyline(from: center, angle: angle, length: length,
                                  segments: 3, drift: 12, in: rect, random: &random)
            rays.append(points)
            stroke(&path, points)
        }

        // 2. Toile : segments reliant deux éclats voisins à distance comparable du choc.
        //    C'est elle qui fait lire « verre » plutôt que « rayures ».
        for ring in Self.webRings {
            for index in 0..<rays.count {
                let current = rays[index]
                let next = rays[(index + 1) % rays.count]
                guard let a = point(on: current, at: ring), let b = point(on: next, at: ring) else { continue }
                path.move(to: a)
                path.addLine(to: b)
            }
        }

        // 3. Longues fêlures qui filent du choc vers le reste de la carte, avec un
        //    embranchement chacune : la cassure gagne toute la surface sans la saturer.
        for cap in Self.runners {
            let angle = cap + (random.next() - 0.5) * 16
            let length = diagonal * (0.58 + random.next() * 0.26)
            let points = polyline(from: center, angle: angle, length: length,
                                  segments: 5, drift: 11, in: rect, random: &random)
            stroke(&path, points)

            guard points.count >= 3 else { continue }
            let fork = points[points.count - 2]
            let side: Double = random.next() > 0.5 ? 1 : -1
            stroke(&path, polyline(from: fork, angle: angle + side * (30 + random.next() * 22),
                                   length: length * 0.30, segments: 2, drift: 9,
                                   in: rect, random: &random))
        }

        return path
    }

    /// Ligne brisée : peu de segments, longs, avec une légère dérive de cap à chaque coude.
    private func polyline(from origin: CGPoint, angle: Double, length: CGFloat,
                          segments: Int, drift: Double, in rect: CGRect,
                          random: inout Seeded) -> [CGPoint] {
        var points = [origin]
        var point = origin
        var heading = angle
        let step = length / CGFloat(segments)

        for _ in 0..<segments {
            heading += (random.next() - 0.5) * drift * 2
            let radians = heading * .pi / 180
            let next = CGPoint(x: point.x + cos(radians) * step, y: point.y + sin(radians) * step)
            // Une fêlure qui sort du cadre s'arrête au bord : le clip ferait le reste, mais
            // poursuivre le tracé hors champ fausse les points d'accroche de la toile.
            guard rect.insetBy(dx: -1, dy: -1).contains(next) else { break }
            points.append(next)
            point = next
        }
        return points
    }

    private func stroke(_ path: inout Path, _ points: [CGPoint]) {
        guard let first = points.first, points.count > 1 else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
    }

    /// Point situé à une fraction donnée d'une ligne brisée (interpolation sur les sommets).
    private func point(on polyline: [CGPoint], at fraction: Double) -> CGPoint? {
        guard polyline.count > 1 else { return nil }
        let position = fraction * Double(polyline.count - 1)
        let index = min(Int(position), polyline.count - 2)
        let local = CGFloat(position - Double(index))
        let a = polyline[index]
        let b = polyline[index + 1]
        return CGPoint(x: a.x + (b.x - a.x) * local, y: a.y + (b.y - a.y) * local)
    }
}

/// Générateur congruentiel linéaire : suite pseudo-aléatoire reproductible.
/// `Math.random` rendrait des fissures différentes à chaque passe de layout.
private struct Seeded {
    var state: UInt64

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF)
    }
}
