import SwiftUI

/// The widget root: the glass background, the two-mode switch, the account card and the
/// context menu.
struct RootView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @Environment(\.colorScheme) private var scheme

    /// What the card shows. No gauges without a Claude session: onboarding takes their place,
    /// never estimated figures.
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
                        colors: isDark
                            ? [.white.opacity(0.24), .white.opacity(0.05)]
                            : [.black.opacity(0.10), .black.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(strainBorder)
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

    /// Past 95 % the card's hairline turns red. It is the only overload signal: discreet, kept
    /// to the edge, and never covering the content.
    @ViewBuilder
    private var strainBorder: some View {
        if isStrained {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.28 * viewModel.snapshot.strain), lineWidth: 1)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(Theme.Motion.gauge, value: viewModel.snapshot.strain)
        }
    }

    /// Visible strain: past 95 %, and only in the modes that carry gauges.
    private var isStrained: Bool {
        viewModel.snapshot.strain > 0 && (display == .full || display == .minimal)
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            Task { await viewModel.refresh() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }

        Button(action: viewModel.toggleMode) {
            Label(
                viewModel.isMinimal ? "Full mode" : "Minimal mode",
                systemImage: viewModel.isMinimal ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
            )
        }

        Button(action: viewModel.toggleMenuBar) {
            Label("Show in menu bar", systemImage: "menubar.arrow.up.rectangle")
        }

        Divider()

        if viewModel.isSignedIn {
            Button("Sign out of Claude") { viewModel.signOut() }
        } else {
            Button {
                viewModel.startSignIn()
            } label: {
                Label("Sign in to Claude…", systemImage: "person.crop.circle.badge.checkmark")
            }
        }

        Divider()

        Toggle("Always on top", isOn: $viewModel.isAlwaysOnTop)

        if LaunchAtLogin.isAdHocSigned {
            Button("Launch at login (unavailable — app is unsigned)") {}
                .disabled(true)
        } else {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                )
            )
        }

        Divider()

        Button("Quit Claudy") {
            NSApp.terminate(nil)
        }
    }
}
