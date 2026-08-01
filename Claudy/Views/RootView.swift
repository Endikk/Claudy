import SwiftUI

/// Racine du widget : le fond glass, la bascule des deux modes, la fiche compte et le menu contextuel.
struct RootView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @Environment(\.colorScheme) private var scheme

    /// Ce que la carte affiche. Aucune jauge sans session Claude : à la place,
    /// l'onboarding — pas de chiffres estimés.
    private enum Display {
        case loading, onboarding, minimal, full
    }

    private var display: Display {
        if !viewModel.hasLoaded { return .loading }
        if !viewModel.snapshot.isDemo && !viewModel.isSignedIn { return .onboarding }
        return viewModel.isMinimal ? .minimal : .full
    }

    private var corner: CGFloat {
        switch display {
        case .minimal, .loading: Theme.Metric.minimalCorner
        case .full, .onboarding: Theme.Metric.cardCorner
        }
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
            switch display {
            case .loading: LoadingCard()
            case .onboarding: OnboardingView()
            case .minimal: MinimalView()
            case .full: FullView()
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
        .overlay(crackLayer)
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
                    onSignOut: viewModel.isSignedIn ? { viewModel.signOut() } : nil,
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

    // MARK: - Surcharge

    /// Au-delà de 95 %, la carte se fissure — et le liseré vire au rouge.
    @ViewBuilder
    private var crackLayer: some View {
        let strain = viewModel.snapshot.strain
        if strain > 0, display == .full || display == .minimal {
            ZStack {
                CrackOverlay(intensity: strain)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.danger.opacity(0.55 * strain), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(Theme.Motion.gauge, value: strain)
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

        if viewModel.isSignedIn {
            Button("Se déconnecter de Claude") { viewModel.signOut() }
        } else {
            Button {
                viewModel.startSignIn()
            } label: {
                Label("Se connecter à Claude…", systemImage: "person.crop.circle.badge.checkmark")
            }
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
