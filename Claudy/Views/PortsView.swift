import SwiftUI

/// The ports annex: what Claude Code left listening, and a way to close it.
///
/// The empty state is the common case and is written for it — an empty list here is good news,
/// not a failure.
struct PortsView: View {
    @EnvironmentObject private var viewModel: PortsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch viewModel.state {
            case .scanning:
                message("Scanning ports…")
            case .unavailable(let reason):
                message("Scan unavailable — \(reason)")
            case .ready(let ports, _) where ports.isEmpty:
                message("No port left open by Claude.")
            case .ready(let ports, let isDegraded):
                if isDegraded {
                    Text("Process environments unreadable — orphans cannot be detected.")
                        .font(Theme.Font.label(9.5, .medium))
                        .foregroundStyle(Theme.Accent.amber.color.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                list(ports)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.accordion, value: viewModel.ports.count)
        .confirmationDialog(
            "Kill \(viewModel.orphanCount) processes?",
            isPresented: $viewModel.isConfirmingBulkKill,
            titleVisibility: .visible
        ) {
            Button("Kill \(viewModel.orphans.map { String($0.port) }.joined(separator: ", "))", role: .destructive) {
                Task { await viewModel.killAllOrphans() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func list(_ ports: [ListeningPort]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ports opened by Claude")
                .microLabel(0.55)
                .padding(.bottom, 4)

            ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                if index > 0 {
                    Rectangle()
                        .fill(.primary.opacity(0.06))
                        .frame(height: 1)
                }
                PortRow(port: port, failure: viewModel.failures[port.id]) {
                    Task { await viewModel.kill(port) }
                }
            }

            if viewModel.orphanCount > 1 {
                Button {
                    viewModel.requestBulkKill()
                } label: {
                    Text("Kill \(viewModel.orphanCount) orphans")
                        .font(Theme.Font.label(9.5, .semibold))
                        .foregroundStyle(Theme.danger.opacity(0.9))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.label(11, .medium))
            .foregroundStyle(.primary.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }
}
