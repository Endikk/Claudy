import SwiftUI

/// Jetons de design de Claudy : couleurs, typographie, métriques.
/// Tout le style visible passe par ici — aucune valeur brute dans les vues.
enum Theme {

    // MARK: - Accents

    /// Palette d'accents. Chaque jauge / modèle porte un accent, jamais une couleur brute.
    enum Accent: CaseIterable {
        case coral, amber, violet, sage, sky

        var color: Color {
            switch self {
            case .coral:  return Color(hex: 0xD97757)
            case .amber:  return Color(hex: 0xE0A34E)
            case .violet: return Color(hex: 0x8B7BD8)
            case .sage:   return Color(hex: 0x6FAE8F)
            case .sky:    return Color(hex: 0x5E9BD1)
            }
        }
    }

    static let danger = Color(hex: 0xE05C4B)

    /// Teinte effective d'une jauge : l'accent de base, sauf en zone de charge haute
    /// où la sémantique « attention » prend le dessus.
    static func tint(_ accent: Accent, at percent: Double) -> Color {
        switch percent {
        case 0.90...:      return danger
        case 0.75..<0.90:  return Accent.amber.color
        default:           return accent.color
        }
    }

    // MARK: - Typographie

    enum Font {
        /// Le grand pourcentage. Chiffres à chasse fixe : sinon la valeur tressaute à chaque refresh.
        static func hero(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
        }
        static func value(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
        static func label(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }

    // MARK: - Métriques

    enum Metric {
        static let fullWidth: CGFloat = 340
        static let minimalWidth: CGFloat = 252
        static let cardCorner: CGFloat = 20
        static let minimalCorner: CGFloat = 15
        /// Marge transparente autour de la carte : c'est là que vit l'ombre portée.
        static let shadowInset: CGFloat = 14
        static let padding: CGFloat = 16
    }

    // MARK: - Animations

    enum Motion {
        static let gauge = SwiftUI.Animation.spring(response: 0.55, dampingFraction: 0.85)
        static let mode = SwiftUI.Animation.spring(response: 0.38, dampingFraction: 0.86)
        static let accordion = SwiftUI.Animation.spring(response: 0.34, dampingFraction: 0.88)
        static let popup = SwiftUI.Animation.spring(response: 0.30, dampingFraction: 0.82)
    }
}

// MARK: - Styles partagés

extension View {
    /// Label discret en capitales : titres de section, en-têtes de colonnes.
    func microLabel(_ opacity: Double = 0.55) -> some View {
        self.font(Theme.Font.label(9.5, .semibold))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(.primary.opacity(opacity))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
