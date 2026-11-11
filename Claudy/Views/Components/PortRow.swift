import SwiftUI

/// One open port.
struct PortRow: View {
    let port: ListeningPort
    let failure: String?
    let onKill: () -> Void

    var body: some View {
        ReapableRow(
            lead: "\(port.port)",
            leadSize: 14,
            title: port.command,
            subtitle: ReapableRow.subtitle(project: port.projectName, startedAt: port.startedAt),
            isOrphan: port.attribution == .orphan,
            failure: failure,
            killLabel: "Kill the process on port \(port.port)",
            onKill: onKill
        )
    }
}

/// One MCP server left behind. Its weight leads where a port shows its number: the memory is
/// the reason to kill it.
struct McpServerRow: View {
    let server: McpOrphan
    let failure: String?
    let onKill: () -> Void

    var body: some View {
        ReapableRow(
            lead: PortsViewModel.memory(server.residentBytes),
            leadSize: 12,
            title: server.name,
            subtitle: ReapableRow.subtitle(project: server.projectName, startedAt: server.startedAt),
            isOrphan: true,
            failure: failure,
            killLabel: "Kill the MCP server \(server.name) and its processes",
            onKill: onKill
        )
    }
}

/// A process the Ports tab can kill. The kill control stays hidden until the pointer is on the
/// row: an irreversible action has no business being one stray click away at rest.
struct ReapableRow: View {
    let lead: String
    let leadSize: CGFloat
    let title: String
    let subtitle: String
    let isOrphan: Bool
    let failure: String?
    let killLabel: String
    let onKill: () -> Void

    /// Wide enough for "412 MB", so the ports and the servers below them share one column.
    private static let leadWidth: CGFloat = 60

    @State private var isHovered = false
    @State private var isKilling = false

    static func subtitle(project: String?, startedAt: Date) -> String {
        let age = PortsViewModel.age(since: startedAt)
        guard let project else { return age }
        return "\(project) · \(age)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(lead)
                .font(Theme.Font.mono(leadSize, .semibold))
                .ink(isOrphan ? .amber : .sky)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: Self.leadWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.mono(13, .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(subtitle)
                        .font(Theme.Font.label(11, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if isOrphan {
                        Text("Orphan")
                            .font(Theme.Font.label(11, .semibold))
                            .ink(.amber)
                    }
                }

                if let failure {
                    Text(failure)
                        .font(Theme.Font.label(11, .medium))
                        .foregroundStyle(Theme.danger.opacity(0.9))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            killButton
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onChange(of: failure) { _ in isKilling = false }
    }

    @ViewBuilder
    private var killButton: some View {
        if isKilling {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.primary.opacity(0.08)))
                .opacity(isHovered ? 1 : 0)
                .onTapGesture {
                    isKilling = true
                    onKill()
                }
                .help(killLabel)
                .accessibilityLabel(killLabel)
        }
    }
}
