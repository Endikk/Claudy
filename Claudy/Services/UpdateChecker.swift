import Foundation
import AppKit

/// A release version, `1.5.3` or `v1.5.3`. Compared number by number, so 1.10 comes after 1.9.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// A published release: its version and the page that describes it.
struct Release: Equatable {
    let version: AppVersion
    let pageURL: URL

    static func == (lhs: Release, rhs: Release) -> Bool {
        lhs.version == rhs.version && lhs.pageURL == rhs.pageURL
    }
}

/// Where the latest release comes from.
protocol ReleaseFeed: Sendable {
    func latest() async throws -> Release
}

/// The latest GitHub release of the repository. No token: one call a day is far below the
/// 60 calls per hour GitHub allows without one.
struct GitHubReleaseFeed: ReleaseFeed {
    static let repository = "Endikk/Claudy"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    enum FeedError: Error { case badStatus(Int), unreadable }

    func latest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Claudy", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FeedError.badStatus(status) }
        return try Self.parse(data)
    }

    /// Only the tag and the page are read. The page must be one of this repository's releases:
    /// anything else falls back to the releases list, so the button never opens a foreign URL.
    static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String?
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name) else { throw FeedError.unreadable }

        let prefix = "https://github.com/\(repository)/releases/"
        let page = payload.html_url.flatMap { $0.hasPrefix(prefix) ? URL(string: $0) : nil } ?? releasesPage
        return Release(version: version, pageURL: page)
    }
}

/// Checks at launch, then once a day, and on every manual refresh, whether a newer Claudy is
/// out. Silent on any failure: no network means no dot, never an error.
@MainActor
final class UpdateChecker: ObservableObject {

    /// The newer release, or nil while the installed version is the latest.
    @Published private(set) var available: Release?
    /// True from the moment a release is found until the bubble has been dismissed once.
    @Published private(set) var shouldAnnounce = false
    /// Claudy waves while a newer version is out and Claudy has not been opened since: the
    /// menu bar popover or a click on the widget. Answering the bubble does not count. Not
    /// remembered: every launch, and every switch between the widget and the menu bar, waves again.
    @Published private(set) var isGreeting = false

    /// Where the one-click upgrade stands.
    enum UpgradeState: Equatable {
        case idle, upgrading
        /// Brew failed; the Terminal fallback is offered.
        case failed
        /// Brew succeeded without quitting Claudy: it restarts itself into the new version.
        case restarting
    }
    @Published private(set) var upgradeState: UpgradeState = .idle

    let current: AppVersion?
    /// Nil when Claudy did not come from Homebrew: the update is then a download.
    private let runner: UpgradeRunner?
    /// Off in tests, where terminating would end the test run.
    private let restartsAfterUpgrade: Bool
    private let feed: ReleaseFeed
    private let store: UserDefaults
    /// A simulated release is announced on every launch: it is never remembered.
    private let remembersAnnouncement: Bool
    private let now: () -> Date
    /// The version installed on disk, read after an upgrade. Nil when unreadable.
    private let installedVersion: () -> AppVersion?
    private var timer: Timer?
    private var isChecking = false
    private var lastCheck: Date?

    static let checkInterval: TimeInterval = 24 * 3600
    /// A refresh clicked again and again asks GitHub once a minute at most: it allows 60 calls
    /// an hour without a token.
    static let manualCheckSpacing: TimeInterval = 60
    private static let announcedKey = "claudy.update.announced"

    init(current: AppVersion? = AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
         feed: ReleaseFeed? = nil,
         runner: UpgradeRunner? = nil,
         store: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         installedVersion: @escaping () -> AppVersion? = UpdateChecker.versionOnDisk) {
        self.current = current
        self.store = store
        self.now = now
        if let feed {
            self.feed = feed
            self.runner = runner
            self.installedVersion = installedVersion
            remembersAnnouncement = true
            restartsAfterUpgrade = false
        } else if let simulated = Self.simulatedFeed() {
            self.feed = simulated
            self.runner = Self.simulatedRunner()
            // A simulated upgrade installs nothing: taken at its word.
            self.installedVersion = { nil }
            remembersAnnouncement = false
            // Restarting drops the launch arguments: the relaunched copy sees no update, as a
            // real upgrade would leave it.
            restartsAfterUpgrade = true
        } else {
            self.feed = GitHubReleaseFeed()
            self.runner = runner ?? Self.homebrewRunner()
            self.installedVersion = installedVersion
            remembersAnnouncement = true
            restartsAfterUpgrade = true
        }
    }

