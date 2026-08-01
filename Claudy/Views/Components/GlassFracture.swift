import SwiftUI

/// Fracture de surcharge : le verre de la carte se fend au-delà de 95 %.
///
/// La fracture vit **dans le fond**, sous le contenu : la carte reste parfaitement
/// lisible à 100 % de charge, seule la matière change. Le tracé est déterministe
/// (graine fixe) — sinon la fissure se redessinerait à chaque passe de layout.
///
/// L'effet tient en trois couches empilées, pas en un trait : un éclat de verre
/// déplacé qui capte la lumière, un creux sombre et flou, une arête claire décalée
/// d'un demi-point. C'est le décalage arête/creux qui fait lire « verre », pas le trait.
struct GlassFracture: View {
    /// 0…1 — 0 sous 95 % de charge, 1 à 100 %.
    let intensity: Double

    /// Plafond d'opacité, atteint à 100 % de charge. La fissure doit rester un **signal**
    /// perçu du coin de l'œil, pas un dessin qui prend la carte : au-delà, elle capte le
    /// regard avant les chiffres, qui sont la raison d'être du widget.
    private static let ceiling = 0.5

    /// Opacité effective des couches.
    private var presence: Double { intensity * Self.ceiling }

    var body: some View {
        ZStack {
            // 1. Éclats : les quartiers de verre déplacés renvoient la lumière.
            Fracture(.shards)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.09 * presence), .white.opacity(0.005 * presence)],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )

            // 2. Le creux : ombre floue sous le trait, elle donne son épaisseur au verre.
            Fracture(.major)
                .stroke(.black.opacity(0.40 * presence), style: stroke(2.4))
                .blur(radius: 1.5)
            Fracture(.minor)
                .stroke(.black.opacity(0.26 * presence), style: stroke(1.6))
                .blur(radius: 1.2)

            // 3. L'arête, décalée vers la source de lumière (haut-gauche, comme le reste
            //    de la carte) : c'est ce décalage qui creuse la fissure au lieu de la peindre.
            Group {
                Fracture(.major).stroke(.white.opacity(0.50 * presence), style: stroke(0.7))
                Fracture(.minor).stroke(.white.opacity(0.28 * presence), style: stroke(0.6))
            }
            .offset(x: -0.5, y: -0.5)

            // 4. Teinte d'alerte : la fracture rougit à mesure que la charge sature.
            Fracture(.major).stroke(Theme.danger.opacity(0.40 * presence), style: stroke(0.8))

            // 5. Halo au point d'impact : la lueur qui signale la surcharge de loin.
            RadialGradient(
                colors: [Theme.danger.opacity(0.18 * presence), .clear],
                center: UnitPoint(x: Fracture.impact.x, y: Fracture.impact.y),
                startRadius: 0,
                endRadius: 130
            )
        }
        .allowsHitTesting(false)
    }

    private func stroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

// MARK: - Tracé

/// Le réseau de fêlures, en trois rôles tirés d'un **même** plan géométrique : les couches
/// de `GlassFracture` doivent se superposer au pixel près, sinon l'arête flotte à côté du creux.
private struct Fracture: Shape {
    enum Role { case major, minor, shards }

    let role: Role

    init(_ role: Role) { self.role = role }

    /// Point d'impact, en coordonnées relatives : coin haut-droit, au-dessus de l'avatar —
    /// la zone la moins chargée en contenu.
    static let impact = CGPoint(x: 0.86, y: 0.10)

    /// Éclats courts autour du choc : ils forment la toile. Le verre casse **dense au point
    /// d'impact et clairsemé au loin** — c'est ce contraste qui fait lire la cassure.
    private static let rayCount = 9

    /// Caps des longues fractures qui s'échappent vers le corps de la carte
    /// (0° = vers la droite, 90° = vers le bas). Trois suffisent : au-delà, la carte se
    /// couvre de traits et l'impact ne se lit plus.
    /// Aucune ne remonte vers le haut : une fracture qui rase le bord se confond avec le
    /// liseré de la carte.
    private static let runners: [Double] = [104, 138, 171]

    /// Distances relatives des anneaux de toile, en fraction de la longueur des éclats.
    private static let webRings: [Double] = [0.42, 0.72, 1.0]

    /// Quartiers remplis, par index d'éclat : un secteur sur trois, jamais tous —
    /// un remplissage uniforme donnerait un voile, pas du verre.
    private static let shardSlots: [Int] = [1, 5]

    func path(in rect: CGRect) -> Path {
        let plan = Self.plan(in: rect)
        var path = Path()

        switch role {
        case .major:
            for line in plan.majors { Self.add(&path, line) }
        case .minor:
            for line in plan.minors { Self.add(&path, line) }
        case .shards:
            for shard in plan.shards { Self.addClosed(&path, shard) }
        }
        return path
    }

    // MARK: Plan

    private struct Plan {
        var majors: [[CGPoint]] = []
        var minors: [[CGPoint]] = []
        var shards: [[CGPoint]] = []
    }

