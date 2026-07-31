import AppKit
import SwiftUI
import Combine

/// Source de vérité unique de l'interface : l'instantané d'usage + les préférences du widget.
@MainActor
final class UsageViewModel: ObservableObject {

    // MARK: - Données

    @Published private(set) var snapshot: UsageSnapshot = .placeholder
    @Published private(set) var isRefreshing = false

    /// Dernière panne d'actualisation, `nil` quand tout va bien. Le dernier instantané
    /// valide reste affiché : la panne se signale, elle ne remplace pas les données.
    @Published private(set) var errorMessage: String?

    // MARK: - Préférences (persistées)

    @Published var isMinimal: Bool { didSet { Defaults.isMinimal = isMinimal } }
    @Published var isAlwaysOnTop: Bool { didSet { Defaults.isAlwaysOnTop = isAlwaysOnTop } }
    @Published var isDetailsExpanded: Bool { didSet { Defaults.isDetailsExpanded = isDetailsExpanded } }

    /// Non persisté volontairement : l'état réel appartient à `SMAppService`, pas à nos préférences.
    @Published var launchAtLogin: Bool

    // MARK: - État de vue

    @Published var isProfileVisible = false

    /// Carte de bienvenue : visible tant que l'utilisateur n'a ni passé l'accueil ni été connecté.
    @Published var isWelcomeVisible = !Defaults.welcomed
    @Published private(set) var isSigningIn = false
    /// Le port loopback était pris : la page affiche `code#state`, à coller dans la carte.
    @Published var isAwaitingManualCode = false

    var isSignedIn: Bool { snapshot.isSignedIn }

