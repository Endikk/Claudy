import XCTest
@testable import Claudy

/// Which model and which project the week's usage lands on.
final class UsageAttributionTests: XCTestCase {

    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudy-tests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: - Model names and prices

    func testDisplayDropsReleaseDates() {
        XCTAssertEqual(ModelName.display("claude-opus-5"), "Opus 5")
        XCTAssertEqual(ModelName.display("claude-haiku-4-5-20251001"), "Haiku 4.5")
        XCTAssertEqual(ModelName.display("claude-3-5-haiku-20241022"), "Haiku 3.5")
    }

    func testInputPriceFollowsFamilyAndGeneration() {
        XCTAssertEqual(ModelName.inputPrice("claude-opus-5"), 5)
        XCTAssertEqual(ModelName.inputPrice("claude-opus-4-1-20250805"), 15)
        XCTAssertEqual(ModelName.inputPrice("claude-sonnet-5"), 2)
        XCTAssertEqual(ModelName.inputPrice("claude-sonnet-4-6"), 3)
        XCTAssertEqual(ModelName.inputPrice("claude-haiku-4-5-20251001"), 1)
        XCTAssertEqual(ModelName.inputPrice("claude-3-5-haiku-20241022"), 0.8)
        XCTAssertEqual(ModelName.inputPrice("claude-fable-5-1"), 10)
        XCTAssertEqual(ModelName.inputPrice("claude-unknown-9"), 3)
    }

    // MARK: - Project resolution

    func testSubdirectoryResolvesToRepositoryRoot() throws {
        let repo = try makeRepository("Jarvis")
        let nested = try makeDirectory("Jarvis/App/Sources")
        var resolver = ProjectResolver(home: sandbox)

        XCTAssertEqual(resolver.repositoryRoot(of: nested.path), repo.path)
        XCTAssertEqual(resolver.repositoryRoot(of: repo.path), repo.path)
    }

    func testWorktreeResolvesToMainCheckout() throws {
        let repo = try makeRepository("Surikat")
        let worktree = try makeDirectory("Surikat/.claude/worktrees/feature")
        try "gitdir: \(repo.path)/.git/worktrees/feature\n"
            .write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        var resolver = ProjectResolver(home: sandbox)

        XCTAssertEqual(resolver.repositoryRoot(of: worktree.path), repo.path)
    }

