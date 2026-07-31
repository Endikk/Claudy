import SwiftUI

/// Pastille du compte, en haut à droite de l'en-tête.
struct AvatarButton: View {
    let account: Account
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(account.initial)
                .font(Theme.Font.label(11, .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Theme.Accent.coral.color, Theme.Accent.coral.color.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    Circle().stroke(.white.opacity(isActive ? 0.85 : 0.22), lineWidth: 1)
                )
                .shadow(color: Theme.Accent.coral.color.opacity(0.4), radius: 5, y: 1)
        }
        .buttonStyle(.plain)
        .help("Compte")
    }
}

/// Fiche compte.
///
/// Volontairement rendue *dans* la carte plutôt qu'en `.popover` : un `NSPopover` attaché à un
/// panneau `.borderless` / `.nonactivatingPanel` s'affiche de façon peu fiable et casse
/// l'esthétique du widget.
struct ProfilePopup: View {
    let account: Account
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(account.initial)
                    .font(Theme.Font.label(15, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [Theme.Accent.coral.color, Theme.Accent.coral.color.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(Theme.Font.label(13, .semibold))
                        .foregroundStyle(.primary)
                    // Compte non connecté : pas de ligne vide, pas d'adresse inventée.
                    if !account.email.isEmpty {
                        Text(account.email)
                            .font(Theme.Font.label(10.5, .regular))
                            .foregroundStyle(.primary.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.4))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            let badges = [
                (account.plan, Theme.Accent.coral.color),
                (account.organization, Theme.Accent.sky.color),
                (account.isAdmin ? "Admin" : "", Theme.Accent.sage.color)
            ].filter { !$0.0.isEmpty }

            if badges.isEmpty {
                Text("Aucun compte Claude connecté sur cette machine")
                    .font(Theme.Font.label(10, .regular))
                    .foregroundStyle(.primary.opacity(0.4))
            } else {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.0) { text, tint in
                        badge(text, tint: tint)
                    }
                }
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

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.Font.label(9.5, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
            .lineLimit(1)
    }
}