    func start() {
        guard timer == nil else { return }
        Task { await check() }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { await self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check() async {
        guard let current, !isChecking else { return }
        isChecking = true
        lastCheck = now()
        let latest = try? await feed.latest()
        isChecking = false
        guard let release = latest else { return }
        guard release.version > current else {
            available = nil
            shouldAnnounce = false
            isGreeting = false
            return
        }
        if available != release { isGreeting = true }
        available = release
        let announced = store.string(forKey: Self.announcedKey).flatMap(AppVersion.init)
        shouldAnnounce = !remembersAnnouncement || announced.map { $0 < release.version } ?? true
        #if DEBUG
        // `-ClaudySimulateAutoUpgrade YES`: press Update by itself, to time the whole upgrade.
        if !remembersAnnouncement, UserDefaults.standard.bool(forKey: "ClaudySimulateAutoUpgrade") { update() }
        #endif
    }

    /// The refresh button: checks again, unless the last check is under a minute old.
    func checkNow() async {
        if let lastCheck, now().timeIntervalSince(lastCheck) < Self.manualCheckSpacing { return }
        await check()
    }

    /// Claudy was opened: stop waving until the next launch or mode switch.
    func acknowledgeGreeting() {
        if isGreeting { isGreeting = false }
    }

    /// The widget moved to the menu bar or back: wave again if the update is still pending.
    func greetAgain() {
        if available != nil { isGreeting = true }
    }

    /// The bubble was seen and closed: it will not come back for this version.
    func markAnnounced() {
        shouldAnnounce = false
        guard remembersAnnouncement, let available else { return }
        store.set(available.version.description, forKey: Self.announcedKey)
    }

    /// True when one click can upgrade in place; otherwise the button downloads.
    var canUpgradeInPlace: Bool { runner != nil }

    /// Installed with Homebrew and brew found: the upgrade goes through brew.
    private static func homebrewRunner() -> UpgradeRunner? {
        let caskroom = ["/opt/homebrew/Caskroom/claudy", "/usr/local/Caskroom/claudy"]
        guard caskroom.contains(where: { FileManager.default.fileExists(atPath: $0) }),
              let brew = BrewUpgradeRunner.findBrew() else { return nil }
        return BrewUpgradeRunner(brew: brew)
    }

    func openReleasePage() {
        guard let available else { return }
        NSWorkspace.shared.open(available.pageURL)
    }

    /// The Update button. With Homebrew, upgrades in the background: brew quits Claudy, replaces
    /// it and the new version opens. Without, opens the release to download it.
    func update() {
        guard let runner else {
            openReleasePage()
            return
        }
        guard upgradeState != .upgrading, upgradeState != .restarting else { return }
        upgradeState = .upgrading
        Task {
            let status = await runner.upgrade()
            guard status == 0, didInstallNewerVersion else {
                upgradeState = .failed
                return
            }
            upgradeState = .restarting
            if restartsAfterUpgrade { Self.restart() }
        }
    }

    /// brew exits 0 without installing anything when its tap has not caught up with the
    /// release: only a newer bundle on disk proves the upgrade. An unreadable one is taken as
    /// success, as before this check.
    private var didInstallNewerVersion: Bool {
        guard let current, let installed = installedVersion() else { return true }
        return installed > current
    }

    /// The bundle's version as it is on disk now. Read from the file: `Bundle` keeps the
    /// Info.plist it loaded at launch.
    nonisolated static func versionOnDisk() -> AppVersion? {
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let version = info["CFBundleShortVersionString"] as? String else { return nil }
        return AppVersion(version)
    }

    /// The fallback after a failed upgrade: the same command, in Terminal, where brew can ask
    /// for a password or show what went wrong.
    func upgradeInTerminal() {
        guard let runner else { return }
        do {
            try runner.openInTerminal()
            upgradeState = .idle
        } catch {
            openReleasePage()
        }
    }

    /// Brew replaced the app without quitting it: reopen the bundle at the same path, now the
    /// new version, as soon as this process has exited.
    private static func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", restartScript, "claudy-restart",
                             String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }

    /// `$1` is this process, `$2` the bundle. Polls until the process is gone, ten seconds at
    /// most, then opens the bundle: opening it earlier would only bring the old one forward.
    static let restartScript = """
        i=0
        while kill -0 "$1" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
        /usr/bin/open "$2"
        """

    /// Debug builds only: `-ClaudySimulateUpdate 1.5.3` on the command line pretends that version
    /// is out, to see the dot and the bubble without publishing anything.
    private static func simulatedFeed() -> ReleaseFeed? {
        #if DEBUG
        guard let value = UserDefaults.standard.string(forKey: "ClaudySimulateUpdate"),
              let version = AppVersion(value) else { return nil }
        return SimulatedFeed(release: Release(version: version, pageURL: GitHubReleaseFeed.releasesPage))
        #else
        return nil
        #endif
    }

    private static func simulatedRunner() -> UpgradeRunner? {
        #if DEBUG
        // `-ClaudySimulateUpgradeWithBrew YES` runs the real brew: with the latest version
        // already installed it changes nothing, and tests the whole chain end to end.
        if UserDefaults.standard.bool(forKey: "ClaudySimulateUpgradeWithBrew"), let brew = BrewUpgradeRunner.findBrew() {
            return BrewUpgradeRunner(brew: brew)
        }
        return SimulatedUpgradeRunner(fails: UserDefaults.standard.bool(forKey: "ClaudySimulateUpgradeFailure"))
        #else
        return nil
        #endif
    }
}

#if DEBUG
private struct SimulatedFeed: ReleaseFeed {
    let release: Release
    func latest() async throws -> Release { release }
}
#endif
