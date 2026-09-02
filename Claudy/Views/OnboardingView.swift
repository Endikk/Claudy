import SwiftUI

/// Card shown while no Claude session is open.
///
/// Claudy **never** shows estimated quotas, so signing in is the way in. This card replaces the
/// gauges outright: no invented figures behind a veil, no apologetic badge.
struct OnboardingView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @State private var manualCode = ""

    var body: some View {
        VStack(spacing: 0) {
            mark
                .padding(.top, 28)
                .padding(.bottom, 14)

            Text("claudy")
                .font(Theme.Font.label(20, .semibold))
                .foregroundStyle(.primary.opacity(0.92))

            Text("Your real Claude quotas.")
                .font(Theme.Font.label(11, .medium))
                .foregroundStyle(.primary.opacity(0.5))
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 13) {
                feature("gauge.with.needle.fill", .coral,
                        "Real quotas",
                        "The same figures as claude.ai, to the minute.")
                feature("metronome.fill", .amber,
                        "Your pace",
                        "Ahead of or behind each window, at a glance.")
                feature("lock.shield.fill", .sage,
                        "Nothing leaves your Mac",
                        "The only exchange is Anthropic's API, with your own token.")
            }
            .padding(.vertical, 20)

            action
                .padding(.bottom, 22)
        }
        .padding(.horizontal, Theme.Metric.padding + 6)
        .frame(width: Theme.Metric.fullWidth)
    }

    // MARK: - Marque

    private var mark: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Accent.coral.color.opacity(0.22), .clear],
                        center: .center, startRadius: 4, endRadius: 40
                    )
                )
                .frame(width: 74, height: 74)

            ClaudeMark()
                .fill(Theme.Accent.coral.color)
                .frame(width: 36, height: 36)
                .shadow(color: Theme.Accent.coral.color.opacity(0.55), radius: 11)
        }
    }

    // MARK: - Arguments

    private func feature(_ icon: String, _ accent: Theme.Accent,
                         _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent.color)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.color.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(Theme.Font.label(11.5, .semibold))
                    .foregroundStyle(.primary.opacity(0.88))
                Text(detail)
                    .font(Theme.Font.label(10, .regular))
                    .foregroundStyle(.primary.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var action: some View {
        if viewModel.isAwaitingManualCode {
            VStack(alignment: .leading, spacing: 7) {
                Text("Paste the code the page shows:")
                    .font(Theme.Font.label(10.5, .medium))
                    .foregroundStyle(.primary.opacity(0.6))
                TextField("code#state", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Font.value(11, .regular))
                HStack(spacing: 12) {
                    Button("Submit") { viewModel.submitManualCode(manualCode) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Accent.coral.color)
                        .disabled(manualCode.trimmed.isEmpty)
                    Button("Cancel") { viewModel.cancelSignIn() }
                        .buttonStyle(.plain)
                        .font(Theme.Font.label(10.5, .medium))
                        .foregroundStyle(.primary.opacity(0.5))
                }
            }
        } else if viewModel.isSigningIn {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("En attente du navigateur…")
                    .font(Theme.Font.label(10.5, .medium))
                    .foregroundStyle(.primary.opacity(0.6))
                Spacer(minLength: 0)
                Button("Cancel") { viewModel.cancelSignIn() }
                    .buttonStyle(.plain)
                    .font(Theme.Font.label(10.5, .medium))
                    .foregroundStyle(.primary.opacity(0.5))
            }
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 9) {
                Button {
                    viewModel.startSignIn()
                } label: {
                    Text("Sign in to Claude")
                        .font(Theme.Font.label(12.5, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Theme.Accent.coral.color,
                                             Theme.Accent.coral.color.opacity(0.78)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        )
                        .shadow(color: Theme.Accent.coral.color.opacity(0.38), radius: 9, y: 2)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Text("Official claude.ai sign-in — revocable at any time.")
                    .font(Theme.Font.label(9, .medium))
                    .foregroundStyle(.primary.opacity(0.35))

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(Theme.Font.label(9.5, .medium))
                        .foregroundStyle(Theme.danger.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Micro-card shown during the very first reading, before we know whether a session exists —
/// it spares already signed-in users a flash of onboarding.
struct LoadingCard: View {
    var body: some View {
        HStack(spacing: 10) {
            ClaudeMark()
                .fill(Theme.Accent.coral.color)
                .frame(width: 16, height: 16)
                .shadow(color: Theme.Accent.coral.color.opacity(0.45), radius: 5)
            ProgressView()
                .controlSize(.small)
        }
        .padding(.vertical, 13)
        .frame(width: Theme.Metric.minimalWidth)
    }
}
