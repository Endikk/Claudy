import CoreGraphics
import Foundation

/// What an hour of the day does to the room: the sky in its window, how many of the city's
/// windows are lit, where the sun or the moon stands, and how much the room itself dims.
struct RoomSky: Equatable, Sendable {

    /// 0 to 24.
    let hour: Double

    init(hour: Double) {
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        self.hour = wrapped < 0 ? wrapped + 24 : wrapped
    }

    /// The hour on the Mac's clock, minutes and seconds as a fraction: the room is lit for it.
    static func hour(at date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
    }

    // MARK: - Moments

    /// The four skies the day passes through, and what each does to the room.
    private struct Moment {
        let bands: [UInt32]
        /// 0 by day, 1 at night: how far the city has turned to silhouettes.
        let darkness: Double
        /// The colour the room is multiplied by. White leaves it as drawn.
        let dim: UInt32

        static let night = Moment(bands: [0x101421, 0x131827, 0x161C2E, 0x192035, 0x1D253D, 0x212A45, 0x25304D, 0x2A3656],
                                  darkness: 1, dim: 0x7A80AA)
        static let dawn = Moment(bands: [0x5A6A8C, 0x7C7A98, 0xA68A9A, 0xCC9A90, 0xE8A882, 0xF2B87A, 0xF6C988, 0xF9DA9E],
                                 darkness: 0.45, dim: 0xE9DCE2)
        static let day = Moment(bands: [0x5FA8E4, 0x6FB3E8, 0x80BEEB, 0x92C8EE, 0xA4D2F1, 0xB6DBF3, 0xC8E4F5, 0xDAECF7],
                                darkness: 0, dim: 0xFFFFFF)
        static let dusk = Moment(bands: [0x3D2A45, 0x5E3548, 0x86444A, 0xAE5646, 0xCE6C48, 0xE28450, 0xEE9C4E, 0xF6B452],
                                 darkness: 0.6, dim: 0xD9C2B8)
    }

    /// When each sky is at its fullest. Between two of them the sky is a blend.
    private static let day: [(hour: Double, moment: Moment)] = [
        (0, .night), (5, .night), (6.5, .dawn), (8.5, .day), (16, .day), (18.25, .dusk), (20.5, .night), (24, .night),
    ]

    /// The two moments around this hour, and how far it is from the first to the second.
    private var blend: (from: Moment, to: Moment, part: Double) {
        for (before, after) in zip(Self.day, Self.day.dropFirst()) where hour <= after.hour {
            let span = after.hour - before.hour
            return (before.moment, after.moment, span > 0 ? (hour - before.hour) / span : 0)
        }
        return (.night, .night, 0)
    }

    // MARK: - The sky

    /// Eight bands of sky, top to bottom.
    var bands: [UInt32] {
        let blend = blend
        return zip(blend.from.bands, blend.to.bands).map { Self.mix($0, $1, blend.part) }
    }

    /// 0 by day, 1 at night.
    var darkness: Double {
        let blend = blend
        return blend.from.darkness + (blend.to.darkness - blend.from.darkness) * blend.part
    }

    /// The colour to multiply the room by, `nil` in full daylight.
    var dim: UInt32? {
        let blend = blend
        let color = Self.mix(blend.from.dim, blend.to.dim, blend.part)
        return color == 0xFFFFFF ? nil : color
    }

    /// Lamps are on, and every screen lights its desk.
    var hasLamps: Bool { hour >= 17.5 || hour < 7 }

    /// How bright the stars are, 0 to 1.
    var starlight: Double { max(0, (darkness - 0.6) / 0.4) }

    /// The share of the city's windows that are lit, 0 to 1: none by day, a few as the sun
    /// goes down, nearly all at nine, fewer and fewer towards midnight, a handful through the
    /// night, some again before sunrise.
    var litShare: Double {
        let points: [(Double, Double)] = [
            (0, 0.2), (2, 0.07), (5, 0.05), (6.5, 0.22), (8, 0.04), (9, 0), (16, 0), (17.5, 0.3), (19, 0.6),
            (21, 0.95), (22.5, 0.6), (24, 0.2),
        ]
        for (before, after) in zip(points, points.dropFirst()) where hour <= after.0 {
            let span = after.0 - before.0
            return before.1 + (after.1 - before.1) * (span > 0 ? (hour - before.0) / span : 0)
        }
        return 0
    }

    /// Where the sun stands, from six to six: `across` runs 0 to 1 over the window, the middle
    /// at noon; `height` is 0 on the horizon and 1 at noon. `nil` once it is down.
    var sun: (across: Double, height: Double)? {
        guard hour >= 6, hour <= 18 else { return nil }
        let across = (hour - 6) / 12
        return (across, sin(.pi * across))
    }

    /// Where the moon stands, from six in the evening to six in the morning, highest at
    /// midnight. `nil` by day.
    var moon: (across: Double, height: Double)? {
        guard hour >= 18 || hour <= 6 else { return nil }
        let across = (hour >= 18 ? hour - 18 : hour + 6) / 12
        return (across, sin(.pi * across))
    }

    /// A colour between two, channel by channel.
    static func mix(_ from: UInt32, _ to: UInt32, _ part: Double) -> UInt32 {
        let part = min(max(part, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((from >> shift) & 0xFF), b = Double((to >> shift) & 0xFF)
            return UInt32((a + (b - a) * part).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

/// The weather in the room's window. Nothing is asked of the network: each day has its own,
/// decided by its date, so it rains some days and, in winter, snows.
enum RoomWeather: String, CaseIterable, Identifiable, Sendable {
    case clear, overcast, rain, snow

    static let storageKey = "roomWeather"
    /// The stored choice that lets each day have its own weather.
    static let asItComes = "auto"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "Clear"
        case .overcast: "Overcast"
        case .rain: "Rain"
        case .snow: "Snow"
        }
    }

    /// Something falls: the window is redrawn often enough to see it fall.
    var isFalling: Bool { self == .rain || self == .snow }

    /// The weather of a day: five days in ten are clear, two overcast, three wet, and what falls
    /// from December to February is snow two times in three.
    static func of(_ date: Date, calendar: Calendar = .current) -> RoomWeather {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let month = parts.month ?? 6
        var seed = UInt32(truncatingIfNeeded: (parts.year ?? 0) &* 372 &+ month &* 31 &+ (parts.day ?? 0))
        seed = (seed ^ (seed >> 15)) &* 2_246_822_519
        seed ^= seed >> 13
        let isWinter = month == 12 || month <= 2
        switch seed % 10 {
        case 0, 1: return isWinter ? .snow : .rain
        case 2: return .rain
        case 3, 4: return .overcast
        default: return .clear
        }
    }

    /// The weather to show for a stored choice: the one chosen, or the day's own.
    static func chosen(_ stored: String, at date: Date, calendar: Calendar = .current) -> RoomWeather {
        RoomWeather(rawValue: stored) ?? of(date, calendar: calendar)
    }
}
