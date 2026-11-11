import SwiftUI

/// The widget root: the glass surface, the two-mode switch, the account card and the context
/// menu.
struct RootView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var updates: UpdateChecker
    @EnvironmentObject private var notifier: Notifier

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

    var body: some View {
        card
            .background(CardShadow(corner: corner))
            .padding(Theme.Metric.shadowInset)
            // Any click on the card counts as opening Claudy: the wave has been seen.
            .simultaneousGesture(TapGesture().onEnded { updates.acknowledgeGreeting() })
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
        .cardSurface(corner: corner)
        .overlay(strainBorder)
        .overlay(profileLayer)
    }

    // MARK: - Account card

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

    /// One switch per kind, in two groups, as in the menu bar item's menu.
    @ViewBuilder
    private var notificationSwitches: some View {
        if notifier.isDenied {
            Button("Turned off in System Settings…") { notifier.openSettings() }
            Divider()
        }
        Section("Quota") {
            ForEach(NotificationKind.allCases.filter(\.isQuota), id: \.self) { kind in
                Toggle(kind.menuTitle, isOn: Binding(get: { notifier.isEnabled(kind) },
                                                     set: { notifier.set(kind, on: $0) }))
            }
        }
        Section("Sessions and agents") {
            ForEach(NotificationKind.allCases.filter { !$0.isQuota }, id: \.self) { kind in
                Toggle(kind.menuTitle, isOn: Binding(get: { notifier.isEnabled(kind) },
                                                     set: { notifier.set(kind, on: $0) }))
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            Task { await viewModel.refresh(userInitiated: true) }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }

        Button(action: viewModel.toggleMode) {
            Label(
                viewModel.isMinimal ? "Full mode" : "Minimal mode",
                systemImage: viewModel.isMinimal ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
            )
        }

        ForEach(viewModel.placement.offered(hasNotch: viewModel.hasNotchedScreen), id: \.self) { placement in
            Button {
                viewModel.place(placement)
            } label: {
                Label(placement.menuTitle, systemImage: placement.systemImage)
            }
        }

        Divider()

        Menu {
            notificationSwitches
        } label: {
            Label("Notifications", systemImage: "bell")
        }

        if (NSApp.delegate as? AppDelegate)?.isHotKeyActive == true {
            Button {
                (NSApp.delegate as? AppDelegate)?.toggleClaudy()
            } label: {
                Label("Show or hide Claudy", systemImage: "eye")
            }
            .keyboardShortcut(KeyEquivalent(Character(GlobalHotKey.keyEquivalent)), modifiers: [.control, .option])
        } else {
            Button {
                (NSApp.delegate as? AppDelegate)?.toggleClaudy()
            } label: {
                Label("Show or hide Claudy (\(GlobalHotKey.display) is taken)", systemImage: "eye")
            }
        }

        Button {
            viewModel.exportUsage()
        } label: {
            Label("Export usage as CSV…", systemImage: "square.and.arrow.up")
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
            Button("Launch at login (unavailable, app is unsigned)") {}
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
