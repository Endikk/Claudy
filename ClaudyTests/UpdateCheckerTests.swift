import SwiftUI
import XCTest
@testable import Claudy

private struct StubFeed: ReleaseFeed {
    let result: Result<Release, Error>
    func latest() async throws -> Release { try result.get() }
}

private struct Offline: Error {}

/// A feed whose latest release can change between checks, counting how often it is asked.
private final class LiveFeed: ReleaseFeed, @unchecked Sendable {
    var latestRelease: Release
    private(set) var calls = 0
    init(_ release: Release) { latestRelease = release }
    func latest() async throws -> Release {
        calls += 1
        return latestRelease
    }
}

private final class StubRunner: UpgradeRunner, @unchecked Sendable {
    let status: Int32
    private(set) var terminalOpened = false
    init(status: Int32) { self.status = status }
    func upgrade() async -> Int32 { status }
    func openInTerminal() throws { terminalOpened = true }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {

    private var store: UserDefaults!
    private let suite = "claudy.tests.updates"

    override func setUp() async throws {
        store = UserDefaults(suiteName: suite)
        store.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        store.removePersistentDomain(forName: suite)
    }

    private func release(_ version: String) -> Release {
        Release(version: AppVersion(version)!, pageURL: URL(string: "https://github.com/Endikk/Claudy/releases/tag/v\(version)")!)
    }

    private func checker(current: String, latest: Result<Release, Error>,
                         runner: UpgradeRunner? = nil,
                         installed: String? = nil) -> UpdateChecker {
        UpdateChecker(current: AppVersion(current), feed: StubFeed(result: latest), runner: runner, store: store,
                      installedVersion: { installed.flatMap(AppVersion.init) })
    }

    /// Lets the upgrade task started by `update()` run to its end.
    private func settle(_ updates: UpdateChecker) async {
        for _ in 0..<50 where updates.upgradeState == .upgrading {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Versions

    func testVersionParsesWithOrWithoutPrefix() {
        XCTAssertEqual(AppVersion("v1.5.3")?.parts, [1, 5, 3])
        XCTAssertEqual(AppVersion("1.5.3")?.parts, [1, 5, 3])
        XCTAssertEqual(AppVersion(" 2.0 ")?.parts, [2, 0])
    }

    func testVersionRejectsGarbage() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.5.3-beta"))
        XCTAssertNil(AppVersion("1.-5"))
    }

    func testVersionsCompareNumberByNumber() {
        XCTAssertLessThan(AppVersion("1.9")!, AppVersion("1.10")!)
        XCTAssertLessThan(AppVersion("1.5.2")!, AppVersion("1.5.3")!)
        XCTAssertLessThan(AppVersion("1.5.9")!, AppVersion("1.6")!)
        XCTAssertEqual(AppVersion("1.5")!, AppVersion("1.5.0")!)
        XCTAssertFalse(AppVersion("1.5.3")! < AppVersion("1.5.3")!)
    }

    // MARK: - GitHub payload

    func testParseReadsTagAndPage() throws {
        let json = #"{"tag_name":"v1.5.3","html_url":"https://github.com/Endikk/Claudy/releases/tag/v1.5.3","draft":false,"prerelease":false}"#
        let release = try GitHubReleaseFeed.parse(Data(json.utf8))
        XCTAssertEqual(release.version.description, "1.5.3")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/Endikk/Claudy/releases/tag/v1.5.3")
    }

    func testParseNeverKeepsAForeignPage() throws {
        let json = #"{"tag_name":"v1.5.3","html_url":"https://evil.example/releases/tag/v1.5.3"}"#
        let release = try GitHubReleaseFeed.parse(Data(json.utf8))
        XCTAssertEqual(release.pageURL, GitHubReleaseFeed.releasesPage)
    }

    func testParseRejectsPrereleasesAndUnreadableTags() {
        let prerelease = #"{"tag_name":"v2.0.0","prerelease":true}"#
        let badTag = #"{"tag_name":"nightly"}"#
        XCTAssertThrowsError(try GitHubReleaseFeed.parse(Data(prerelease.utf8)))
        XCTAssertThrowsError(try GitHubReleaseFeed.parse(Data(badTag.utf8)))
        XCTAssertThrowsError(try GitHubReleaseFeed.parse(Data("not json".utf8)))
    }

    // MARK: - Checker

    func testNewerReleaseIsAvailableAndAnnounced() async {
        let updates = checker(current: "1.5.2", latest: .success(release("1.5.3")))
        await updates.check()
        XCTAssertEqual(updates.available?.version.description, "1.5.3")
        XCTAssertTrue(updates.shouldAnnounce)
    }

    func testSameOrOlderReleaseShowsNothing() async {
        for latest in ["1.5.2", "1.5.1"] {
            let updates = checker(current: "1.5.2", latest: .success(release(latest)))
            await updates.check()
            XCTAssertNil(updates.available, latest)
            XCTAssertFalse(updates.shouldAnnounce, latest)
        }
    }

    func testOfflineStaysSilent() async {
        let updates = checker(current: "1.5.2", latest: .failure(Offline()))
        await updates.check()
        XCTAssertNil(updates.available)
        XCTAssertFalse(updates.shouldAnnounce)
    }

    func testBubbleIsAnnouncedOncePerVersion() async {
        let first = checker(current: "1.5.2", latest: .success(release("1.5.3")))
        await first.check()
        first.markAnnounced()
        XCTAssertFalse(first.shouldAnnounce)

        // Next launch, same release: the dot stays, the bubble does not come back.
        let again = checker(current: "1.5.2", latest: .success(release("1.5.3")))
        await again.check()
        XCTAssertNotNil(again.available)
        XCTAssertFalse(again.shouldAnnounce)

        // A later release is announced again.
        let later = checker(current: "1.5.2", latest: .success(release("1.5.4")))
        await later.check()
        XCTAssertTrue(later.shouldAnnounce)
    }

    // MARK: - Manual refresh

    func testRefreshFindsAReleasePublishedSinceLaunch() async {
        let feed = LiveFeed(release("1.5.2"))
        var clock = Date(timeIntervalSince1970: 0)
        let updates = UpdateChecker(current: AppVersion("1.5.2"), feed: feed, store: store, now: { clock })
        await updates.check()
        XCTAssertNil(updates.available)

        feed.latestRelease = release("1.5.3")
        clock += UpdateChecker.manualCheckSpacing
        await updates.checkNow()

        XCTAssertEqual(updates.available?.version.description, "1.5.3")
    }

    func testRefreshBurstAsksGitHubOnce() async {
        let feed = LiveFeed(release("1.5.2"))
        var clock = Date(timeIntervalSince1970: 0)
        let updates = UpdateChecker(current: AppVersion("1.5.2"), feed: feed, store: store, now: { clock })
        await updates.check()

        for _ in 0..<5 { await updates.checkNow() }
        clock += UpdateChecker.manualCheckSpacing - 1
        await updates.checkNow()
        XCTAssertEqual(feed.calls, 1)

        clock += 1
        await updates.checkNow()
        XCTAssertEqual(feed.calls, 2)
    }

    // MARK: - Greeting

    func testClaudyWavesUntilOpenedAndAgainAfterAModeSwitch() async {
        let updates = checker(current: "1.5.2", latest: .success(release("1.5.3")))
        await updates.check()
        XCTAssertTrue(updates.isGreeting)

        updates.acknowledgeGreeting()
        XCTAssertFalse(updates.isGreeting)

        // A daily check finding the same release does not wave again on its own.
        await updates.check()
        XCTAssertFalse(updates.isGreeting)

        updates.greetAgain()
        XCTAssertTrue(updates.isGreeting)

        // Closing the bubble is not opening Claudy: the wave goes on.
        updates.markAnnounced()
        XCTAssertTrue(updates.isGreeting)
    }

    func testNoGreetingWithoutAnUpdate() async {
        let updates = checker(current: "1.5.3", latest: .success(release("1.5.3")))
        await updates.check()
        updates.greetAgain()
        XCTAssertFalse(updates.isGreeting)
    }

    func testCroppedWaveFitsTheMascotSlot() {
        // One point per pixel must not exceed the typing mascot by more than a point.
        XCTAssertLessThanOrEqual(ClaudyWave.contentRows.count, 28)
        XCTAssertLessThanOrEqual(ClaudyWave.columns, 29)
    }

    // MARK: - One-click upgrade

    func testSuccessfulUpgradeRestarts() async {
        let updates = checker(current: "1.5.2", latest: .success(release("1.5.3")), runner: StubRunner(status: 0),
                              installed: "1.5.3")
        await updates.check()
        XCTAssertTrue(updates.canUpgradeInPlace)

        updates.update()
        XCTAssertEqual(updates.upgradeState, .upgrading)
        await settle(updates)
        XCTAssertEqual(updates.upgradeState, .restarting)
    }

    /// brew exits 0 without installing anything when its tap has not caught up with the release.
    /// Restarting would bring the same version back, dot included.
    func testUpgradeThatInstalledNothingOffersTerminal() async {
        let updates = checker(current: "1.5.2", latest: .success(release("1.5.3")), runner: StubRunner(status: 0),
                              installed: "1.5.2")
        await updates.check()

        updates.update()
        await settle(updates)
        XCTAssertEqual(updates.upgradeState, .failed)
    }

    func testVersionOnDiskReadsTheBundlesInfoPlist() {
        let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertNotNil(bundled)
        XCTAssertEqual(UpdateChecker.versionOnDisk()?.description, bundled.flatMap(AppVersion.init)?.description)
    }

    func testFailedUpgradeOffersTerminal() async {
        let runner = StubRunner(status: 1)
        let updates = checker(current: "1.5.2", latest: .success(release("1.5.3")), runner: runner)
        await updates.check()

        updates.update()
        await settle(updates)
        XCTAssertEqual(updates.upgradeState, .failed)

        updates.upgradeInTerminal()
        XCTAssertTrue(runner.terminalOpened)
        XCTAssertEqual(updates.upgradeState, .idle)
    }

    /// brew upgrades the copy its Caskroom links to. Any other copy (a build from source, a copy
    /// dragged elsewhere) would watch brew upgrade another app, then restart into itself.
    func testOnlyTheCopyBrewInstalledUpgradesThroughBrew() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudy-caskroom-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let installed = sandbox.appendingPathComponent("Applications/Claudy.app", isDirectory: true)
        let elsewhere = sandbox.appendingPathComponent("build/Claudy.app", isDirectory: true)
        let caskroom = sandbox.appendingPathComponent("Caskroom/claudy", isDirectory: true)
        for directory in [installed, elsewhere, caskroom.appendingPathComponent("1.5.4")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: caskroom.appendingPathComponent("1.5.4/Claudy.app"),
                                                   withDestinationURL: installed)
        let missing = sandbox.appendingPathComponent("nowhere/claudy", isDirectory: true)

        XCTAssertTrue(UpdateChecker.isManagedByHomebrew(installed, caskrooms: [missing, caskroom]))
        XCTAssertFalse(UpdateChecker.isManagedByHomebrew(elsewhere, caskrooms: [missing, caskroom]))
        XCTAssertFalse(UpdateChecker.isManagedByHomebrew(installed, caskrooms: [missing]))
    }

    func testWithoutHomebrewTheButtonDownloads() async {
        let updates = checker(current: "1.5.2", latest: .success(release("1.5.3")), runner: nil)
        await updates.check()
        XCTAssertFalse(updates.canUpgradeInPlace)
    }

    func testUpgradeScriptRunsTheCaskUpgradeAndReopensClaudy() throws {
        let script = BrewUpgradeRunner.script(brew: "/opt/homebrew/bin/brew", claudy: 4242)
        XCTAssertTrue(script.contains(#""/opt/homebrew/bin/brew" upgrade --cask claudy"#))
        // brew refreshes its taps once a day at most on its own: a release out since then would
        // read as "the latest version is already installed", with exit status 0.
        let update = try XCTUnwrap(script.range(of: #""/opt/homebrew/bin/brew" update --quiet"#))
        let upgrade = try XCTUnwrap(script.range(of: "upgrade --cask claudy"))
        XCTAssertLessThan(update.lowerBound, upgrade.lowerBound)
        XCTAssertTrue(script.contains("open -b com.claudy.Claudy"))
        // Reopen only on success, only if brew quit Claudy, and hand brew's status back.
        XCTAssertTrue(script.contains(#"[ "$status" -eq 0 ] && ! kill -0 4242"#))
        XCTAssertTrue(script.contains(#"exit "$status""#))
    }

    /// The restart must wait for the old process to exit, then open the bundle straight away.
    func testRestartScriptWaitsForTheOldProcessOnly() throws {
        let old = Process()
        old.executableURL = URL(fileURLWithPath: "/bin/sleep")
        old.arguments = ["0.5"]
        try old.run()

        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/bin/sh")
        restart.arguments = ["-c", UpdateChecker.restartScript, "claudy-restart",
                             String(old.processIdentifier), "/nonexistent/Claudy.app"]
        restart.standardError = FileHandle.nullDevice
        let start = Date()
        try restart.run()
        restart.waitUntilExit()
        let waited = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(waited, 0.4, "opened before the old process exited")
        XCTAssertLessThan(waited, 1.5, "kept waiting after the old process exited")
    }

    // MARK: - Wave frames

    func testWaveFramesHaveTheGridSize() {
        for (index, frame) in ClaudyWave.frames.enumerated() {
            XCTAssertEqual(frame.count, ClaudyWave.rows, "frame \(index) row count")
            for line in frame {
                XCTAssertEqual(line.count, ClaudyWave.columns, "frame \(index) row width")
            }
        }
    }

    func testWaveSequencePointsAtRealFrames() {
        XCTAssertFalse(ClaudyWave.sequence.isEmpty)
        for step in ClaudyWave.sequence {
            XCTAssertTrue(ClaudyWave.frames.indices.contains(step.frame))
            XCTAssertGreaterThan(step.ms, 0)
        }
        XCTAssertTrue(ClaudyWave.frames.indices.contains(ClaudyWave.stillFrame))
    }

    func testEveryWaveInkHasAColour() {
        let inks = Set(ClaudyWave.frames.joined().joined()).subtracting([Character(".")])
        for ink in inks {
            XCTAssertFalse(ClaudyTyping.colors(for: ink, tint: .red).isEmpty, "ink \(ink) has no colour")
        }
    }

    /// The menu bar percentage sits right of the icon: waving must not change the icon's width.
    func testWaveIconIsAsWideAsTheTypingIcon() {
        let typing = ClaudyTyping.image(.resting, tint: .red, cell: 0.5)
        for index in ClaudyWave.frames.indices {
            XCTAssertEqual(ClaudyTyping.waveImage(index, tint: .red, cell: 0.5).size.width, typing.size.width)
        }
    }

    func testWaveFrameIndexFollowsTheSequenceAndLoops() {
        XCTAssertEqual(ClaudyWave.frameIndex(elapsed: 0), ClaudyWave.sequence[0].frame)
        let firstStep = Double(ClaudyWave.sequence[0].ms) / 1000
        XCTAssertEqual(ClaudyWave.frameIndex(elapsed: firstStep + 0.001), ClaudyWave.sequence[1].frame)
        XCTAssertEqual(ClaudyWave.frameIndex(elapsed: ClaudyWave.loopDuration + 0.01), ClaudyWave.sequence[0].frame)
    }
}
