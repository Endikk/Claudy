import SwiftUI

/// Account chip, at the top right of the header.
struct AvatarButton: View {
    let account: Account
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(account.initial)
                .font(Theme.Font.label(12, .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.Accent.coral.color))
                .overlay(
                    Circle().strokeBorder(.white.opacity(isActive ? 0.85 : 0.3), lineWidth: isActive ? 1.5 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Account")
    }
}

/// Account card, rendered *inside* the widget rather than as a `.popover`: an `NSPopover`
/// attached to a `.borderless` / `.nonactivatingPanel` window displays unreliably.
struct ProfilePopup: View {
    let account: Account
    /// Present only when a Claude session is open through Claudy.
    let onSignOut: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(account.initial)
                    .font(Theme.Font.label(15, .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.Accent.coral.color))

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(Theme.Font.label(13, .semibold))
                        .foregroundStyle(.primary)
                    if !account.email.isEmpty {
                        Text(account.email)
                            .font(Theme.Font.label(11, .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
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
                Text("No Claude account signed in on this machine")
                    .font(Theme.Font.label(11, .regular))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.0) { text, tint in
                        badge(text, tint: tint)
                    }
                }
            }

            if let onSignOut {
                Divider()
                    .padding(.vertical, 11)
                PopupRow(title: "Sign out", icon: "rectangle.portrait.and.arrow.right",
                         tint: Theme.danger, action: onSignOut)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
                .font(Theme.Font.label(12, .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// An action row on the account card, highlighted on hover.
private struct PopupRow: View {
    let title: String
    let icon: String
    var tint: Color = .primary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
                Text(title)
                    .font(Theme.Font.label(12, .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(isHovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

