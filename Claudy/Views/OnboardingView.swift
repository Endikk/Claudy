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

            SignInControls()
                .padding(.bottom, 22)
        }
        .padding(.horizontal, Theme.Metric.padding + 6)
        .frame(width: Theme.Metric.fullWidth)
    }

    // MARK: - Brand mark

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

            ClaudyTyping()
                .frame(width: 54 * ClaudyTyping.aspectRatio, height: 54)
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
