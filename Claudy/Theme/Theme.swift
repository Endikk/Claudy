import SwiftUI

/// Claudy's design tokens: colours, type, metrics. Every visible style goes through here, so no
/// raw values ever appear in the views.
enum Theme {

    /// Accent palette. Every gauge and model carries an accent, never a raw colour: one colour
    /// per thing measured, Claude's coral first. Amber names no window: it only warns, so a gauge
    /// that turns amber always means "look".
    enum Accent {
        case coral, amber, violet, sage, sky, teal

        var color: Color {
            switch self {
            case .coral:  return Color(hex: 0xD97757)
            case .amber:  return Color(hex: 0xF2A93B)
            case .violet: return Color(hex: 0xA67CF7)
            case .sage:   return Color(hex: 0x6FAE8F)
            case .sky:    return Color(hex: 0x4FA8F7)
            case .teal:   return Color(hex: 0x3EC6BC)
            }
        }
    }

    static let danger = Color(hex: 0xF0604D)
    /// Good news: on pace, or behind it.
    static let positive = Color(hex: 0x4CC38A)
    /// Text set on a filled accent: white on coral is 3.1 to 1, this dark ink is above 5.
    static let onAccent = Color(hex: 0x1F1A17)
    /// An agent fallen silent: its Claudy loses its colour.
    static let idle = Color(hex: 0x8F8A86)

    /// The agents' Claudys, one colour each in launch order. Never coral, the main Claudy's, nor
    /// amber, which warns: an agent's Claudy must not pass for the quota's.
    static let agentTints: [Color] = [
        Accent.sky.color,
        Accent.violet.color,
        Color(hex: 0xD9779B),   // rose
        Accent.sage.color,
    ]

    /// Effective tint of a gauge: its base accent, except in the high-load band where the
    /// "warning" meaning takes over.
    static func tint(_ accent: Accent, at percent: Double) -> Color {
        switch percent {
        case 0.90...:      return danger
        case 0.75..<0.90:  return Accent.amber.color
        default:           return accent.color
        }
    }

    /// An accent used as text. Fills keep the accent itself; text on a light surface takes a
    /// darker shade of it, or amber and green fall under 2.5 to 1.
    enum Ink {
        case coral, amber, danger, positive, sky, violet, teal

        func color(_ scheme: ColorScheme) -> Color {
            let isDark = scheme == .dark
            switch self {
            case .coral:    return isDark ? Accent.coral.color : Color(hex: 0xAD5130)
            case .amber:    return isDark ? Accent.amber.color : Color(hex: 0x95600F)
            case .danger:   return isDark ? Theme.danger : Color(hex: 0xBB3828)
            case .positive: return isDark ? Theme.positive : Color(hex: 0x2B7550)
            case .sky:      return isDark ? Accent.sky.color : Color(hex: 0x1F6AB0)
            case .violet:   return isDark ? Accent.violet.color : Color(hex: 0x6B44C9)
            case .teal:     return isDark ? Accent.teal.color : Color(hex: 0x1D7F78)
            }
        }
    }

    /// The warm veil laid over the card's glass: dark clay at night, paper by day. Without it the
    /// glass takes the wallpaper's colour and the text goes grey on grey.
    static func veil(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1C1714).opacity(0.64) : Color(hex: 0xFFF8EE).opacity(0.45)
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
        /// Ports, commands, file names: what a developer types.
        static func mono(_ size: CGFloat, _ weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
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
        /// The notch island open: wide and low, like a Live Activity.
        static let islandWidth: CGFloat = 440
        /// The card's glass, concentric with its tiles: tile corner plus the panel's padding.
        static let cardCorner: CGFloat = 28
        static let minimalCorner: CGFloat = 22
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
        /// Inside the card: from its edge to the tiles, and between two tiles.
        static let panelPadding: CGFloat = 10
        static let gap: CGFloat = 8
        /// One block of the card, as in Control Center: a tile of glass.
        static let tileCorner: CGFloat = 18
        static let tilePadding: CGFloat = 14
        /// Height of a tab of the card's switch.
        static let tabHeight: CGFloat = 28
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

    /// Springs damped enough that nothing bounces: a gauge settles, it does not wobble.
    enum Motion {
        static let gauge = SwiftUI.Animation.spring(response: 0.55, dampingFraction: 0.95)
        static let mode = SwiftUI.Animation.spring(response: 0.38, dampingFraction: 0.95)
        static let accordion = SwiftUI.Animation.spring(response: 0.34, dampingFraction: 0.95)
        static let popup = SwiftUI.Animation.spring(response: 0.30, dampingFraction: 0.92)
        /// Hover and press feedback.
        static let feedback = SwiftUI.Animation.easeOut(duration: 0.15)
    }
}

extension View {
    /// Section titles and column headers, in sentence case.
    func sectionLabel() -> some View {
        font(Theme.Font.label(11, .medium)).foregroundStyle(.secondary)
    }

