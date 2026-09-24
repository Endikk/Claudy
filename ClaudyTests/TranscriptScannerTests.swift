import XCTest
@testable import Claudy

/// Token counts the history is built from: every response once, at its final size, whatever
/// the folder layout of the machine.
final class TranscriptScannerTests: XCTestCase {

    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudy-scanner-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: - One response, several lines

    func testStreamedResponseCountsItsFinalOutput() async throws {
        let projects = try makeDirectory("projects")
        // Claude Code writes one line per content block; the early ones carry the output count
        // reached so far, only the last one the final count.
        try write(projects, "p/s.jsonl", [
            line(id: "m1", output: 4, cacheWrite: 36_146),
            line(id: "m1", output: 4, cacheWrite: 36_146),
            line(id: "m1", output: 202, cacheWrite: 36_146),
        ])

        let entries = try await scanner(projects).scan()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.tokens, 36_146 + 202)
    }

    func testLineAppendedAfterAReadCompletesTheResponse() async throws {
        let projects = try makeDirectory("projects")
        let file = try write(projects, "p/s.jsonl", [line(id: "m1", output: 4)])
        let scanner = scanner(projects)

        let early = try await scanner.scan()
        try append(file, [line(id: "m1", output: 202)])
        let later = try await scanner.scan()

        XCTAssertEqual(early.first?.tokens, 4, "read mid-response")
        XCTAssertEqual(later.map(\.tokens), [202], "the final count replaces the partial one")
    }

    func testLineStillBeingWrittenIsReadOnceComplete() async throws {
        let projects = try makeDirectory("projects")
        let full = line(id: "m1", output: 7)
        let cut = full.index(full.startIndex, offsetBy: full.count / 2)
        let file = try write(projects, "p/s.jsonl", [line(id: "m0", output: 1)])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(full[..<cut].utf8))
        let scanner = scanner(projects)

        let early = try await scanner.scan()
        try handle.write(contentsOf: Data((full[cut...] + "\n").utf8))
        try handle.close()
        let later = try await scanner.scan()

        XCTAssertEqual(early.map(\.tokens), [1], "half a line is left for the next pass")
        XCTAssertEqual(later.map(\.tokens).sorted(), [1, 7])
    }

    func testFinalLineWithoutNewlineCountsWhenComplete() async throws {
        let projects = try makeDirectory("projects")
        let url = projects.appendingPathComponent("p/s.jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (line(id: "m1", output: 3) + "\n" + line(id: "m2", output: 5)).write(to: url, atomically: true, encoding: .utf8)

        let entries = try await scanner(projects).scan()

        XCTAssertEqual(entries.map(\.tokens).sorted(), [3, 5])
    }

    func testLinesWithoutUsageAreSkippedWhateverTheirSize() async throws {
        let projects = try makeDirectory("projects")
        let prompt = #"{"type":"user","message":{"content":"\#(String(repeating: "x", count: 200_000))"}}"#
        try write(projects, "p/s.jsonl", [prompt, line(id: "m1", output: 4), "", prompt, line(id: "m2", output: 6)])

        let entries = try await scanner(projects).scan()

        XCTAssertEqual(entries.map(\.tokens).sorted(), [4, 6])
    }

    /// Files are read in whatever order the disk lists them, so each case runs with the
    /// complete copy in either file.
    func testResumedSessionCountsSharedResponsesOnceAtTheirFinalSize() async throws {
        for (partial, complete) in [("a", "b"), ("b", "a")] {
            let projects = try makeDirectory("projects-\(partial)")
            try write(projects, "p/\(complete).jsonl", [line(id: "m1", output: 202), line(id: "m2", output: 7)])
            try write(projects, "p/\(partial).jsonl", [line(id: "m1", output: 4), line(id: "m3", output: 9)])

            let entries = try await scanner(projects).scan()

            XCTAssertEqual(entries.map(\.tokens).sorted(), [7, 9, 202], "partial copy in \(partial)")
        }
    }

    func testRewrittenFileDoesNotTakeASharedResponseAwayFromTheOther() async throws {
        for rewritten in ["a", "b"] {
            let projects = try makeDirectory("projects-\(rewritten)")
            try write(projects, "p/a.jsonl", [line(id: "m1", output: 50)])
            try write(projects, "p/b.jsonl", [line(id: "m1", output: 50)])
            let scanner = scanner(projects)
            _ = try await scanner.scan()

            // Replaced by a shorter file: the response only lives in the other one now.
            try write(projects, "p/\(rewritten).jsonl", [line(id: "m9", output: 1)])
            let entries = try await scanner.scan()

            XCTAssertEqual(entries.map(\.tokens).sorted(), [1, 50], "\(rewritten) rewritten")
        }
    }

    // MARK: - Timestamps

    /// Claude Code's form is read without a formatter; the result must be the formatter's, to the
    /// millisecond, and anything unusual must still reach the formatter.
    func testTimestampsMatchTheSystemFormatter() async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let stamps = ["2026-09-24T07:05:12.345Z", "2026-01-01T00:00:00.000Z", "2025-12-31T23:59:59.999Z",
                      "2024-02-29T12:00:00.5Z", "2026-03-01T00:00:00.123456Z", "1999-12-31T23:59:59Z"]

        for stamp in stamps {
            let expected = try XCTUnwrap(formatter.date(from: stamp) ?? plain.date(from: stamp), stamp)
            let result = await timestamp(stamp)
            let parsed = try XCTUnwrap(result, stamp)
            XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001, stamp)
        }
    }

    /// Whatever the fast path turns down is the formatter's to judge, lenient as it is: it reads
    /// 30 February as 2 March, which is what Claudy always did.
    func testUnusualTimestampsGetTheFormattersAnswer() async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let offset = await timestamp("2026-09-24T09:05:12.345+02:00")
        let utc = await timestamp("2026-09-24T07:05:12.345Z")
        XCTAssertEqual(offset?.timeIntervalSince1970 ?? 0, utc?.timeIntervalSince1970 ?? -1, accuracy: 0.001,
                       "an offset goes through the formatter")
        for stamp in ["2026-02-30T07:05:12.345Z", "2026-13-01T07:05:12.345Z", "yesterday", ""] {
            let parsed = await timestamp(stamp)
            XCTAssertEqual(parsed, formatter.date(from: stamp), stamp)
        }
    }

    /// A transcript line is data from disk. However long its fraction of a second, it is read to
    /// the nanosecond: parsed whole, it would overflow, and on Intel Macs `ISO8601DateFormatter`
    /// itself crashes on it (SIGFPE inside ICU), so it never reaches the formatter untrimmed.
    func testOverlongFractionIsReadToTheNanosecond() async {
        let nines = String(repeating: "9", count: 40)

        let expected = await timestamp("2026-09-24T07:05:12.999999999Z")
        let utc = await timestamp("2026-09-24T07:05:12.\(nines)Z")
        let offset = await timestamp("2026-09-24T09:05:12.\(nines)+02:00")

        XCTAssertNotNil(expected)
        XCTAssertEqual(utc, expected)
        XCTAssertEqual(offset?.timeIntervalSince1970 ?? 0, expected?.timeIntervalSince1970 ?? -1, accuracy: 0.001,
                       "an offset goes through the formatter, trimmed first")
    }

    // MARK: - Previous days

    func testPreviousDaysShowTheirFinalTotals() async throws {
        let projects = try makeDirectory("projects")
        let now = Date()
        let threeDaysAgo = now.addingTimeInterval(-3 * 86_400)
        try write(projects, "p/s.jsonl", [
            line(id: "old", output: 10, cacheRead: 1_000, at: threeDaysAgo),
            line(id: "old", output: 90, cacheRead: 1_000, at: threeDaysAgo),
            line(id: "new", output: 5, at: now),
        ])

        let entries = try await scanner(projects).scan()
        let snapshot = UsageAggregator.snapshot(from: entries, account: account, reading: nil, now: now)

        let day = Calendar.current.startOfDay(for: threeDaysAgo)
        XCTAssertEqual(snapshot.history.first { $0.date == day }?.tokens, 1_090)
        XCTAssertEqual(snapshot.history.last?.tokens, 5)
        XCTAssertEqual(snapshot.weekTokens, 1_095)
    }

    // MARK: - Folder layout

    func testSymlinkedProjectsFolderIsRead() async throws {
        let real = try makeDirectory("elsewhere/projects")
        try write(real, "p/s.jsonl", [line(id: "m1", output: 3)])
        let config = try makeDirectory("home/.claude")
        let link = config.appendingPathComponent("projects")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let entries = try await scanner(link).scan()

        XCTAssertEqual(entries.map(\.tokens), [3])
    }

    func testSeveralProjectsFoldersAreMergedWithoutDoubleCounting() async throws {
        let legacy = try makeDirectory("home/.claude/projects")
        let xdg = try makeDirectory("home/.config/claude/projects")
        try write(legacy, "p/a.jsonl", [line(id: "m1", output: 4), line(id: "m2", output: 8)])
        try write(xdg, "p/b.jsonl", [line(id: "m1", output: 40), line(id: "m3", output: 16)])
        let missing = sandbox.appendingPathComponent("nowhere/projects")

        let entries = try await TranscriptScanner(projectsDirectories: { [legacy, xdg, missing] }).scan()

        XCTAssertEqual(entries.map(\.tokens).sorted(), [8, 16, 40])
    }

    func testUnreadableFallbackFolderDoesNotHideThePrimaryOne() async throws {
        let legacy = try makeDirectory("home/.claude/projects")
        let xdg = try makeDirectory("home/.config/claude/projects")
        try write(legacy, "p/a.jsonl", [line(id: "m1", output: 4)])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: xdg.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xdg.path) }

        let entries = try await TranscriptScanner(projectsDirectories: { [legacy, xdg] }).scan()

        XCTAssertEqual(entries.map(\.tokens), [4])
    }

    func testUnreadablePrimaryFolderIsReported() async throws {
        let legacy = try makeDirectory("home/.claude/projects")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: legacy.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: legacy.path) }

        do {
            _ = try await TranscriptScanner(projectsDirectories: { [legacy] }).scan()
            XCTFail("an unreadable transcripts folder must surface, not read as an idle week")
        } catch UsageDataError.projectsUnreadable {
            // Expected.
        }
    }

    func testUnreadableFolderIsReportedWhenItIsTheOnlyOneThatExists() async throws {
        let missing = sandbox.appendingPathComponent("home/.claude/projects")
        let xdg = try makeDirectory("home/.config/claude/projects")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: xdg.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xdg.path) }

        do {
            _ = try await TranscriptScanner(projectsDirectories: { [missing, xdg] }).scan()
            XCTFail("the only transcripts folder is unreadable: that must surface")
        } catch UsageDataError.projectsUnreadable {
            // Expected.
        }
    }

    func testCopiedTranscriptWithoutIdentifiersCountsOnce() async throws {
        let legacy = try makeDirectory("home/.claude/projects")
        let xdg = try makeDirectory("home/.config/claude/projects")
        let lines = [line(id: "a", output: 3, hasIdentifiers: false), line(id: "b", output: 5, hasIdentifiers: false)]
        try write(legacy, "p/s.jsonl", lines)
        try write(xdg, "p/s.jsonl", lines)

        let entries = try await TranscriptScanner(projectsDirectories: { [legacy, xdg] }).scan()

        XCTAssertEqual(entries.map(\.tokens).sorted(), [3, 5])
    }

    func testSameFolderReachedTwiceIsReadOnce() async throws {
        let real = try makeDirectory("home/.claude/projects")
        try write(real, "p/s.jsonl", [line(id: "m1", output: 3, hasIdentifiers: false)])
        let alias = sandbox.appendingPathComponent("home/.config-claude-projects")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)

        let entries = try await TranscriptScanner(projectsDirectories: { [real, alias] }).scan()

        XCTAssertEqual(entries.count, 1, "a response without identifiers is not deduplicated by key")
    }

    func testDefaultConfigurationReadsBothKnownFolders() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

        let folders = ClaudeHome.projectsDirectories(custom: nil, home: home, environment: [:])

        XCTAssertEqual(folders.map(\.path), ["/Users/someone/.claude/projects",
                                            "/Users/someone/.config/claude/projects"])
    }

    func testXDGConfigHomeIsHonoured() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

        let folders = ClaudeHome.projectsDirectories(custom: nil, home: home,
                                                     environment: ["XDG_CONFIG_HOME": "/Volumes/cfg"])

        XCTAssertEqual(folders.last?.path, "/Volumes/cfg/claude/projects")
    }

    func testCustomConfigurationStandsAlone() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let custom = URL(fileURLWithPath: "/Volumes/work/claude", isDirectory: true)

        let folders = ClaudeHome.projectsDirectories(custom: custom, home: home,
                                                     environment: ["XDG_CONFIG_HOME": "/Volumes/cfg"])

        XCTAssertEqual(folders.map(\.path), ["/Volumes/work/claude/projects"])
    }

    // MARK: - Fixtures

    private let account = Account(name: "", email: "", plan: "", organization: "", isAdmin: false)

    private func timestamp(_ stamp: String) async -> Date? {
        await TranscriptScanner(projectsDirectories: { [] }).timestamp(stamp)
    }

    private func scanner(_ projects: URL) -> TranscriptScanner {
        TranscriptScanner(projectsDirectories: { [projects] })
    }

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = sandbox.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ projects: URL, _ relative: String, _ lines: [String]) throws -> URL {
        let url = projects.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func append(_ url: URL, _ lines: [String]) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private func line(id: String, output: Int, cacheWrite: Int = 0, cacheRead: Int = 0,
                      at date: Date = Date().addingTimeInterval(-600),
                      hasIdentifiers: Bool = true) -> String {
        var message: [String: Any] = [
            "model": "claude-opus-5",
            "usage": ["input_tokens": 0, "output_tokens": output,
                      "cache_creation_input_tokens": cacheWrite, "cache_read_input_tokens": cacheRead],
        ]
        var object: [String: Any] = [
            "type": "assistant", "timestamp": ISO8601DateFormatter().string(from: date),
            "cwd": sandbox.path, "sessionId": "s", "isSidechain": false,
        ]
        if hasIdentifiers {
            message["id"] = id
            object["requestId"] = "req-\(id)"
        }
        object["message"] = message
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
