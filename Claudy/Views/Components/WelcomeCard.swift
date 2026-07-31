import SwiftUI

/// Carte de première ouverture : dit ce que Claudy lit, et propose la connexion Claude
/// (quotas réels). Rendue dans la carte, comme la fiche compte — pas de `NSPopover`.
struct WelcomeCard: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @State private var manualCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ClaudeMark()
                    .fill(Theme.Accent.coral.color)
                    .frame(width: 18, height: 18)
                    .shadow(color: Theme.Accent.coral.color.opacity(0.5), radius: 6)
                Text("Bienvenue dans Claudy")
                    .font(Theme.Font.label(13.5, .semibold))
                Spacer(minLength: 0)
            }

            Text("Claudy lit les transcripts locaux de Claude Code et, si tu te connectes, "
                 + "les vrais quotas de ton compte — les mêmes chiffres que claude.ai. "
                 + "Rien ne quitte ton Mac, sauf vers l'API d'Anthropic avec ton propre jeton.")
                .font(Theme.Font.label(10.5, .regular))
                .foregroundStyle(.primary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isAwaitingManualCode {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Colle le code affiché par la page :")
                        .font(Theme.Font.label(10.5, .medium))
                    TextField("code#state", text: $manualCode)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Font.value(11, .regular))
                    HStack(spacing: 10) {
                        Button("Valider") { viewModel.submitManualCode(manualCode) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Accent.coral.color)
                            .disabled(manualCode.trimmed.isEmpty)
                        Button("Annuler") { viewModel.cancelSignIn() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary.opacity(0.5))
                    }
                }
            } else if viewModel.isSigningIn {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("En attente du navigateur…")
                        .font(Theme.Font.label(10.5, .medium))
                        .foregroundStyle(.primary.opacity(0.6))
                    Spacer(minLength: 0)
                    Button("Annuler") { viewModel.cancelSignIn() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary.opacity(0.5))
                }
            } else {
                Button {
                    viewModel.startSignIn()
                } label: {
                    Text("Se connecter à Claude")
                        .font(Theme.Font.label(11.5, .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Accent.coral.color)

                Button("Plus tard — jauges estimées en attendant") {
                    viewModel.dismissWelcome()
                }
                .buttonStyle(.plain)
                .font(Theme.Font.label(10, .medium))
                .foregroundStyle(.primary.opacity(0.45))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
    }
}
