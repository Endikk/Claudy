import SwiftUI

/// The agent room, drawn: the open space of one project, redrawn a few times a second while its
/// window is open. Over the drawing lie the places a pointer can rest or click: each occupied
/// desk says who sits there, and Claudy's second screen opens the summary.
struct RoomCanvas: View {
    @ObservedObject var room: RoomViewModel
    /// The hour to light the room for: the Mac's clock, or one held still.
    var light: RoomLight = .clock
    /// The stored choice of weather: one of `RoomWeather`, or each day's own.
    var weatherChoice = RoomWeather.asItComes
    @EnvironmentObject private var usage: UsageViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points per unit of the scene: a half unit is then one point, two pixels on a Retina screen.
    static let unit: CGFloat = 2
    static let size = CGSize(width: RoomGeometry.size.width * unit, height: RoomGeometry.size.height * unit)
    /// Frames a second: as many as what the room shows asks for, and the most while the hour is
    /// swept through.
    private var frameRate: Double {
        if sweep.from != nil { return RoomScene.Pace.walking.framesPerSecond }
        return room.scene(for: room.selected, at: Date(), quota: nil, withHelp: false).pace.framesPerSecond
    }
    private static let stepDuration: TimeInterval = 0.18
    private static let strideDuration: TimeInterval = 0.12

    /// What never changes from one frame to the next, kept as images: the still part of the
    /// room, drawn again only when what it shows changes (the project's name, the week on the
    /// board, the lamps), and a desk's furniture, drawn once.
    @MainActor
    private final class Backdrop {
        private var key: String?
        private var still: Image?
        private var desk: RoomPainter.DeskArt?
        private var hasTriedDesk = false

        func image(title: String, week: [Double], isLit: Bool) -> Image? {
            let wanted = "\(title)|\(week)|\(isLit)"
            if wanted == key { return still }
            key = wanted
            still = Self.render(RoomGeometry.size) { $0.stillBackdrop(title: title, week: week, isLit: isLit) }
            return still
        }

        func deskArt() -> RoomPainter.DeskArt? {
            if hasTriedDesk { return desk }
            hasTriedDesk = true
            let origin = CGPoint(x: RoomPainter.DeskArt.margin, y: RoomPainter.DeskArt.margin)
            guard let chair = Self.render(RoomPainter.DeskArt.size, draw: { $0.deskChair(at: origin) }),
                  let body = Self.render(RoomPainter.DeskArt.size, draw: { $0.deskBody(at: origin) }) else { return nil }
            desk = RoomPainter.DeskArt(chair: chair, desk: body)
            return desk
        }

        private var symbols: [String: Image]?

        /// Every symbol a screen can show, in each colour it is shown in, as small images: a
        /// symbol resolved on every frame costs far more than an image stamped.
        func stamps() -> [String: Image] {
            if let symbols { return symbols }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            var made: [String: Image] = [:]
            for name in RoomGlyph.names {
                for ink in RoomGlyph.inks {
                    let symbol = Image(systemName: name)
                        .font(.system(size: ink.points * RoomCanvas.unit / 2, weight: .semibold))
                        .foregroundColor(Color(hex: ink.color))
                    let renderer = ImageRenderer(content: symbol)
                    renderer.scale = scale
                    if let image = renderer.cgImage {
                        made[RoomGlyph.tag(name, color: ink.color, points: ink.points)] = Image(decorative: image, scale: scale)
                    }
                }
            }
            symbols = made
            return made
        }

        /// A drawing of `size` units as an image. Where SwiftUI cannot render off screen there
        /// is none, and the room draws that part itself on every frame.
        private static func render(_ size: CGSize, draw: @escaping (RoomPainter) -> Void) -> Image? {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let drawing = Canvas { context, _ in
                draw(RoomPainter(context: context, unit: RoomCanvas.unit))
            }
            .frame(width: size.width * RoomCanvas.unit, height: size.height * RoomCanvas.unit)
            let renderer = ImageRenderer(content: drawing)
            renderer.scale = scale
            return renderer.cgImage.map { Image(decorative: $0, scale: scale) }
        }
    }

    @State private var backdrop = Backdrop()

    /// What the last frame showed, so that a change of light is swept through hour by hour
    /// instead of jumped to.
    private final class Sweep {
        var light: RoomLight?
        var shown: Double?
        var from: Double?
        var startedAt: Date?
    }

    @State private var sweep = Sweep()

    /// Seconds a sweep takes for each hour it crosses, and its bounds.
    private static let sweepPerHour: TimeInterval = 0.4
    private static let sweepBounds: ClosedRange<TimeInterval> = 1.2...5