    /// Counts, times and captions under a figure.
    func meta() -> some View {
        font(Theme.Font.value(11, .regular)).foregroundStyle(.secondary)
    }

    /// An accent as text, readable on light and dark glass alike.
    func ink(_ ink: Theme.Ink) -> some View {
        modifier(InkStyle(ink: ink))
    }

    /// The card's surface: Liquid Glass from macOS 26, the window material before it, the warm
    /// veil under the content in both.
    func cardSurface(corner: CGFloat) -> some View {
        modifier(CardSurface(corner: corner))
    }

    /// One block of the card: a tile of glass, washed with the colour of what it shows.
    func tile(_ tint: Color? = nil, strength: Double = 0.16,
              padding: CGFloat = Theme.Metric.tilePadding) -> some View {
        modifier(Tile(tint: tint, strength: strength, padding: padding))
    }
}

private struct InkStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let ink: Theme.Ink

    func body(content: Content) -> some View {
        content.foregroundStyle(ink.color(scheme))
    }
}

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let corner: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        // Liquid Glass needs the macOS 26 SDK: an older Xcode builds the fallback alone.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            // One container for the card and its tiles: glass cannot sample other glass, the
            // container renders them together.
            GlassEffectContainer(spacing: Theme.Metric.gap) {
                content
                    .background(shape.fill(Theme.veil(scheme)))
                    .glassEffect(.regular, in: shape)
            }
        } else {
            // The material that least follows the wallpaper. `.hudWindow` turned mid-grey in dark
            // mode over a light wallpaper, and in light mode over a dark one: grey text on grey.
            content
                .background(
                    ZStack {
                        VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
                        Theme.veil(scheme)
                    }
                )
                .clipShape(shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1))
        }
        #else
        // The material that least follows the wallpaper. `.hudWindow` turned mid-grey in dark
        // mode over a light wallpaper, and in light mode over a dark one: grey text on grey.
        content
            .background(
                ZStack {
                    VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
                    Theme.veil(scheme)
                }
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1))
        #endif
    }
}

private struct Tile: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let tint: Color?
    let strength: Double
    let padding: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metric.tileCorner, style: .continuous)
        // A tint reads weaker on dark glass: half as much again there.
        let wash = tint.map { $0.opacity(strength * (scheme == .dark ? 1.5 : 1)) }
            ?? Color.black.opacity(scheme == .dark ? 0.12 : 0)
        let washed = content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(wash))
        // Liquid Glass needs the macOS 26 SDK: an older Xcode builds the fallback alone.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            washed.glassEffect(.regular, in: shape)
        } else {
            washed
                .background(shape.fill(.primary.opacity(0.05)))
                .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        }
        #else
        washed
            .background(shape.fill(.primary.opacity(0.05)))
            .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        #endif
    }
}

/// The thin line that separates two subjects lying on the card's glass, where a tile would have
/// been one block too many.
struct Hairline: View {
    var isVertical = false

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(width: isVertical ? 1 : nil, height: isVertical ? nil : 1)
            .padding(isVertical ? .vertical : .horizontal, 6)
    }
}

/// A capsule button. Prominent, it is filled with its tint and lettered in dark ink; quiet, the
/// tint only washes it. Glass from macOS 26, lit by the pointer. The fill is drawn by the button
/// itself: the system's tinted glass turns grey whenever Claudy's panel is not the key window,
/// which is most of the time.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.Accent.coral.color
    var isProminent = true
    var isLarge = false

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, tint: tint, isProminent: isProminent, isLarge: isLarge)
    }
}

private struct PillButton: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let isProminent: Bool
    let isLarge: Bool
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    var body: some View {
        let pill = configuration.label
            .font(Theme.Font.label(isLarge ? 14 : 12, .semibold))
            .foregroundStyle(isProminent ? Theme.onAccent : tint)
            .lineLimit(1)
            .padding(.horizontal, isLarge ? 16 : 12)
            .frame(minHeight: isLarge ? 38 : 26)
            .background(Capsule().fill(isProminent ? tint : tint.opacity(configuration.isPressed ? 0.28 : 0.16)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Theme.Motion.feedback, value: configuration.isPressed)
        // Liquid Glass needs the macOS 26 SDK: an older Xcode builds the fallback alone.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            pill.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            pill
        }
        #else
        pill
        #endif
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
