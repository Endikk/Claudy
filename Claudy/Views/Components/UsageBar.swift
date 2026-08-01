import SwiftUI

/// Barre de progression : rail creusé, remplissage dégradé, halo de la teinte,
/// et repère de rythme optionnel.
struct UsageBar: View {
    let percent: Double
    let tint: Color
    let height: CGFloat
    var showsGlow: Bool = true

    /// Position 0…1 du repère : la part de la fenêtre déjà écoulée. Le remplissage à gauche du
    /// repère signifie « en avance sur l'horloge », à droite « sous le rythme ».
    /// `nil` sur les barres qui expriment une part et non une durée (répartitions).
    var pace: Double?

    private var clamped: Double { min(max(percent, 0), 1) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.primary.opacity(0.09))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.72), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    // Plancher à `height` : une valeur infime reste lisible au lieu de disparaître.
                    .frame(width: max(height, geometry.size.width * clamped))
                    .shadow(color: showsGlow ? tint.opacity(0.45) : .clear, radius: 5, y: 1)

                if let pace {
                    marker(in: geometry.size, at: min(max(pace, 0), 1))
                }
            }
        }
        .frame(height: height)
        .animation(Theme.Motion.gauge, value: clamped)
    }

    private func marker(in size: CGSize, at pace: Double) -> some View {
        let width = max(1.5, height * 0.28)
        // Le repère tombe soit sur le remplissage, soit sur le rail vide : sans ce basculement,
        // il disparaît sur l'un des deux fonds — en clair comme en sombre.
        let onFill = pace <= clamped

        return RoundedRectangle(cornerRadius: width / 2, style: .continuous)
            .fill(onFill ? Color.white.opacity(0.92) : Color.primary.opacity(0.45))
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(onFill ? 0.35 : 0), radius: 1.5)
            .offset(x: (size.width - width) * pace)
            .animation(Theme.Motion.gauge, value: pace)
    }
}
