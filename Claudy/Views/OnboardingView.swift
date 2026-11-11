import SwiftUI

/// Card shown while no Claude session is open.
///
/// Claudy **never** shows estimated quotas, so signing in is the way in. This card replaces the
/// gauges outright: no invented figures behind a veil, no apologetic badge.
struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 0) {
            mark
                .padding(.top, 28)
                .padding(.bottom, 14)

            Text("Claudy")
                .font(Theme.Font.label(22, .semibold))
                .foregroundStyle(.primary)

            Text("Your real Claude quotas")
                .font(Theme.Font.label(13, .regular))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 14) {
                feature("gauge.with.needle.fill", .coral,
                        "Real quotas",
                        "The same figures as claude.ai, to the minute")
                feature("metronome.fill", .sky,
                        "Your pace",
                        "Ahead of or behind each window, at a glance")
                feature("lock.shield.fill", .teal,
                        "Nothing leaves your Mac",
                        "The only exchange is Anthropic's API, with your own token")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 22)

            SignInControls()
                .padding(.horizontal, 6)
                .padding(.bottom, 22)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .frame(width: Theme.Metric.fullWidth)
    }

    // MARK: - Brand mark

    private var mark: some View {
        ClaudyTyping()
            .frame(width: 60 * ClaudyTyping.aspectRatio, height: 60)
    }

    // MARK: - Arguments

    private func feature(_ icon: String, _ accent: Theme.Accent,
                         _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.label(13, .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(Theme.Font.label(12, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Micro-card shown during the very first reading, before we know whether a session exists —
/// it spares already signed-in users a flash of onboarding.
struct LoadingCard: View {
    var body: some View {
        HStack(spacing: 10) {
            ClaudyTyping()
                .frame(width: 27 * ClaudyTyping.aspectRatio, height: 27)
            ProgressView()
                .controlSize(.small)
        }
        .padding(.vertical, 13)
        .frame(width: Theme.Metric.minimalWidth)
    }
}
