import SwiftUI

/// One open port. The kill control stays hidden until the pointer is on the row: an
/// irreversible action has no business being one stray click away at rest.
struct PortRow: View {
    let port: ListeningPort
    let failure: String?
    let onKill: () -> Void

    @State private var isHovered = false
    @State private var isKilling = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(port.port)")
                .font(Theme.Font.value(13, .semibold))
                .foregroundStyle(Theme.Accent.coral.color.opacity(0.95))
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.command)
                    .font(Theme.Font.label(11, .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(subtitle)
                        .font(Theme.Font.label(9.5, .medium))
                        .foregroundStyle(.primary.opacity(0.38))
                        .lineLimit(1)

                    if port.attribution == .orphan {
                        Text("orphan")
                            .font(Theme.Font.label(8.5, .semibold))
                            .foregroundStyle(Theme.Accent.amber.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.Accent.amber.color.opacity(0.16)))
                    }
                }

                if let failure {
                    Text(failure)
                        .font(Theme.Font.label(9.5, .medium))
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

    private var subtitle: String {
        let age = PortsViewModel.age(since: port.startedAt)
        guard let project = port.projectName else { return age }
        return "\(project) · \(age)"
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
                .foregroundStyle(.primary.opacity(0.55))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.primary.opacity(0.08)))
                .opacity(isHovered ? 1 : 0)
                .onTapGesture {
                    isKilling = true
                    onKill()
                }
                .help("Kill the process on port \(port.port)")
                .accessibilityLabel("Kill the process on port \(port.port)")
        }
    }
}