    /// Construit le réseau complet en une passe. Tous les rôles rejouent cette même passe
    /// avec la même graine : le tirage est donc identique d'une couche à l'autre.
    private static func plan(in rect: CGRect) -> Plan {
        var plan = Plan()
        var random = Seeded(state: 0x0C1A_5EED)
        let diagonal = sqrt(rect.width * rect.width + rect.height * rect.height)
        let center = CGPoint(
            x: rect.minX + impact.x * rect.width,
            y: rect.minY + impact.y * rect.height
        )

        // 1. Éclats du choc : courts, tout autour du point d'impact. Le coin en rogne la
        //    moitié — c'est voulu, le choc est au bord, pas au centre d'une étoile.
        var rays: [[CGPoint]] = []
        for index in 0..<rayCount {
            let base = Double(index) * 360 / Double(rayCount)
            let angle = base + (random.next() - 0.5) * 20
            // Longueurs très inégales : des éclats calibrés donneraient un polygone régulier,
            // et la toile lirait « toile d'araignée » au lieu de « verre ».
            let length = diagonal * (0.035 + random.next() * 0.135)
            let ray = polyline(from: center, angle: angle, length: length,
                               segments: 2, drift: 9, in: rect, random: &random)
            rays.append(ray)
            plan.minors.append(ray)
        }

        // 2. Toile : segments droits reliant deux éclats voisins à distance comparable du
        //    choc. Ce sont eux qui referment les quartiers et font lire « verre » plutôt
        //    que « rayures ».
        for ring in webRings {
            for index in 0..<rays.count {
                // Un segment sur trois manque et chaque accroche glisse le long de son
                // éclat : un anneau complet et régulier ferait une toile d'araignée.
                guard random.next() > 0.32,
                      let a = point(on: rays[index], at: jitter(ring, &random)),
                      let b = point(on: rays[(index + 1) % rays.count], at: jitter(ring, &random))
                else { continue }
                plan.minors.append([a, b])
            }
        }

        // 3. Longues fractures : elles s'échappent du choc vers le corps de la carte.
        //    Peu de coudes, dérive de cap faible — un trait qui casse net lit « verre »,
        //    une ligne sinueuse lit « cheveu ».
        for cap in runners {
            let angle = cap + (random.next() - 0.5) * 10
            // Assez longue pour sortir du cadre à coup sûr : une fracture principale qui
            // s'arrête en plein verre trahit le dessin (les embranchements, eux, peuvent).
            let length = diagonal * (0.95 + random.next() * 0.45)
            plan.majors.append(
                polyline(from: center, angle: angle, length: length,
                         segments: 4, drift: 6, in: rect, random: &random)
            )
        }

        // 4. Un embranchement par longue fracture, aux deux tiers du trajet : la cassure
        //    gagne la surface sans multiplier les départs depuis le point de choc.
        for line in plan.majors {
            guard line.count >= 3 else { continue }
            let index = max(1, line.count * 2 / 3)
            let fork = line[index]
            let heading = angle(from: line[index - 1], to: fork)
            let side: Double = random.next() > 0.5 ? 1 : -1
            plan.minors.append(
                polyline(from: fork, angle: heading + side * (24 + random.next() * 16),
                         length: diagonal * (0.10 + random.next() * 0.10),
                         segments: 2, drift: 7, in: rect, random: &random)
            )
        }

        // 5. Quartiers pleins : le secteur choc → éclat → éclat voisin, refermé sur
        //    l'anneau extérieur de la toile.
        for slot in shardSlots {
            let next = (slot + 1) % rays.count
            guard slot < rays.count, let ring = webRings.last,
                  let a = point(on: rays[slot], at: ring),
                  let b = point(on: rays[next], at: ring) else { continue }
            plan.shards.append([center, a, b])
        }

        return plan
    }

    // MARK: Géométrie

    /// Ligne brisée : peu de segments, longs, avec une légère dérive de cap à chaque coude.
    /// Le tracé continue **hors cadre** — la carte le rogne, et une fissure qui s'arrête en
    /// plein verre trahit le dessin.
    private static func polyline(from origin: CGPoint, angle: Double, length: CGFloat,
                                 segments: Int, drift: Double, in rect: CGRect,
                                 random: inout Seeded) -> [CGPoint] {
        var points = [origin]
        var point = origin
        var heading = angle
        let step = length / CGFloat(segments)
        // Marge au-delà de laquelle poursuivre le tracé ne change plus rien à l'écran.
        let bounds = rect.insetBy(dx: -step, dy: -step)

        for _ in 0..<segments {
            heading += (random.next() - 0.5) * drift * 2
            let radians = heading * .pi / 180
            let next = CGPoint(x: point.x + cos(radians) * step, y: point.y + sin(radians) * step)
            points.append(next)
            point = next
            guard bounds.contains(next) else { break }
        }
        return points
    }

    private static func add(_ path: inout Path, _ points: [CGPoint]) {
        guard let first = points.first, points.count > 1 else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
    }

    private static func addClosed(_ path: inout Path, _ points: [CGPoint]) {
        guard let first = points.first, points.count > 2 else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
    }

    /// Point situé à une fraction donnée d'une ligne brisée (interpolation sur les sommets).
    private static func point(on polyline: [CGPoint], at fraction: Double) -> CGPoint? {
        guard polyline.count > 1 else { return nil }
        let position = fraction * Double(polyline.count - 1)
        let index = min(Int(position), polyline.count - 2)
        let local = CGFloat(position - Double(index))
        let a = polyline[index]
        let b = polyline[index + 1]
        return CGPoint(x: a.x + (b.x - a.x) * local, y: a.y + (b.y - a.y) * local)
    }

    /// Décale l'accroche d'un segment de toile le long de son éclat, en restant dans le tracé.
    private static func jitter(_ ring: Double, _ random: inout Seeded) -> Double {
        min(max(ring + (random.next() - 0.5) * 0.26, 0.12), 1)
    }

    private static func angle(from a: CGPoint, to b: CGPoint) -> Double {
        atan2(Double(b.y - a.y), Double(b.x - a.x)) * 180 / .pi
    }
}

/// Générateur congruentiel linéaire : suite pseudo-aléatoire reproductible.
/// `Double.random` rendrait des fissures différentes à chaque passe de layout.
private struct Seeded {
    var state: UInt64

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF)
    }
}
