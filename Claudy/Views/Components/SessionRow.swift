import SwiftUI

/// One Claude Code session in the card's Sessions tab: its line, its details once unfolded, and
/// the agents it runs underneath. A session that waits for the user takes the amber waiting row
/// as its line, with the way to its window in reach.
struct SessionRow: View {
    let group: SessionGroup
    @EnvironmentObject private var viewModel: AgentsViewModel

    private var session: ClaudeSession { group.session }
    private var isExpanded: Bool { viewModel.expandedSessionID == session.id }

    /// The agents' rule sits under the session's dot, and their rows just right of it.
    static let agentIndent: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.isWaiting {
                WaitingRow(session: session, compact: true)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.toggleExpanded(session) }
            } else {
                SessionHeader(session: session, isExpanded: isExpanded)
            }
            if isExpanded {
                SessionDetails(session: session, agentCount: group.agents.count)
                    .padding(.leading, Self.agentIndent + 4)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !group.agents.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.agents) { agent in
                        AgentRow(agent: agent, isExpanded: viewModel.expandedID == agent.id)
                    }
                }
                .padding(.leading, Self.agentIndent)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.primary.opacity(0.1))
                        .frame(width: 1)
                        .padding(.leading, 4)
                }
            }
        }
    }
}

/// A session's line: its state as a dot, its name and project, then what it does and how long it
/// has been open. A click unfolds it.
struct SessionHeader: View {
    let session: ClaudeSession
    let isExpanded: Bool
    @EnvironmentObject private var viewModel: AgentsViewModel
    @State private var isHovered = false

    private var tint: Color {
        switch session.status {
        case .busy: Theme.Accent.coral.color
        case .waiting: Theme.Accent.amber.color
        case .idle, .unknown: Theme.idle
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .frame(width: 9)
            Text(session.name)
                .font(Theme.Font.label(13, .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
            if let folder = session.folderName, folder != session.name {
                Text(folder)
                    .font(Theme.Font.label(11, .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Group {
                if session.status == .busy {
                    Text(viewModel.state(session).sentenceCased).ink(.coral)
                } else {
                    Text(viewModel.state(session).sentenceCased).foregroundStyle(.secondary)
                }
            }
            .font(Theme.Font.label(11, .semibold))
            .fixedSize()
            if let age = viewModel.age(session) {
                Text(age)
                    .font(Theme.Font.value(11, .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
        }
        .frame(minHeight: 22)
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(isExpanded ? 0.06 : isHovered ? 0.035 : 0))
        )
        .padding(.horizontal, -6)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onTapGesture { viewModel.toggleExpanded(session) }
        .help(session.lastPrompt.map { "Last: \($0)" } ?? (isExpanded ? "Click to fold" : "Click to unfold"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.name), \(session.folderName ?? ""), \(viewModel.state(session))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { viewModel.toggleExpanded(session) }
        .accessibilityHint(isExpanded ? "Folds the session" : "Unfolds the session: its app, its last prompt, interrupt")
    }
}

/// What a session unfolds to: where it runs, the last thing asked of it, the way to its window,
/// and the interrupt. The interrupt is two clicks: the first one asks, naming the session and
/// saying what the signal does, since it reaches every agent of that session.
struct SessionDetails: View {
    let session: ClaudeSession
    let agentCount: Int
    @EnvironmentObject private var viewModel: AgentsViewModel

    private var isConfirming: Bool { viewModel.interruptPending == session.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(viewModel.details(session, agents: agentCount))
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
            if let prompt = session.lastPrompt {
                Text("Last: \u{201C}\(prompt)\u{201D}")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(prompt)
            }
            if isConfirming {
                confirmation
                    .padding(.top, 2)
            } else if session.host != nil || session.canBeInterrupted {
                actions
                    .padding(.top, 2)
            }
        }
        .font(Theme.Font.label(11, .medium))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let host = session.host {
                Button("Open \(host.shortName)") { viewModel.focus(session) }
                    .buttonStyle(QuietButtonStyle())
                    .help("Brings \(host.name) forward")
            }
            if session.canBeInterrupted {
                Button {
                    viewModel.askToInterrupt(session)
                } label: {
                    Label("Interrupt", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(QuietButtonStyle(tint: Theme.danger))
                .help("Sends Ctrl+C to this Claude Code session")
            }
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sends Ctrl+C to \(session.name): its turn and every agent of it stop. The session stays open.")
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: viewModel.cancelInterrupt)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                // No Return shortcut: the destructive choice takes a click.
                Button("Interrupt \(session.name)") { viewModel.interrupt(session) }
                    .buttonStyle(QuietButtonStyle(tint: Theme.danger))
            }
        }
    }
}

/// A session waiting on the user, in amber: who waits, for how long, for what, and the way to its
/// window. In the card it heads its session; in the island and the popover it comes first.
struct WaitingRow: View {
    let session: ClaudeSession
    /// The card's width keeps the button to "Open"; the island has room for the app's name.
    var compact = false
    @EnvironmentObject private var viewModel: AgentsViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15, weight: .semibold))
                .ink(.amber)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.name) is waiting for you")
                    .font(Theme.Font.label(13, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                // The wait leads the second line: the title never has to give way to it.
                (Text(viewModel.waited(session)).foregroundColor(.primary)
                 + Text(" · " + viewModel.waitingDetail(session)))
                    .font(Theme.Font.label(11, .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if let host = session.host {
                Button(compact ? "Open" : "Open \(host.shortName)") { viewModel.focus(session) }
                    .buttonStyle(PillButtonStyle(tint: Theme.Accent.amber.color))
                    .help("Brings \(host.name) forward")
            }
        }
        .tile(Theme.Accent.amber.color, strength: 0.3, padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name) is waiting for you: \(viewModel.waitingDetail(session))")
    }
}

/// The sessions waiting on the user, for the island and the popover: each its own amber row,
/// above the quotas, since an answer is what unblocks the work.
struct WaitingList: View {
    @EnvironmentObject private var viewModel: AgentsViewModel
    var compact = false

    var body: some View {
        let waiting = viewModel.waiting
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Metric.gap) {
                ForEach(waiting) { session in
                    WaitingRow(session: session, compact: compact)
                }
            }
            .animation(Theme.Motion.accordion, value: waiting.map(\.id))
        }
    }
}

private extension String {
    /// "working" as a status beside a name reads "Working".
    var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
}
