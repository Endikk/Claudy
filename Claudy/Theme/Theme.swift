import SwiftUI

/// Claudy's design tokens: colours, type, metrics. Every visible style goes through here, so no
/// raw values ever appear in the views.
enum Theme {

    /// Accent palette. Every gauge and model carries an accent, never a raw colour.
    enum Accent {
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

    /// Effective tint of a gauge: its base accent, except in the high-load band where the
    /// "warning" meaning takes over.
    static func tint(_ accent: Accent, at percent: Double) -> Color {
        switch percent {
        case 0.90...:      return danger
        case 0.75..<0.90:  return Accent.amber.color
        default:           return accent.color
        }
    }

    enum Font {
        /// The large percentage. Monospaced digits, or the value jitters on every refresh.
        static func hero(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
        }
        static func value(_ size: CGFloat, _ weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
        static func label(_ size: CGFloat, _ weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }

    enum Metric {
        static let fullWidth: CGFloat = 340
        static let minimalWidth: CGFloat = 252
        static let cardCorner: CGFloat = 20
        static let minimalCorner: CGFloat = 15
        /// Transparent margin around the card, where the drop shadow lives. The window is
        /// therefore larger than the visible card by `shadowInset` on each edge, so any on-screen
        /// positioning must reason about the *visual* rectangle.
        static let shadowInset: CGFloat = 14
        /// Gap between the visible card and the screen edge, in its anchor corner.
        static let screenMargin: CGFloat = 8
        static let padding: CGFloat = 16
        /// Height of the usage/ports switch, and the corner of its selected segment.
        static let tabHeight: CGFloat = 22
        static let tabCorner: CGFloat = 7
    }

    enum Motion {
        static let gauge = SwiftUI.Animation.spring(response: 0.55, dampingFraction: 0.85)
        static let mode = SwiftUI.Animation.spring(response: 0.38, dampingFraction: 0.86)
        static let accordion = SwiftUI.Animation.spring(response: 0.34, dampingFraction: 0.88)
        static let popup = SwiftUI.Animation.spring(response: 0.30, dampingFraction: 0.82)
    }
}

extension View {
    /// Quiet uppercase label: section titles and column headers.
    func microLabel(_ opacity: Double) -> some View {
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