    /// The hour to draw: the light's own, or on the way to it just after the light changed. The
    /// sweep takes the short way round the clock.
    private func hour(at date: Date) -> Double {
        let target = light.hour(at: date)
        if sweep.light != light {
            sweep.from = sweep.light == nil || reduceMotion ? nil : sweep.shown
            sweep.startedAt = date
            sweep.light = light
        }
        var shown = target
        if let from = sweep.from, let startedAt = sweep.startedAt {
            var span = (target - from).truncatingRemainder(dividingBy: 24)
            if span > 12 { span -= 24 }
            if span < -12 { span += 24 }
            let duration = min(max(abs(span) * Self.sweepPerHour, Self.sweepBounds.lowerBound), Self.sweepBounds.upperBound)
            let part = date.timeIntervalSince(startedAt) / duration
            if part < 1 {
                let eased = part * part * (3 - 2 * part)
                shown = from + span * max(0, eased)
            } else {
                sweep.from = nil
            }
        }
        sweep.shown = shown
        return shown
    }

    /// The tokens of the last seven days, each as a share of the busiest: the board's bars.
    private var week: [Double] {
        let days = usage.snapshot.history.suffix(7)
        guard let most = days.map(\.tokens).max(), most > 0 else { return [] }
        return days.map { Double($0.tokens) / Double(most) }
    }

    private var quota: Double? {
        let session = usage.snapshot.session
        return session.isMeasured ? session.percent : nil
    }

