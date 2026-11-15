import SwiftUI

/// The window of the agent room and the city behind it. The hour decides everything in it: the
/// colour of the sky, where the sun or the moon stands, how dark the buildings are, and how many
/// of their windows are lit.
extension RoomPainter {

    private enum Roof {
        case flat, antenna, tank, step, slant
    }

    private struct Building {
        let x: CGFloat
        let width: CGFloat
        let height: CGFloat
        /// Which of the four facades it is built in.
        let tone: Int
        let roof: Roof
    }

    /// The glass, in units.
    private static let glass = CGRect(x: 17, y: 9, width: 140, height: 27)

    private static let near: [Building] = [
        Building(x: 17, width: 13, height: 12, tone: 0, roof: .tank),
        Building(x: 31, width: 10, height: 18, tone: 1, roof: .antenna),
        Building(x: 42, width: 15, height: 9, tone: 2, roof: .flat),
        Building(x: 58, width: 11, height: 22, tone: 3, roof: .step),
        Building(x: 70, width: 14, height: 11, tone: 0, roof: .flat),
        Building(x: 85, width: 9, height: 8, tone: 1, roof: .slant),
        Building(x: 95, width: 16, height: 11, tone: 2, roof: .tank),
        Building(x: 112, width: 12, height: 23, tone: 3, roof: .antenna),
        Building(x: 125, width: 13, height: 15, tone: 0, roof: .step),
        Building(x: 139, width: 18, height: 10, tone: 1, roof: .flat),
    ]
    /// The towers further off, hazier, between the nearer ones. The skyline dips in the middle of
    /// the window: that is where the sun stands at noon and the moon at midnight.
    private static let far: [(x: CGFloat, width: CGFloat, height: CGFloat)] = [
        (22, 12, 17), (48, 9, 21), (73, 10, 13), (103, 8, 17), (121, 9, 26), (133, 10, 21), (150, 7, 18),
    ]
    private static let facades: [UInt32] = [0x8793A0, 0x73818F, 0x9A9186, 0x66747F]
    private static let silhouette: UInt32 = 0x0D1017

    /// A number from 0 to 1 that is always the same for the same three integers: which windows
    /// of the city light up first is decided once and for all.
    private static func chance(_ a: Int, _ b: Int, _ c: Int) -> Double {
        var hash = UInt32(truncatingIfNeeded: (a &* 73_856_093) ^ (b &* 19_349_663) ^ (c &* 83_492_791))
        hash ^= hash >> 13
        hash = hash &* 1_274_126_177
        hash ^= hash >> 16
        return Double(hash & 0xFFFF) / 65_535
    }

    /// The frame of the window in units: all `window` draws stays inside it.
    static let windowFrame = CGRect(x: 12, y: 6, width: 150, height: 35)

    /// What of the window a pass draws. The sky and the city move slowly and cost the most; what
    /// falls is cheap and fast. The room draws them at their own rates, a small room all at once.
    enum WindowPart {
        case all
        /// The frame, the sky and the city.
        case view
        /// The rain or the snow, and what stands in front of the glass.
        case falling
    }

    func window(_ sky: RoomSky, weather: RoomWeather, step: Int, time: TimeInterval, part: WindowPart = .all) {
        let glass = Self.glass
        // Everything behind the glass is cut to it: a cloud or a halo stops at the frame.
        var view = self
        view.context.clip(to: Path(CGRect(x: glass.minX * unit, y: glass.minY * unit,
                                          width: glass.width * unit, height: glass.height * unit)))
        if part != .falling {
            fill(0x4A3C34, 14, 6, 146, 33)
            fill(0x5E4D42, 15, 7, 144, 31)
            fill(0x3A2F29, 16, 8, 142, 29)
            view.heavens(sky, weather: weather, step: step, time: time)
            view.city(sky, weather: weather, step: step, time: time)
        }
        if part != .view { view.falling(weather, time: time) }
        // With rain or snow on its own pass, what stands in front of the glass is drawn there.
        if part == .view, weather.isFalling { return }

        // The glass catches the light: two slanted sheens.
        let sheen = Color.white.opacity(0.1 - 0.06 * sky.darkness)
        shape([CGPoint(x: 38, y: 9), CGPoint(x: 47, y: 9), CGPoint(x: 33, y: 36), CGPoint(x: 24, y: 36)], color: sheen)
        shape([CGPoint(x: 133, y: 9), CGPoint(x: 137, y: 9), CGPoint(x: 123, y: 36), CGPoint(x: 119, y: 36)], color: sheen)
        // A blind rolled most of the way up, and its cord.
        fill(0xEDE3D3, 17, 9, 140, 2.5)
        fill(0xCFC3AE, 17, 11, 140, 0.5)
        fill(0xCFC3AE, 153.5, 11.5, 0.5, 5)
        fill(0xEDE3D3, 153, 16.5, 1.5, 1.5)
        fill(0x5E4D42, 62.5, 8, 2, 29)
        fill(0x5E4D42, 110, 8, 2, 29)
        fill(0x7A6556, 62.5, 8, 0.5, 29)
        fill(0x7A6556, 110, 8, 0.5, 29)
        fill(0x6E5B4E, 12, 38, 150, 2.5)
        fill(0x8A7363, 12, 38, 150, 0.5)
        fill(0x4A3C34, 12, 40, 150, 0.5)
    }

