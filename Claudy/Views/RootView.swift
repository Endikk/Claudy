import SwiftUI

/// Racine du widget : le fond glass, la bascule des deux modes, la fiche compte et le menu contextuel.
struct RootView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @Environment(\.colorScheme) private var scheme

    private var corner: CGFloat {
        viewModel.isMinimal ? Theme.Metric.minimalCorner : Theme.Metric.cardCorner
    }

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        card
            // Marge transparente : c'est l'espace où l'ombre portée peut s'étaler,
            // la fenêtre étant elle-même sans ombre système.
            .padding(Theme.Metric.shadowInset)
            .contextMenu { menu }
    }

    private var card: some View {
        Group {
            if viewModel.isMinimal {
                MinimalView()
            } else {
                FullView()
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        // En clair, un liseré blanc serait invisible : on passe en noir translucide.
                        colors: isDark
                            ? [.white.opacity(0.24), .white.opacity(0.05)]
                            : [.black.opacity(0.10), .black.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(profileLayer)
        .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
    }

    private var cardBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blending: .behindWindow)
            LinearGradient(
                colors: isDark
                    ? [.white.opacity(0.10), .white.opacity(0.015)]
                    : [.white.opacity(0.30), .white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Halo corail discret : ancre la marque Claude dans le coin haut-gauche.
            RadialGradient(
                colors: [Theme.Accent.coral.color.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 240
            )
        }
    }

    // MARK: - Fiche compte

    @ViewBuilder
    private var profileLayer: some View {
        if viewModel.isProfileVisible {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.22)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.toggleProfile() }

                ProfilePopup(
                    account: viewModel.snapshot.account,
                    onClose: viewModel.toggleProfile
                )
                .frame(width: 262)
                .padding(.top, 42)
                .padding(.trailing, 12)
                .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    // MARK: - Menu contextuel

    @ViewBuilder
    private var menu: some View {
        Button {
            Task { await viewModel.refresh() }
        } label: {
            Label("Rafraîchir", systemImage: "arrow.clockwise")
        }

        Button(action: viewModel.toggleMode) {
            Label(
                viewModel.isMinimal ? "Mode complet" : "Mode minimal",
                systemImage: viewModel.isMinimal ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
            )
        }

        Divider()

        Toggle("Toujours au premier plan", isOn: $viewModel.isAlwaysOnTop)

        if LaunchAtLogin.isAdHocSigned {
            // `SMAppService.register()` refuse les binaires ad hoc : annoncer l'option
            // indisponible vaut mieux qu'une case qui se décoche toute seule.
            Button("Lancer au démarrage (indisponible — app non signée)") {}
                .disabled(true)
        } else {
            Toggle(
                "Lancer au démarrage",
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                )
            )
        }

        Divider()

        Button("Quitter Claudy") {
            NSApp.terminate(nil)
        }
    }
}