    var body: some View {
        // Told before the timelines are set up, so that a change of light starts at the fast rate.
        let _ = hour(at: Date())
        // Under Reduce Motion the room still tells the time: one frame a second, nobody walking.
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / frameRate)) { timeline in
            let scene = room.scene(for: room.selected, at: timeline.date, quota: quota, withHelp: false)
            let title = room.selected?.id ?? "Claudy"
            let isSummaryOpen = room.isSummaryOpen
            let week = week
            let sky = RoomSky(hour: hour(at: timeline.date))
            let still = backdrop.image(title: title, week: week, isLit: sky.hasLamps)
            let art = backdrop.deskArt()
            let stamps = backdrop.stamps()
            Canvas { context, _ in
                Self.draw(scene, in: context, at: timeline.date, sky: sky,
                          weather: RoomWeather.chosen(weatherChoice, at: timeline.date), week: week, still: still, art: art,
                          stamps: stamps, title: title, isSummaryOpen: isSummaryOpen)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay(alignment: .topLeading) {
            // The window, over the room, in a drawing no larger than itself: twice a second is
            // enough for clouds and for a city lighting up, more when something falls, and every
            // frame while the hour is swept through.
            let frame = RoomPainter.windowFrame
            let falls = RoomWeather.chosen(weatherChoice, at: Date()).isFalling
            let pause = sweep.from != nil ? 1 / RoomScene.Pace.walking.framesPerSecond
                : (falls ? 1 / RoomScene.Pace.typing.framesPerSecond : 0.5)
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : pause)) { timeline in
                let sky = RoomSky(hour: hour(at: timeline.date))
                let weather = RoomWeather.chosen(weatherChoice, at: timeline.date)
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, _ in
                    var painter = RoomPainter(context: context, unit: Self.unit)
                    painter.context.translateBy(x: -frame.minX * Self.unit, y: -frame.minY * Self.unit)
                    painter.window(sky, weather: weather, step: Int(time / Self.stepDuration), time: time)
                }
            }
            .frame(width: frame.width * Self.unit, height: frame.height * Self.unit)
            .offset(x: frame.minX * Self.unit, y: frame.minY * Self.unit)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            // Once a second: a Claudy that just sat down gets its desk's words without waiting
            // for the next pass.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                hotspots(at: timeline.date)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent room of \(room.selected?.id ?? "no project")")
    }

    /// What a pointer can rest on or click.
    private func hotspots(at date: Date) -> some View {
        let scene = room.scene(for: room.selected, at: date, quota: quota)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(scene.desks.enumerated()), id: \.offset) { index, occupant in
                if let occupant {
                    let seat = RoomSeat(zone: index / RoomPlan.seatsPerZone, index: index % RoomPlan.seatsPerZone)
                    let origin = RoomGeometry.desk(seat)
                    spot(x: origin.x, y: origin.y, width: RoomGeometry.deskSize.width, height: RoomGeometry.deskSize.height,
                         help: occupant.help) { room.toggleAgent(occupant.id) }
                }
            }
            ForEach(scene.loungers) { lounger in
                let seat = RoomGeometry.sofa(lounger.slot)
                spot(x: seat.x - 8, y: seat.y - CGFloat(RoomSprite.rows), width: 16, height: CGFloat(RoomSprite.rows),
                     help: lounger.help) { room.toggleAgent(lounger.id) }
            }
            if !scene.chief.help.isEmpty {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 56 * Self.unit, height: 30 * Self.unit)
                    .offset(x: 200 * Self.unit, y: (100 + RoomGeometry.centreDrop) * Self.unit)
                    .help(scene.chief.help)
                    .accessibilityLabel(scene.chief.help)
            }
            Button {
                withAnimation(Theme.Motion.popup) {
                    room.isSummaryOpen.toggle()
                    if room.isSummaryOpen { room.selectedAgentID = nil }
                }
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .offset(x: RoomPainter.quotaCentre.x * Self.unit - 22, y: (RoomPainter.quotaCentre.y + RoomGeometry.centreDrop) * Self.unit - 22)
            .help(room.isSummaryOpen ? "Hide the session summary" : "Show the session summary")
            .accessibilityLabel("Session summary")
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    /// A place of the room that says something under the pointer and does something on a click.
    private func spot(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, help: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: width * Self.unit, height: height * Self.unit)
        .offset(x: x * Self.unit, y: y * Self.unit)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Drawing

    /// Draws a room. `unit` is its scale; a small room, in the overview, has no image kept for
    /// it and draws its own window (`drawsWindow`), where the full one leaves it to its layer.
    static func draw(_ scene: RoomScene, in context: GraphicsContext, at date: Date, sky: RoomSky, weather: RoomWeather,
                     week: [Double], still: Image?, art: RoomPainter.DeskArt?, stamps: [String: Image], title: String,
                     isSummaryOpen: Bool, unit: CGFloat = RoomCanvas.unit, drawsWindow: Bool = false) {
        var painter = RoomPainter(context: context, unit: unit, stamps: stamps)
        let time = date.timeIntervalSinceReferenceDate
        let step = Int(time / stepDuration)

        let centre = painter.lowered(by: RoomGeometry.centreDrop)
        if let still {
            context.draw(still, in: CGRect(x: 0, y: 0, width: RoomGeometry.size.width * unit, height: RoomGeometry.size.height * unit))
        } else {
            painter.stillBackdrop(title: title, week: week, isLit: sky.hasLamps)
        }
        let quota = scene.chief.quota ?? 0
        painter.liveBackdrop(sky: sky, weather: weather, step: step, time: time, date: date, quota: quota)
        if drawsWindow { painter.window(sky, weather: weather, step: step, time: time) }
        for (index, zone) in scene.zones.enumerated() {
            painter.zone(zone, at: RoomGeometry.zoneOrigins[index])
        }

        // Back to front: whoever stands lower on the floor is drawn over what is behind.
        let desks = scene.desks.enumerated().map { index, occupant in
            (origin: RoomGeometry.desk(seat(at: index)), occupant: occupant)
        }
        let chosen = scene.selectedDesk.map { desks[$0].origin }
        var layers: [(depth: CGFloat, draw: (RoomPainter) -> Void)] = desks.map { desk in
            (desk.origin.y + RoomGeometry.deskSize.height, { painter in
                painter.desk(at: desk.origin, occupant: desk.occupant, step: step, art: art)
                if desk.origin == chosen { painter.selection(at: desk.origin) }
            })
        }
        for lounger in scene.loungers {
            layers.append((RoomGeometry.sofa(lounger.slot).y, { $0.lounger(lounger, step: step) }))
        }
        layers.append((138 + RoomGeometry.centreDrop, { _ in
            centre.chief(scene.chief, step: step, isLit: sky.hasLamps, isSummaryOpen: isSummaryOpen)
        }))
        let vacuum = RoomVacuum.state(at: time)
        painter.vacuumTrail(RoomVacuum.trail(at: time))
        layers.append((vacuum.position.y + 3, { $0.vacuum(vacuum, time: time) }))
        let stride: [RoomSprite.Pose] = [.rest, .stepA, .rest, .stepB]
        let pose = stride[Int(time / strideDuration) % stride.count]
        for walker in scene.walkers {
            layers.append((walker.position.y, { painter in
                painter.shadow(walker.position.x - 6, walker.position.y - 1, 12, 2, opacity: 0.25)
                painter.claudy(pose, feet: walker.position, tint: walker.tint)
                if let glyph = walker.glyph {
                    painter.bubble(glyph, x: walker.position.x - 5.5, y: walker.position.y - 28)
                }
            }))
        }
        for layer in layers.sorted(by: { $0.depth < $1.depth }) {
            layer.draw(painter)
        }

        let lit = desks.filter { $0.occupant != nil && $0.occupant?.state != .stalled }
            .map { CGPoint(x: $0.origin.x + 8.5, y: $0.origin.y + 8) }
        painter.vignette()
        painter.strain(quota, time: time)
        painter.light(sky, screens: lit)
        if drawsWindow, sky.dim != nil { painter.window(sky, weather: weather, step: step, time: time) }
        guard sky.dim != nil, sky.hasLamps else { return }
        // The night dims the screens with the rest: they are lit again on top of it.
        for desk in desks where desk.occupant != nil {
            painter.screenFace(at: desk.origin, of: desk.occupant, step: step)
        }
        centre.chiefScreens(scene.chief, step: step, isSummaryOpen: isSummaryOpen)
    }

    private static func seat(at index: Int) -> RoomSeat {
        RoomSeat(zone: index / RoomPlan.seatsPerZone, index: index % RoomPlan.seatsPerZone)
    }
}