    /// The sky, its stars, its clouds, and the sun or the moon.
    private func heavens(_ sky: RoomSky, weather: RoomWeather, step: Int, time: TimeInterval) {
        let glass = Self.glass
        let bands = sky.bands
        let bandHeight = glass.height / CGFloat(bands.count)
        for (index, band) in bands.enumerated() {
            fill(band, glass.minX, glass.minY + CGFloat(index) * bandHeight, glass.width, bandHeight + 0.5)
        }
        if sky.starlight > 0, weather == .clear {
            for star in 0..<22 {
                let twinkle = (step + star * 5) % 17 > 2 ? 1.0 : 0.35
                let size: CGFloat = star % 5 == 0 ? 1 : 0.5
                let starX: CGFloat = glass.minX + 3 + CGFloat((star * 37) % 134)
                let starY: CGFloat = glass.minY + 3.5 + CGFloat((star * 11) % 13)
                fill(Color(hex: 0xE8ECF8).opacity(sky.starlight * twinkle), starX, starY, size, size)
            }
        }
        if let moon = sky.moon {
            let centre = CGPoint(x: glass.minX + glass.width * moon.across, y: 34 - 19 * moon.height)
            disc(centre, radius: 7, color: Color(hex: 0xC8D4F0).opacity(0.12))
            disc(centre, radius: 3.25, color: Color(hex: 0xE8ECF8))
            disc(CGPoint(x: centre.x + 1.5, y: centre.y - 0.75), radius: 2.75, color: Color(hex: bands[2]))
        }
        if let sun = sky.sun {
            let centre = CGPoint(x: glass.minX + glass.width * sun.across, y: 34 - 19 * sun.height)
            let color = Color(hex: RoomSky.mix(0xFF9A4A, 0xFFF4C8, sun.height))
            let middle = CGPoint(x: centre.x * unit, y: centre.y * unit)
            let halo = CGRect(x: middle.x - 14 * unit, y: middle.y - 14 * unit, width: 28 * unit, height: 28 * unit)
            context.fill(Path(ellipseIn: halo), with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                                                                    center: middle, startRadius: 0, endRadius: 14 * unit))
            disc(centre, radius: 3.5, color: color)
            disc(centre, radius: 2.5, color: Color.white.opacity(0.35))
        }
        // Under a covered sky a grey veil takes the colour out, and the sun is a pale patch in it.
        if weather != .clear {
            fill(RoomSky.mix(0x9AA3AE, 0x1E232D, sky.darkness), glass.minX, glass.minY, glass.width, glass.height, opacity: 0.66)
        }
        let cloudiness = max(0, 1 - sky.darkness * 1.4)
        guard cloudiness > 0 else { return }
        let white = weather == .clear ? Color.white.opacity(0.9 * cloudiness)
            : Color(hex: RoomSky.mix(0xD3D9E0, 0x596270, sky.darkness)).opacity(0.75 * cloudiness)
        var clouds: [(Double, CGFloat, CGFloat, Double)] = [(10, 15, 1, 0.5), (70, 19.5, 0.75, 0.3), (118, 13.5, 0.6, 0.4)]
        if weather != .clear { clouds += [(40, 13, 1.2, 0.35), (100, 17, 1.1, 0.45), (150, 14.5, 0.9, 0.25)] }
        for (start, y, scale, speed) in clouds {
            let drift = (start + time * speed).truncatingRemainder(dividingBy: 170) - 15
            let x = glass.minX + CGFloat(drift)
            fill(white, x, y + 1.5 * scale, 16 * scale, 2 * scale)
            fill(white, x + 3 * scale, y, 9 * scale, 2 * scale)
            fill(white, x + 6 * scale, y - 1 * scale, 4 * scale, 1.5 * scale)
        }
    }

    /// Two rows of buildings: hazy towers behind, and in front the ones whose windows light up.
    /// How lit a window of the city is, 0 to 1. Each has its own moment to come on, set by
    /// `luck`; around that moment it wavers, on and off over a minute or so, and it fades rather
    /// than switches.
    private static func glow(luck: Double, share: Double, time: TimeInterval) -> Double {
        let waver = 0.035 * sin(time * (0.08 + luck * 0.12) + luck * 40)
        let lead = (share - luck + waver) / 0.05
        guard lead > 0 else { return 0 }
        let part = min(lead, 1)
        return part * part * (3 - 2 * part)
    }

    private func city(_ sky: RoomSky, weather: RoomWeather, step: Int, time: TimeInterval) {
        let ground = Self.glass.maxY
        let bands = sky.bands
        let litShare = sky.litShare
        let shade = pow(sky.darkness, 0.8)
        let haze = RoomSky.mix(RoomSky.mix(0x9AA6B2, Self.silhouette, shade), bands[5], 0.5)
        for (index, tower) in Self.far.enumerated() {
            fill(haze, tower.x, ground - tower.height, tower.width, tower.height)
            fill(Color.white.opacity(0.06), tower.x, ground - tower.height, tower.width, 0.5)
            var y = ground - tower.height + 2
            while y < ground - 1 {
                var x = tower.x + 1.5
                var column = 0
                while x < tower.x + tower.width - 1 {
                    let glow = Self.glow(luck: Self.chance(index + 40, Int(y * 2), column), share: litShare * 0.7, time: time)
                    if glow > 0 { fill(Color(hex: 0xFFD98A).opacity(0.7 * glow), x, y, 0.75, 0.75) }
                    x += 2.5
                    column += 1
                }
                y += 3
            }
        }
        let pane = RoomSky.mix(bands[3], 0x1B2230, sky.darkness)
        for (index, building) in Self.near.enumerated() {
            let facade = RoomSky.mix(Self.facades[building.tone], Self.silhouette, shade)
            let top = ground - building.height
            roof(building, top: top, facade: facade, sky: sky, step: step, seed: index)
            fill(facade, building.x, top, building.width, building.height)
            shadow(building.x + building.width - 1.5, top, 1.5, building.height, opacity: 0.2)
            fill(Color.white.opacity(0.12 - 0.08 * sky.darkness), building.x, top, building.width, 0.5)
            if weather == .snow { fill(Color.white.opacity(0.8 - 0.45 * sky.darkness), building.x, top - 0.5, building.width, 1) }
            let dark = RoomSky.mix(facade, pane, 0.45)
            var row = 0
            var y = top + 2
            while y < ground - 1.5 {
                var column = 0
                var x = building.x + 1.5
                while x < building.x + building.width - 3 {
                    let luck = Self.chance(index, row, column)
                    fill(dark, x, y, 1.25, 1.5)
                    let glow = Self.glow(luck: luck, share: litShare, time: time)
                    if glow > 0 {
                        // One window in nine has a screen on: a cooler light.
                        let light: UInt32 = Int(luck * 9_000) % 9 == 0 ? 0xCFE4FF : 0xFFD98A
                        fill(light, x, y, 1.25, 1.5, opacity: glow)
                    }
                    x += 2.5
                    column += 1
                }
                y += 2.75
                row += 1
            }
        }
    }

    /// Rain in slanted streaks, or snow in slow flakes, in front of the city.
    private func falling(_ weather: RoomWeather, time: TimeInterval) {
        let glass = Self.glass
        switch weather {
        case .rain:
            var streaks = Path()
            for drop in 0..<46 {
                let across = (Double(drop) * 29 + time * 30).truncatingRemainder(dividingBy: Double(glass.width) + 8)
                let down = (Double(drop * drop % 97) * 3 + time * 70).truncatingRemainder(dividingBy: Double(glass.height))
                let x = glass.maxX + 4 - CGFloat(across), y = glass.minY + CGFloat(down)
                streaks.move(to: CGPoint(x: x * unit, y: y * unit))
                streaks.addLine(to: CGPoint(x: (x - 1.1) * unit, y: (y + 3.2) * unit))
            }
            context.stroke(streaks, with: .color(Color.white.opacity(0.32)), lineWidth: 0.35 * unit)
        case .snow:
            for flake in 0..<42 {
                let sway = sin(time * 0.8 + Double(flake)) * 2
                let down = (Double(flake) * 13 + time * Double(4 + flake % 4)).truncatingRemainder(dividingBy: Double(glass.height))
                let size: CGFloat = flake % 3 == 0 ? 0.75 : 0.5
                fill(Color.white.opacity(0.9), glass.minX + CGFloat((flake * 23) % Int(glass.width)) + CGFloat(sway),
                     glass.minY + CGFloat(down), size, size)
            }
        case .clear, .overcast:
            break
        }
    }

    private func roof(_ building: Building, top: CGFloat, facade: UInt32, sky: RoomSky, step: Int, seed: Int) {
        let middle = building.x + building.width / 2
        switch building.roof {
        case .flat:
            fill(facade, building.x + 2, top - 1, 3, 1)
        case .antenna:
            fill(facade, middle - 0.25, top - 5, 0.5, 5)
            fill(facade, middle - 1.25, top - 2, 2.5, 0.5)
            let isOn = sky.darkness > 0.4 && (step + seed) % 8 < 4
            fill(isOn ? 0xF0604D : facade, middle - 0.5, top - 5.5, 1, 1)
        case .tank:
            fill(facade, building.x + 2.5, top - 3, 4.5, 2.5)
            fill(facade, building.x + 3, top - 0.5, 0.5, 0.5)
            fill(facade, building.x + 6, top - 0.5, 0.5, 0.5)
        case .step:
            fill(facade, building.x + 2, top - 3, building.width - 5, 3)
            shadow(building.x + building.width - 4.5, top - 3, 1.5, 3, opacity: 0.2)
        case .slant:
            shape([CGPoint(x: building.x, y: top), CGPoint(x: building.x + building.width, y: top),
                   CGPoint(x: building.x + building.width, y: top - 4)], color: Color(hex: facade))
        }
    }
}
