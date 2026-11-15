import SwiftUI

/// Every project with a session open, each as a small room, side by side: who works where, at a
/// glance. A click on a room enters it. The small rooms are drawn once a second: nobody is seen
/// walking here, only where everyone sits.
struct RoomOverview: View {
    @ObservedObject var room: RoomViewModel
    let weatherChoice: String
    @EnvironmentObject private var usage: UsageViewModel
    @EnvironmentObject private var agents: AgentsViewModel

    /// The room is dark at any hour, so what lies on it is lettered in a fixed light ink.
    private static let ink = Color(hex: 0xF4EDE4)
    private static let wideLimit = 4
    private static let labelHeight: CGFloat = 30

    private var quota: Double? {
        let session = usage.snapshot.session
        return session.isMeasured ? session.percent : nil
    }

    var body: some View {
        let count = room.projects.count <= Self.wideLimit ? 2 : 3
        let gap = Theme.Metric.gap
        let width = ((RoomCanvas.size.width - gap * CGFloat(count + 1)) / CGFloat(count)).rounded(.down)
        let unit = width / RoomGeometry.size.width
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: gap), count: count), spacing: gap) {
                ForEach(room.projects) { project in
                    Button {
                        withAnimation(Theme.Motion.mode) { room.enter(project.id) }
                    } label: {
                        tile(project, width: width, unit: unit)
                    }
                    .buttonStyle(.plain)
                    .help("Enter the room of \(project.id)")
                }
            }
            .padding(gap)
        }
        .frame(width: RoomCanvas.size.width, height: RoomCanvas.size.height)
        .background(Color(hex: 0x1F1815))
    }

    private func tile(_ project: RoomViewModel.Project, width: CGFloat, unit: CGFloat) -> some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let date = timeline.date
                let scene = room.scene(for: project, at: date, quota: quota, withHelp: false)
                let sky = RoomSky(hour: RoomSky.hour(at: date))
                let weather = RoomWeather.chosen(weatherChoice, at: date)
                Canvas { context, _ in
                    RoomCanvas.draw(scene, in: context, at: date, sky: sky, weather: weather, week: [], still: nil, art: nil,
                                    stamps: [:], title: project.id, isSummaryOpen: true, unit: unit, drawsWindow: true)
                }
            }
            .frame(width: width, height: RoomGeometry.size.height * unit)
            HStack(spacing: 6) {
                Text(project.id)
                    .font(Theme.Font.label(12, .semibold))
                    .foregroundStyle(Self.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                let tally = RoomTally(project, at: agents.now)
                if tally.waiting > 0 { RoomBadge(text: "\(tally.waiting) waiting", ink: .amber) }
                if tally.working > 0 { RoomBadge(text: "\(tally.working) working", ink: .coral) }
                if tally.stuck > 0 { RoomBadge(text: "\(tally.stuck) stuck", ink: .danger) }
            }
            .padding(.horizontal, 10)
            .frame(height: Self.labelHeight)
            .environment(\.colorScheme, .dark)
        }
        .background(Color(hex: 0x2A211D))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.id), \(project.runningCount) agents")
    }
}
