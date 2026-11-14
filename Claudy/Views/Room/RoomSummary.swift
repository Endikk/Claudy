import SwiftUI

/// What Claudy's second screen opens: the session in plain sentences. What was asked, what
/// happens now, how much of the limit is used, and the two things to do about it, as the
/// Sessions tab offers them.
struct RoomSummary: View {
    let project: RoomViewModel.Project
    @EnvironmentObject private var agents: AgentsViewModel
    @EnvironmentObject private var usage: UsageViewModel

    /// The room is dark at any hour, so what lies on it is lettered in fixed light inks: the
    /// system's own would turn dark with a light appearance.
    private static let ink = Color(hex: 0xF4EDE4)
    private static let quiet = Color(hex: 0xB9AEA3)

    private var lead: ClaudeSession? { project.lead }
    private var isConfirming: Bool { lead.map { agents.interruptPending == $0.id } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    asked
                    rightNow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                limit
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let lead {
                if isConfirming {
                    confirmation(lead)
                } else if lead.host != nil || lead.canBeInterrupted {
                    actions(lead)
                }
            }
        }
        .padding(Theme.Metric.tilePadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.tileCorner, style: .continuous)
                .fill(Color(hex: 0x1C1714).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.tileCorner, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .foregroundStyle(Self.ink)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - What was asked

    @ViewBuilder
    private var asked: some View {
        if let prompt = lead?.lastPrompt {
            VStack(alignment: .leading, spacing: 3) {
                label("You asked")
                Text(prompt)
                    .font(Theme.Font.label(13, .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(prompt)
            }
        }
    }

    // MARK: - What happens now

    private var rightNow: some View {
        let tally = RoomTally(project, at: agents.now)
        return VStack(alignment: .leading, spacing: 6) {
            label("Right now")
            ForEach(Self.sentences(tally, lead: lead), id: \.text) { line in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(line.ink.map { $0.color(.dark) } ?? Theme.idle)
                        .frame(width: 7, height: 7)
                    Text(line.text)
                        .font(Theme.Font.label(12, .medium))
                        .foregroundStyle(line.ink.map { $0.color(.dark) } ?? Self.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The state of a project in sentences, the one that needs the user first.
    static func sentences(_ tally: RoomTally, lead: ClaudeSession?) -> [(text: String, ink: Theme.Ink?)] {
        var lines: [(String, Theme.Ink?)] = []
        if let lead, lead.isWaiting {
            lines.append(("Waiting for your answer" + (lead.waitingReason.map { ": \($0.lowercased())" } ?? ""), .amber))
        }
        if tally.stuck > 0 {
            let silence = AgentsViewModel.duration(tally.longestSilence)
            lines.append((tally.stuck == 1 ? "1 agent has been silent for \(silence)"
                                           : "\(tally.stuck) agents are silent, one for \(silence)", .danger))
        }
        if tally.working > 0 {
            lines.append((tally.working == 1 ? "1 agent is working" : "\(tally.working) agents are working", .coral))
        }
        if tally.done > 0 {
            lines.append((tally.done == 1 ? "1 agent is done" : "\(tally.done) agents are done", .positive))
        }
        if lines.isEmpty {
            switch lead?.status {
            case .busy: lines.append(("Claude is working on its own", .coral))
            case .idle: lines.append(("Nothing is running", nil))
            default: lines.append(("No agent is running", nil))
            }
        }
        return lines
    }

    // MARK: - The limit

    private var limit: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Your limit")
            gauge("This session", usage.snapshot.session)
            if usage.snapshot.session.isActive {
                Text("Starts again at \(UsageViewModel.resetTime(usage.snapshot.session.resetDate))")
                    .font(Theme.Font.value(11, .regular))
                    .foregroundStyle(Self.quiet)
            }
            gauge("This week", usage.snapshot.weekly)
        }
    }

    private func gauge(_ title: String, _ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 4)
                Text(window.isMeasured ? "\(Int((window.percent * 100).rounded())) % used" : "not measured")
                    .monospacedDigit()
            }
            .font(Theme.Font.label(12, .medium))
            UsageBar(percent: window.isMeasured ? window.percent : 0,
                     tint: Theme.tint(window.accent, at: window.percent), height: 5)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.label(11, .medium))
            .foregroundStyle(Self.quiet)
    }

    // MARK: - Actions

    private func actions(_ session: ClaudeSession) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let host = session.host {
                Button("Open \(host.shortName)") { agents.focus(session) }
                    .buttonStyle(QuietButtonStyle(tint: Self.ink))
                    .help("Brings \(host.name) forward")
            }
            if session.canBeInterrupted {
                Button {
                    agents.askToInterrupt(session)
                } label: {
                    Label("Interrupt", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(QuietButtonStyle(tint: Theme.danger))
                .help("Sends Ctrl+C to this Claude Code session")
            }
        }
        .font(Theme.Font.label(11, .medium))
    }

    private func confirmation(_ session: ClaudeSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sends Ctrl+C to \(session.name): its turn and every agent of it stop. The session stays open.")
                .foregroundStyle(Self.quiet)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: agents.cancelInterrupt)
                    .buttonStyle(QuietButtonStyle(tint: Self.ink))
                // No Return shortcut: the destructive choice takes a click.
                Button("Interrupt \(session.name)") { agents.interrupt(session) }
                    .buttonStyle(QuietButtonStyle(tint: Theme.danger))
            }
        }
        .font(Theme.Font.label(11, .medium))
    }
}
