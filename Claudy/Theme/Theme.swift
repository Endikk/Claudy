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

    /// Fixed inks of the pixel mascot (ClaudyTyping). The body itself takes the caller's tint;
    /// its light and dark faces lean warm and cool, as pixel artists shift hue with the light.
    enum Pixel {
        static let highlight = Color(hex: 0xFFE3B0).opacity(0.35)
        static let shade = Color(hex: 0x3A1030).opacity(0.38)
        static let outline = Color(hex: 0x1E0A12).opacity(0.78)
        static let eye = Color(hex: 0x2A1418)
        static let keys = Color(hex: 0x9A9CA6)
        static let laptop = Color(hex: 0x464652)
        static let lid = Color(hex: 0x70727E)
        static let screenGlow = Color(hex: 0xC8E4FF)
        static let deskTop = Color(hex: 0xB08462)
        static let deskFront = Color(hex: 0x8C6248)
        static let deskSide = Color(hex: 0x68463C)

        // Overload: the explosion, its smoke, and Claude turned to ash.
        static let flash = Color(hex: 0xFFF8D6)
        static let fireYellow = Color(hex: 0xFFD24A)
        static let fireOrange = Color(hex: 0xFF8A2A)
        static let fireRed = Color(hex: 0xD8402A)
        static let ember = Color(hex: 0xFF6A20)
        static let smokeDark = Color(hex: 0x3C3638)
        static let smoke = Color(hex: 0x5E5658)
        static let smokeLight = Color(hex: 0x8A8083)
        static let smokePale = Color(hex: 0xBEB6B8)
        static let charred = Color(hex: 0x2A2426)
        static let ash = Color(hex: 0x968682)
        static let ashTop = Color(hex: 0xB2A49E)
        static let ashSide = Color(hex: 0x6E6060)
        /// Under the waving Claudy: a soft shadow, the only translucent ink.
        static let groundShadow = Color.black.opacity(0.2)
    }

    enum Metric {
        static let fullWidth: CGFloat = 340
        static let minimalWidth: CGFloat = 252
        static let menuBarWidth: CGFloat = 290
        static let cardCorner: CGFloat = 20
        static let minimalCorner: CGFloat = 15
        /// Transparent margin around the card, where the drop shadow lives. The window is
        /// therefore larger than the visible card by `shadowInset` on each edge, so any on-screen
        /// positioning must reason about the *visual* rectangle.
        ///
        /// Derived from the shadow: a Gaussian shadow only fades out some three radii past its
        /// offset edge, and the window edge cuts whatever is left, which shows as a grey box
        /// around the card on a light wallpaper.
        static let shadowInset: CGFloat = (3 * Shadow.radius + abs(Shadow.offset)).rounded(.up)
        /// Gap between the visible card and the screen edge, in its anchor corner.
        static let screenMargin: CGFloat = 8
        static let padding: CGFloat = 16
        /// Height of the usage/ports switch, and the corner of its selected segment.
        static let tabHeight: CGFloat = 22
        static let tabCorner: CGFloat = 7
    }

    /// The card's drop shadow, drawn by `CardShadow`.
    enum Shadow {
        static let radius: CGFloat = 8
        static let offset: CGFloat = 4
        static let opacity: Double = 0.3
        /// A tight second shadow that keeps the card's edge drawn on a white wallpaper.
        static let contactRadius: CGFloat = 1
        static let contactOpacity: Double = 0.18
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
