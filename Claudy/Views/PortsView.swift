import SwiftUI

/// The ports annex: what Claude Code left listening, and a way to close it. Below the ports, the
/// MCP servers Claude Code left running: they hold no port, but they hold memory.
///
/// The empty state is the common case and is written for it — an empty list here is good news,
/// not a failure.
struct PortsView: View {
    @EnvironmentObject private var viewModel: PortsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.gap) {
            switch viewModel.state {
            case .scanning:
                message("Scanning ports…")
            case .unavailable(let reason):
                message("Scan unavailable: \(reason)")
            case .ready(let ports, _) where ports.isEmpty:
                message("No port left open by Claude")
            case .ready(let ports, let isDegraded):
                if isDegraded {
                    Text("Process environments unreadable, so orphans cannot be detected")
                        .font(Theme.Font.label(11, .medium))
                        .ink(.amber)
                        .padding(.horizontal, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                portList(ports)
            }

            if !viewModel.mcpOrphans.isEmpty {
                Hairline()
                serverList(viewModel.mcpOrphans)
            }

            if viewModel.orphanCount > 1 {
                Button {
                    viewModel.requestBulkKill()
                } label: {
                    Label("Kill \(viewModel.orphanCount) orphans", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(tint: Theme.danger, isLarge: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.accordion, value: viewModel.ports.count)
        .animation(Theme.Motion.accordion, value: viewModel.mcpOrphans.count)
        .confirmationDialog(
            "Kill \(viewModel.orphanCount) processes?",
            isPresented: $viewModel.isConfirmingBulkKill,
            titleVisibility: .visible
        ) {
            Button("Kill \(viewModel.bulkKillTargets)", role: .destructive) {
                Task { await viewModel.killAllOrphans() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func portList(_ ports: [ListeningPort]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ports opened by Claude")
                .sectionLabel()
                .padding(.bottom, 6)

            ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                if index > 0 { divider }
                PortRow(port: port, failure: viewModel.failures[port.id]) {
                    Task { await viewModel.kill(port) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func serverList(_ servers: [McpOrphan]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MCP servers left behind")
                    .sectionLabel()
                Spacer(minLength: 0)
                Text(PortsViewModel.memory(viewModel.mcpMemory))
                    .font(Theme.Font.mono(11, .semibold))
                    .ink(.amber)
            }
            .padding(.bottom, 6)

            ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                if index > 0 { divider }
                McpServerRow(server: server, failure: viewModel.failures[server.id]) {
                    Task { await viewModel.kill(server) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 1)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.label(12, .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
    }
}