    func testSubmoduleStaysItsOwnProject() throws {
        _ = try makeRepository("Parent")
        let module = try makeDirectory("Parent/vendor/lib")
        try "gitdir: ../../.git/modules/lib\n"
            .write(to: module.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        var resolver = ProjectResolver(home: sandbox)

        XCTAssertEqual(resolver.repositoryRoot(of: module.path), module.path)
    }

    func testFolderOutsideRepositoryHasNoRoot() throws {
        let plain = try makeDirectory("scratchpad")
        var resolver = ProjectResolver(home: sandbox)

        XCTAssertNil(resolver.repositoryRoot(of: plain.path))
        XCTAssertNil(resolver.repositoryRoot(of: sandbox.appendingPathComponent("deleted/tmp").path))
        XCTAssertNil(resolver.repositoryRoot(of: ""))
    }

    // MARK: - Scanner

    func testScannerReadsSubagentTranscriptsAndGroupsByRepository() async throws {
        let repo = try makeRepository("Jarvis")
        let app = try makeDirectory("Jarvis/App")
        let scratch = try makeDirectory("scratchpad")
        let projects = try makeDirectory("projects")
        let session = try makeDirectory("projects/-Jarvis")

        try writeLines(session.appendingPathComponent("s1.jsonl"), [
            line(id: "m1", cwd: repo.path, session: "s1", model: "claude-opus-5", output: 100),
            line(id: "m1", cwd: repo.path, session: "s1", model: "claude-opus-5", output: 100),
            line(id: "m2", cwd: scratch.path, session: "s1", model: "claude-opus-5", output: 10),
        ])
        let subagents = try makeDirectory("projects/-Jarvis/s1/subagents/workflows/wf_1")
        try writeLines(subagents.appendingPathComponent("agent-a.jsonl"), [
            line(id: "m3", cwd: app.path, session: "s1", model: "claude-haiku-4-5-20251001",
                 output: 50, sidechain: true),
        ])

        let entries = try await TranscriptScanner(projectsDirectories: { [projects] }).scan()

        XCTAssertEqual(entries.count, 3, "duplicate content-block line counted once, subagent read")
        XCTAssertEqual(Set(entries.map(\.project)), [repo.path],
                       "subfolder and scratchpad both belong to the session's repository")
        XCTAssertTrue(entries.contains { $0.isSidechain && $0.model.contains("haiku") })
    }

    func testWeightPricesCacheReadsAtATenth() async throws {
        let projects = try makeDirectory("projects")
        let session = try makeDirectory("projects/-p")
        try writeLines(session.appendingPathComponent("s.jsonl"), [
            line(id: "a", cwd: sandbox.path, session: "s", model: "claude-opus-5", output: 0,
                 cacheRead: 1_000_000),
            line(id: "b", cwd: sandbox.path, session: "s", model: "claude-opus-5", output: 1_000_000),
        ])

        let entries = try await TranscriptScanner(projectsDirectories: { [projects] }).scan()

        XCTAssertEqual(entries.first { $0.dedupKey?.hasPrefix("a") == true }?.weight ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(entries.first { $0.dedupKey?.hasPrefix("b") == true }?.weight ?? 0, 25, accuracy: 1e-9)
    }

    // MARK: - Aggregation

    func testSplitsRankByWeightAndMergeSnapshots() {
        let now = Date()
        let entries = [
            entry("claude-haiku-4-5-20251001", tokens: 900, weight: 1, project: "/w/observer", now: now),
            entry("claude-haiku-4-5", tokens: 100, weight: 1, project: "/w/observer", now: now),
            entry("claude-opus-5", tokens: 100, weight: 8, project: "/w/Surikat", now: now),
        ]

        let snapshot = UsageAggregator.snapshot(from: entries, account: account, reading: nil, now: now)

        XCTAssertEqual(snapshot.models.map(\.name), ["Opus 5", "Haiku 4.5"])
        XCTAssertEqual(snapshot.models[0].share, 0.8, accuracy: 1e-9)
        XCTAssertEqual(snapshot.models[1].tokens, 1000)
        XCTAssertEqual(snapshot.projects.map(\.name), ["Surikat", "observer"])
        XCTAssertEqual(snapshot.activeModel, "Opus 5", "fewer tokens, but they weigh more")
    }

    func testLocalActivityKeepsTheSessionRunningWithoutAQuota() {
        let now = Date()
        let entries = [entry("claude-opus-5", tokens: 100, weight: 1, project: "/w/Claudy", now: now)]

        let snapshot = UsageAggregator.snapshot(from: entries, account: account, reading: nil, now: now)

        XCTAssertFalse(snapshot.session.isMeasured)
        XCTAssertFalse(snapshot.session.isActive, "no quota, so no countdown to show")
        XCTAssertTrue(snapshot.session.isRunning, "Claude Code worked an hour ago: Claudy must type")
    }

    func testLocalActivityKeepsTheSessionRunningWhenTheAccountHasNoWindow() {
        let now = Date()
        let entries = [entry("claude-opus-5", tokens: 100, weight: 1, project: "/w/Claudy", now: now)]
        // Claude Code bills another account (an API key), so the one Claudy reads has no window.
        let reading = QuotaReading(session: QuotaWindow(percent: 0, resetsAt: nil),
                                   weekly: nil, scoped: nil, source: .api)

        let snapshot = UsageAggregator.snapshot(from: entries, account: account, reading: reading, now: now)

        XCTAssertTrue(snapshot.session.isMeasured)
        XCTAssertFalse(snapshot.session.isActive, "the account runs no window: no countdown")
        XCTAssertTrue(snapshot.session.isRunning, "Claude Code worked an hour ago: Claudy must type")
    }

    func testAccountWindowKeepsTheSessionRunningWithoutLocalActivity() {
        let now = Date()
        let reading = QuotaReading(session: QuotaWindow(percent: 0.4, resetsAt: now.addingTimeInterval(3600)),
                                   weekly: nil, scoped: nil, source: .api)

        let snapshot = UsageAggregator.snapshot(from: [], account: account, reading: reading, now: now)

        XCTAssertTrue(snapshot.session.isActive)
        XCTAssertTrue(snapshot.session.isRunning, "work on another machine still counts")
    }

    func testNoActivityAndNoQuotaLeavesTheSessionIdle() {
        let now = Date()

        let snapshot = UsageAggregator.snapshot(from: [], account: account, reading: nil, now: now)

        XCTAssertFalse(snapshot.session.isRunning)
    }

    func testHomonymProjectsShowTheirParent() {
        let names = UsageAggregator.displayNames(for: ["/work/api", "/personal/api", "/work/site"])

        XCTAssertEqual(names["/work/api"], "work/api")
        XCTAssertEqual(names["/personal/api"], "personal/api")
        XCTAssertEqual(names["/work/site"], "site")
    }

    // MARK: - Fixtures

    private let account = Account(name: "", email: "", plan: "", organization: "", isAdmin: false)

    private func entry(_ model: String, tokens: Int, weight: Double, project: String, now: Date) -> TranscriptEntry {
        TranscriptEntry(date: now.addingTimeInterval(-3600), model: model, tokens: tokens, weight: weight,
                        cwd: project, project: project, sessionID: "s", isSidechain: false,
                        dedupKey: UUID().uuidString)
    }

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = sandbox.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRepository(_ relative: String) throws -> URL {
        let url = try makeDirectory(relative)
        try FileManager.default.createDirectory(at: url.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)
        return url
    }

    private func writeLines(_ url: URL, _ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func line(id: String, cwd: String, session: String, model: String, output: Int,
                      cacheRead: Int = 0, sidechain: Bool = false) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))
        let object: [String: Any] = [
            "type": "assistant", "timestamp": stamp, "cwd": cwd, "sessionId": session,
            "isSidechain": sidechain, "requestId": "req-\(id)",
            "message": [
                "id": id, "model": model,
                "usage": ["input_tokens": 0, "output_tokens": output,
                          "cache_creation_input_tokens": 0, "cache_read_input_tokens": cacheRead],
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
