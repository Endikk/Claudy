import SwiftUI

/// What a click on a desk opens: the agent that sits there. What it was asked, what it does now,
/// its last calls and the files it wrote.
struct RoomAgentCard: View {
    let agent: RunningAgent
    let close: () -> Void
    @EnvironmentObject private var agents: AgentsViewModel

    static let width: CGFloat = 236
    /// Room kept for it when it is placed: it is never taller.
    static let height: CGFloat = 200

    /// The room is dark at any hour, so what lies on it is lettered in fixed light inks.
    private static let ink = Color(hex: 0xF4EDE4)
    private static let quiet = Color(hex: 0xB9AEA3)
    private static let callCount = 4
    private static let fileCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(agents.tint(of: agent))
                    .frame(width: 9, height: 9)
                    .padding(.top, 3)
                Text(agent.title)
                    .font(Theme.Font.label(13, .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Self.quiet)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text("\(status) · \(agents.elapsed(agent)) · \(agent.sessionName)")
                .font(Theme.Font.value(11, .regular))
                .foregroundStyle(Self.quiet)
                .lineLimit(1)
            section("Now") {
                Text(agent.workLabel)
                    .font(Theme.Font.mono(11, .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !calls.isEmpty {
                section("Before that") {
                    ForEach(Array(calls.enumerated()), id: \.offset) { _, call in
                        Text(call)
                            .font(Theme.Font.mono(11, .regular))
                            .foregroundStyle(Self.quiet)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            if !agent.editedFiles.isEmpty {
                section(agent.editedFiles.count == 1 ? "Wrote 1 file" : "Wrote \(agent.editedFiles.count) files") {
                    Text(files)
                        .font(Theme.Font.mono(11, .regular))
                        .foregroundStyle(Self.quiet)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
        .foregroundStyle(Self.ink)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.tileCorner, style: .continuous)
                .fill(Color(hex: 0x1C1714).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.tileCorner, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .environment(\.colorScheme, .dark)
    }

    /// Where it stands, in a word or two. While it works, what it works on is said under "Now".
    private var status: String {
        switch agent.status(at: agents.now) {
        case .working: return "Working"
        case .idle: return "Waiting"
        case .stalled, .done:
            let state = agents.state(agent)
            return state.prefix(1).uppercased() + state.dropFirst()
        }
    }

    /// The calls before the last one, newest first: "tests · swift test".
    private var calls: [String] {
        agent.recent.dropLast().suffix(Self.callCount).reversed().map { action in
            [action.work.label, action.detail ?? action.file].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var files: String {
        let shown = agent.editedFiles.suffix(Self.fileCount).joined(separator: ", ")
        let hidden = agent.editedFiles.count - Self.fileCount
        return hidden > 0 ? "\(shown) and \(hidden) more" : shown
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Font.label(11, .medium))
                .foregroundStyle(Self.quiet)
            content()
        }
    }

    /// Where the card goes for an agent at `place` (the top left of its desk, in points): beside
    /// the desk, on the side of the room's middle, and never past the room's edges.
    static func origin(beside place: CGPoint, in room: CGSize) -> CGPoint {
        let desk = CGSize(width: RoomGeometry.deskSize.width * RoomCanvas.unit, height: RoomGeometry.deskSize.height * RoomCanvas.unit)
        let x = place.x < room.width / 2 ? place.x + desk.width + 8 : place.x - width - 8
        let y = min(max(8, place.y - 12), room.height - height - 8)
        return CGPoint(x: min(max(8, x), room.width - width - 8), y: y)
    }
}
