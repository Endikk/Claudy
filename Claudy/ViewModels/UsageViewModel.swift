import AppKit
import SwiftUI

/// The UI's single source of truth: the usage snapshot plus the widget's preferences.
@MainActor
final class UsageViewModel: ObservableObject {

    @Published private(set) var snapshot: UsageSnapshot = .placeholder
    @Published private(set) var isRefreshing = false

    /// Last refresh failure, `nil` when all is well. The last valid snapshot stays on screen:
    /// a failure announces itself, it does not replace the data.
    @Published private(set) var errorMessage: String?

    @Published var isMinimal: Bool { didSet { Defaults.isMinimal = isMinimal } }
    @Published var isAlwaysOnTop: Bool { didSet { Defaults.isAlwaysOnTop = isAlwaysOnTop } }
    @Published var isDetailsExpanded: Bool { didSet { Defaults.isDetailsExpanded = isDetailsExpanded } }

    /// Deliberately not persisted: the real state belongs to `SMAppService`, not to our prefs.
    @Published var launchAtLogin: Bool

    @Published var isProfileVisible = false

    /// False until the first reading: while we work out whether a Claude session exists the card
    /// shows a loading state — no ghost onboarding, no placeholder gauges.
    @Published private(set) var hasLoaded = false
    @Published private(set) var isSigningIn = false
    /// The loopback port was taken: the page shows `code#state` for pasting into the card.
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

    /// Takes a usage reading. `userInitiated` lifts any backoff in progress: a click on
    /// "refresh" must attempt something, even mid-way through an hour-long wait after a 429.
    func refresh(userInitiated: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if userInitiated { await ClaudeAccountClient.shared.resetBackoff() }

        do {
            let fresh = try await source.fetch()
            errorMessage = nil
            withAnimation(Theme.Motion.gauge) {
                snapshot = fresh
            }
        } catch UsageDataError.projectsUnreadable {
            errorMessage = "Could not read the transcripts folder (permissions?)."
        } catch {
            errorMessage = "Refresh failed: \(error.localizedDescription)"
        }
        withAnimation(Theme.Motion.mode) {
            hasLoaded = true
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

    /// Applies the request, then realigns the UI with the state actually reached — a refused
    /// `register()` must not leave the box ticked.
    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.set(enabled)
    }

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

    private func completeSignIn(_ credentials: OAuthCredentials) async {
        await ClaudeAccountClient.shared.signIn(credentials)
        isSigningIn = false
        isAwaitingManualCode = false
        await refresh()
    }

    private func failSignIn(_ error: Error) {
        isSigningIn = false
        isAwaitingManualCode = false
        errorMessage = (error as? OAuthError)?.errorDescription
            ?? "Sign-in failed: \(error.localizedDescription)"
    }

    /// Three minutes: Anthropic's quotas move by the minute, and polling faster brought nothing
    /// but a cascade of 429s (the client caches for 60 s anyway). Opening the card and waking the
    /// machine each trigger an immediate reading.
    private static let refreshInterval: TimeInterval = 180

    private func startAutoRefresh() {
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// "3.14 B", "2.34 M", "640 k" — decimal separator follows the system locale. The billions
    /// step is not decorative: counting cache reads, a busy week routinely passes a billion tokens.
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch count {
        case 1_000_000_000...:
            return "\(number(value / 1_000_000_000, digits: 2)) B"
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

    /// "2 h 14 min" or "14 min": time left before a window resets.
    static func countdown(to date: Date) -> String {
        let remaining = Int(date.timeIntervalSinceNow)
        guard remaining > 0 else { return "any moment" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours >= 24 { return "\(hours / 24) d \(hours % 24) h" }
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }

    /// "14:30"
    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// A window's distance from its expected pace, ready to display. `nil` when no window is
    /// running. The four-point threshold keeps the noise of a single request from being called
    /// "ahead".
    static func pace(_ window: UsageWindow) -> (text: String, color: Color)? {
        guard window.isActive else { return nil }

        let delta = window.paceDelta
        let points = Int((abs(delta) * 100).rounded())

        if points < 4 {
            return ("on pace", Theme.Accent.sage.color)
        }
        if delta > 0 {
            return ("\(points) pts ahead of pace",
                    delta > 0.20 ? Theme.danger : Theme.Accent.amber.color)
        }
        return ("\(points) pts behind pace", Theme.Accent.sage.color)
    }

    /// Day initial for the sparkline axis: S M T W T F S. An explicit table rather than a
    /// `DateFormatter`, so the axis stays in the app's language whatever the system locale is.
    /// `.weekday` is 1 for Sunday, whichever day the week starts on.
    static func dayInitial(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let initials = ["S", "M", "T", "W", "T", "F", "S"]
        guard initials.indices.contains(weekday - 1) else { return "" }
        return initials[weekday - 1]
    }

    /// A reading's age in one short phrase: "4 min", "2 h", "3 d". On stale data the age is what
    /// lets the reader judge — a clock time alone never says it.
    static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return "less than a minute"
        case ..<3600: return "\(Int(seconds / 60)) min"
        case ..<86_400: return "\(Int(seconds / 3600)) h"
        default: return "\(Int(seconds / 86_400)) d"
        }
    }

    /// `minimumFractionDigits = 0`, so "18 M" rather than "18.00 M".
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

}

/// Small `UserDefaults` wrapper: `@AppStorage` is not usable from a class.
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

}
