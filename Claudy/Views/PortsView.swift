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
            case .ready(let ports) where ports.isEmpty:
                message("No port left open by Claude.")
            case .ready(let ports):
                list(ports)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.accordion, value: viewModel.ports.count)
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