    private let source: UsageDataSource
    private let oauth = ClaudeOAuth()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(source: UsageDataSource = AdaptiveUsageDataSource()) {
        self.source = source
        self.isMinimal = Defaults.isMinimal
        self.isAlwaysOnTop = Defaults.isAlwaysOnTop
        self.isDetailsExpanded = Defaults.isDetailsExpanded
        self.launchAtLogin = LaunchAtLogin.isEnabled
        startAutoRefresh()

        // Après une veille, le timer de 60 s ne se rattrape pas : sans ce rafraîchissement
        // immédiat, la carte afficherait des données périmées jusqu'au prochain tick.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - Actions

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fresh = try await source.fetch()
            errorMessage = nil
            withAnimation(Theme.Motion.gauge) {
                snapshot = fresh
            }
            // Déjà connecté (par exemple .credentials.json présent) : l'accueil n'a rien à vendre.
            if fresh.isSignedIn, isWelcomeVisible {
                dismissWelcome()
            }
        } catch UsageDataError.projectsUnreadable {
            errorMessage = "Impossible de lire le dossier des transcripts (droits d'accès ?)."
        } catch {
            errorMessage = "Actualisation échouée : \(error.localizedDescription)"
        }
    }

    func toggleMode() {
        withAnimation(Theme.Motion.mode) {
            isMinimal.toggle()
            if isMinimal { isProfileVisible = false }
        }
    }

    func toggleDetails() {
        withAnimation(Theme.Motion.accordion) {
            isDetailsExpanded.toggle()
        }
    }

    func toggleProfile() {
        withAnimation(Theme.Motion.popup) {
            isProfileVisible.toggle()
        }
    }

    /// Applique la demande puis recale l'affichage sur l'état réellement obtenu
    /// (un `register()` refusé ne doit pas laisser la case cochée).
    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.set(enabled)
    }

    // MARK: - Connexion Claude

    func startSignIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil

        switch oauth.begin() {
        case .manual:
            isAwaitingManualCode = true
        case .loopback:
            Task {
                do {
                    let credentials = try await oauth.awaitLoopbackCode()
                    await completeSignIn(credentials)
                } catch {
                    failSignIn(error)
                }
            }
        }
    }

    func submitManualCode(_ pasted: String) {
        guard isAwaitingManualCode else { return }
        Task {
            do {
                let credentials = try await oauth.redeemManualCode(pasted)
                await completeSignIn(credentials)
            } catch {
                failSignIn(error)
            }
        }
    }

    func cancelSignIn() {
        oauth.cancel()
        isSigningIn = false
        isAwaitingManualCode = false
    }

    func signOut() {
        Task {
            await ClaudeAccountClient.shared.signOut()
            withAnimation(Theme.Motion.popup) { isProfileVisible = false }
            await refresh()
        }
    }

    func dismissWelcome() {
        withAnimation(Theme.Motion.popup) { isWelcomeVisible = false }
        Defaults.welcomed = true
    }

    private func completeSignIn(_ credentials: OAuthCredentials) async {
        await ClaudeAccountClient.shared.signIn(credentials)
        isSigningIn = false
        isAwaitingManualCode = false
        dismissWelcome()
        await refresh()
    }

    private func failSignIn(_ error: Error) {
        isSigningIn = false
        isAwaitingManualCode = false
        errorMessage = (error as? OAuthError)?.errorDescription
            ?? "Connexion échouée : \(error.localizedDescription)"
    }

    private func startAutoRefresh() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        // `.common` : le tick survit aux drags de fenêtre et aux menus ouverts,
        // là où le mode par défaut le gèle.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Formatage

    /// « 3,14 Md », « 2,34 M », « 640 k » — séparateur décimal selon la locale système.
    /// Le palier des milliards n'est pas décoratif : en comptant les lectures de cache,
    /// une semaine chargée dépasse couramment le milliard de tokens.
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch count {
        case 1_000_000_000...:
            return "\(number(value / 1_000_000_000, digits: 2)) Md"
        case 1_000_000...:
            return "\(number(value / 1_000_000, digits: 2)) M"
        case 10_000...:
            return "\(number(value / 1_000, digits: 0)) k"
        case 1_000...:
            return "\(number(value / 1_000, digits: 1)) k"
        default:
            return number(value, digits: 0)
        }
    }

    /// « 2h 14 » ou « 14 min » : temps restant avant remise à zéro d'une fenêtre.
    static func countdown(to date: Date) -> String {
        let remaining = Int(date.timeIntervalSinceNow)
        guard remaining > 0 else { return "imminent" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours >= 24 { return "\(hours / 24) j \(hours % 24) h" }
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }

    /// « 14:30 »
    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// Écart au rythme d'une fenêtre, prêt à afficher. `nil` si aucune fenêtre n'est en cours.
    ///
    /// Le seuil de 4 points évite de qualifier d'« avance » le bruit d'une requête isolée.
    static func pace(_ window: UsageWindow) -> (text: String, color: Color)? {
        guard window.isActive else { return nil }

        let delta = window.paceDelta
        let points = Int((abs(delta) * 100).rounded())

        if points < 4 {
            return ("dans le rythme", Theme.Accent.sage.color)
        }
        if delta > 0 {
            return ("\(points) pts au-dessus du rythme",
                    delta > 0.20 ? Theme.danger : Theme.Accent.amber.color)
        }
        return ("\(points) pts sous le rythme", Theme.Accent.sage.color)
    }

    /// Initiale du jour pour l'axe de la sparkline : L, M, M, J, V, S, D.
    static func dayInitial(_ date: Date) -> String {
        String(dayFormatter.string(from: date).prefix(1)).uppercased()
    }

    /// `minimumFractionDigits = 0` : « 18 M » plutôt que « 18,00 M ».
    private static func number(_ value: Double, digits: Int) -> String {
        numberFormatter.maximumFractionDigits = digits
        numberFormatter.minimumFractionDigits = 0
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()
}

// MARK: - Persistance

/// Petit wrapper `UserDefaults` : `@AppStorage` n'est pas utilisable depuis une classe.
private enum Defaults {
    private static let store = UserDefaults.standard

    static var isMinimal: Bool {
        get { store.bool(forKey: "claudy.isMinimal") }
        set { store.set(newValue, forKey: "claudy.isMinimal") }
    }

    static var isAlwaysOnTop: Bool {
        get { store.object(forKey: "claudy.alwaysOnTop") as? Bool ?? true }
        set { store.set(newValue, forKey: "claudy.alwaysOnTop") }
    }

    static var isDetailsExpanded: Bool {
        get { store.bool(forKey: "claudy.detailsExpanded") }
        set { store.set(newValue, forKey: "claudy.detailsExpanded") }
    }

    static var welcomed: Bool {
        get { store.bool(forKey: "claudy.welcomed") }
        set { store.set(newValue, forKey: "claudy.welcomed") }
    }
}
