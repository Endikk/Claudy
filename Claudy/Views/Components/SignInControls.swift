import SwiftUI

/// The way in, wherever Claudy shows it signed out: the onboarding card and the menu bar
/// popover. It covers the whole sign-in, including the paste field used when the loopback port
/// is taken, so neither face can get stuck halfway.
struct SignInControls: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @State private var manualCode = ""

    var body: some View {
        if viewModel.isAwaitingManualCode {
            manualEntry
        } else if viewModel.isSigningIn {
            waiting
        } else {
            signInButton
        }
    }

    private var manualEntry: some View {
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
                cancelButton
            }
        }
    }

    private var waiting: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text("Waiting for the browser…")
                .font(Theme.Font.label(10.5, .medium))
                .foregroundStyle(.primary.opacity(0.6))
            Spacer(minLength: 0)
            cancelButton
        }
        .padding(.vertical, 6)
    }

    private var cancelButton: some View {
        Button("Cancel") { viewModel.cancelSignIn() }
            .buttonStyle(.plain)
            .font(Theme.Font.label(10.5, .medium))
            .foregroundStyle(.primary.opacity(0.5))
    }

    private var signInButton: some View {
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

            Text("Official claude.ai sign-in, revocable at any time.")
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
