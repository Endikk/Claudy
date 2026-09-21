import SwiftUI

/// The popover under the menu bar item: a shorter card than full mode. The 5h session, the
/// two weekly columns, and a footer to refresh or bring the floating widget back. Totals,
/// sparkline, details and ports stay in the widget.
struct MenuBarView: View {
    @EnvironmentObject private var viewModel: UsageViewModel

    private var snapshot: UsageSnapshot { viewModel.snapshot }
    private var session: UsageWindow { snapshot.session }
    private var sessionTint: Color { Theme.tint(session.accent, at: session.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if viewModel.isSignedIn || snapshot.isDemo {
                sessionBlock
                HStack(spacing: 9) {
                    StatColumn(window: snapshot.weekly)
                    StatColumn(window: snapshot.sonnet)
                }
            } else {
                signedOut
            }
            footer
        }
        .padding(Theme.Metric.padding)
        .frame(width: Theme.Metric.menuBarWidth)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ClaudyTyping(tint: sessionTint, isTyping: session.isActive)
                .frame(width: 27 * ClaudyTyping.aspectRatio, height: 27)

            Text("Claudy")
                .font(Theme.Font.label(14, .semibold))
                .foregroundStyle(.primary.opacity(0.9))

            Spacer(minLength: 0)

            if let message = viewModel.errorMessage {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 6, height: 6)
                    .help(message)
            }

            if !snapshot.activeModel.isEmpty {
                Text(snapshot.activeModel)
                    .font(Theme.Font.label(9.5, .semibold))
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.primary.opacity(0.08)))
            }
        }
    }

    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(session.title) · \(session.window)")
                        .microLabel(0.55)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(session.isMeasured ? "\(Int(session.percent * 100))" : "—")
                            .font(Theme.Font.hero(32))
                            .foregroundStyle(.primary.opacity(session.isMeasured ? 0.95 : 0.4))
                        if session.isMeasured {
                            Text("%")
                                .font(Theme.Font.label(14, .medium))
                                .foregroundStyle(.primary.opacity(0.38))
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(session.isActive ? "reset" : (session.isMeasured ? "session" : "quota"))
                        .microLabel(0.35)
                    Text(session.isActive ? UsageViewModel.clock(session.resetDate)
                                          : (session.isMeasured ? "inactive" : "unavailable"))
                        .font(Theme.Font.value(13, .semibold))
                        .foregroundStyle(.primary.opacity(0.8))
                    if session.isActive {
                        Text("in \(UsageViewModel.countdown(to: session.resetDate))")
                            .font(Theme.Font.label(9.5, .medium))
                            .foregroundStyle(.primary.opacity(0.35))
                    }
                }
            }

            UsageBar(percent: session.percent, tint: sessionTint, height: 6,
                     pace: session.isActive ? session.elapsed : nil)
        }
    }

    /// No gauges without a session, same rule as the widget: say so and offer the way in.
    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not signed in to Claude")
                .font(Theme.Font.label(12, .medium))
                .foregroundStyle(.primary.opacity(0.7))
            Button("Sign in to Claude…") { viewModel.startSignIn() }
                .disabled(viewModel.isSigningIn)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("updated \(UsageViewModel.clock(snapshot.updatedAt))")
                .font(Theme.Font.label(9.5, .medium))
                .foregroundStyle(.primary.opacity(0.35))

            Spacer(minLength: 0)

            Button {
                Task { await viewModel.refresh(userInitiated: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshing)
            .help("Refresh")

            Button("Floating widget", action: viewModel.toggleMenuBar)
                .help("Leave the menu bar and show the widget on the desktop")
        }
        .buttonStyle(.borderless)
        .font(Theme.Font.label(11, .medium))
    }
}
