import XCTest
@testable import Claudy

/// A source with no history of its own, like the stubs the other tests use.
private struct StubSource: UsageDataSource {
    func fetch() async throws -> UsageSnapshot { .placeholder }
}

/// A history read that only ends when the test says so, and counts how many were started.
private actor HeldScanner: TranscriptSource {
    private let entries: [TranscriptEntry]
    private var isReleased = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var passes = 0

    init(entries: [TranscriptEntry]) {
        self.entries = entries
    }

    func scan() async throws -> [TranscriptEntry] {
        passes += 1
        if !isReleased { await withCheckedContinuation { waiting.append($0) } }
        return entries
    }

    func release() {
        isReleased = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// The CSV export: one line per local hour, project and model over the last seven days, in a
/// form a spreadsheet opens without surprises whatever the folder names hold.
final class UsageExportTests: XCTestCase {

    private static let header =
        "hour,project,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,list_price_usd"

    // MARK: - Lines

    func testResponsesOfOneHourProjectAndModelShareALine() {
        let entries = [
            entry(at: "2026-11-10T08:05:00Z", input: 100, output: 10, cacheRead: 1_000, cacheWrite: 50, weight: 1.25),
            entry(at: "2026-11-10T08:55:00Z", input: 20, output: 5, cacheRead: 300, cacheWrite: 7, weight: 0.5),
            entry(at: "2026-11-10T08:30:00Z", model: "claude-sonnet-5-5", input: 1, output: 2, cacheRead: 3,
                  cacheWrite: 4, weight: 0.01),
            entry(at: "2026-11-10T09:10:00Z", input: 9, output: 8, cacheRead: 7, cacheWrite: 6, weight: 0.2),
        ]

        let csv = UsageExport.csv(from: entries, now: now, calendar: paris)

        XCTAssertEqual(csv, """
        \(Self.header)
        2026-11-10T09:00,Claudy,claude-opus-5-5,120,15,1300,57,1.7500
        2026-11-10T09:00,Claudy,claude-sonnet-5-5,1,2,3,4,0.0100
        2026-11-10T10:00,Claudy,claude-opus-5-5,9,8,7,6,0.2000

        """)
    }

    func testHourIsReadInTheCalendarsTimeZone() {
        let entries = [entry(at: "2026-11-10T08:05:00Z", output: 1)]

        let inParis = UsageExport.rows(from: entries, now: now, calendar: paris)
        let inTokyo = UsageExport.rows(from: entries, now: now, calendar: calendar("Asia/Tokyo"))
        let inKathmandu = UsageExport.rows(from: entries, now: now, calendar: calendar("Asia/Kathmandu"))

        XCTAssertEqual(inParis.map(\.hour), ["2026-11-10T09:00"])
        XCTAssertEqual(inTokyo.map(\.hour), ["2026-11-10T17:00"])
        XCTAssertEqual(inKathmandu.map(\.hour), ["2026-11-10T13:00"], "08:05 UTC is 13:50 at UTC+5:45")
    }

    /// A user on the Buddhist or Japanese calendar still gets 2026: a script reading the file
    /// must not depend on the settings of the Mac it came from.
    func testDatesAreGregorianWhateverTheUsersCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Europe/Paris")!

        let rows = UsageExport.rows(from: [entry(at: "2026-11-10T08:05:00Z", output: 1)], now: now, calendar: buddhist)

        XCTAssertEqual(rows.map(\.hour), ["2026-11-10T09:00"])
        XCTAssertEqual(UsageExport.fileName(now: now, calendar: buddhist), "claudy-usage-2026-11-10.csv")
    }

    func testOnlyTheLastSevenDaysAreExported() {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let entries = [
            entry(at: weekAgo.addingTimeInterval(-1), output: 1),
            entry(at: weekAgo, output: 2),
            entry(at: now.addingTimeInterval(-60), output: 3),
        ]

        let rows = UsageExport.rows(from: entries, now: now, calendar: paris)

        XCTAssertEqual(rows.map(\.outputTokens), [2, 3], "a response seven days old to the second is kept")
    }

    func testLinesAreSortedByHourThenProjectThenModel() {
        let entries = [
            entry(at: "2026-11-10T09:10:00Z", project: "/w/EVAN", model: "claude-opus-5-5", output: 1),
            entry(at: "2026-11-10T08:10:00Z", project: "/w/EVAN", model: "claude-sonnet-5-5", output: 1),
            entry(at: "2026-11-10T08:20:00Z", project: "/w/Claudy", model: "claude-sonnet-5-5", output: 1),
            entry(at: "2026-11-10T08:30:00Z", project: "/w/EVAN", model: "claude-haiku-5", output: 1),
            entry(at: "2026-11-10T08:40:00Z", project: "/w/Claudy", model: "claude-opus-5-5", output: 1),
            entry(at: "2026-11-09T23:40:00Z", project: "/w/Zed", model: "claude-opus-5-5", output: 1),
        ]

        let rows = UsageExport.rows(from: entries, now: now, calendar: paris)

        XCTAssertEqual(rows.map { "\($0.hour) \($0.project) \($0.model)" }, [
            "2026-11-10T00:00 Zed claude-opus-5-5",
            "2026-11-10T09:00 Claudy claude-opus-5-5",
            "2026-11-10T09:00 Claudy claude-sonnet-5-5",
            "2026-11-10T09:00 EVAN claude-haiku-5",
            "2026-11-10T09:00 EVAN claude-sonnet-5-5",
            "2026-11-10T10:00 EVAN claude-opus-5-5",
        ])
    }

    // MARK: - Project names

    /// Two folders named alike are told apart even when they never share an hour: the names hold
    /// across the whole file, so a pivot table does not merge them.
    func testCollidingFolderNamesArePrefixedByTheirParent() {
        let entries = [
            entry(at: "2026-11-10T08:10:00Z", project: "/Users/me/work/api", output: 1),
            entry(at: "2026-11-09T08:10:00Z", project: "/Users/me/personal/api", output: 1),
            entry(at: "2026-11-10T08:20:00Z", project: "/Users/me/Claudy", output: 1),
        ]

        let rows = UsageExport.rows(from: entries, now: now, calendar: paris)

        XCTAssertEqual(rows.map(\.project), ["personal/api", "Claudy", "work/api"])
    }

    /// A project the export leaves out, older than the week, does not rename the ones it keeps.
    func testOnlyExportedProjectsCountAsCollisions() {
        let entries = [
            entry(at: "2026-11-10T08:10:00Z", project: "/Users/me/work/api", output: 1),
            entry(at: "2026-11-01T08:10:00Z", project: "/Users/me/personal/api", output: 1),
        ]

        let rows = UsageExport.rows(from: entries, now: now, calendar: paris)

        XCTAssertEqual(rows.map(\.project), ["api"])
    }

    // MARK: - Escaping

    func testFieldsThatWouldBreakALineAreQuoted() {
        XCTAssertEqual(UsageExport.escape("Claudy"), "Claudy")
        XCTAssertEqual(UsageExport.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(UsageExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(UsageExport.escape("two\nlines"), "\"two\nlines\"")
        XCTAssertEqual(UsageExport.escape("carriage\rreturn"), "\"carriage\rreturn\"")
        XCTAssertEqual(UsageExport.escape("windows\r\nline"), "\"windows\r\nline\"",
                       "CR LF is a single Character in Swift, and still a line break")
    }

    /// Folder names are the user's: one named `=HYPERLINK(...)` must open as text, not run.
    func testFieldsThatASpreadsheetWouldRunAsAFormulaAreDefused() {
        XCTAssertEqual(UsageExport.escape("=SUM(A1:A9)"), "'=SUM(A1:A9)")
        XCTAssertEqual(UsageExport.escape("+33"), "'+33")
        XCTAssertEqual(UsageExport.escape("-rf"), "'-rf")
        XCTAssertEqual(UsageExport.escape("@cmd"), "'@cmd")
        XCTAssertEqual(UsageExport.escape("\tindent"), "'\tindent")
        XCTAssertEqual(UsageExport.escape("\rback"), "\"'\rback\"")
        XCTAssertEqual(UsageExport.escape("\r\nback"), "\"'\r\nback\"")
        XCTAssertEqual(UsageExport.escape("=1,2"), "\"'=1,2\"")
        XCTAssertEqual(UsageExport.escape("a=b"), "a=b", "only a leading sign starts a formula")
    }

    func testProjectNamesGoThroughTheEscaping() {
        let entries = [entry(at: "2026-11-10T08:10:00Z", project: "/w/=HYPERLINK(\"x\",\"y\")", output: 1)]

        let csv = UsageExport.csv(from: entries, now: now, calendar: paris)

        XCTAssertEqual(csv.split(separator: "\n").last,
                       "2026-11-10T09:00,\"'=HYPERLINK(\"\"x\"\",\"\"y\"\")\",claude-opus-5-5,0,1,0,0,0.0000")
    }

    // MARK: - Edges

    /// A response with no folder leaves its project cell empty, not the card's dash.
    func testResponseWithoutAFolderHasAnEmptyProject() {
        let csv = UsageExport.csv(from: [entry(at: "2026-11-10T08:05:00Z", project: "", input: 1)],
                                  now: now, calendar: paris)
        XCTAssertTrue(csv.contains("\n2026-11-10T09:00,,claude-opus-5-5,1,0,0,0,0.0000\n"), csv)
    }

    func testEmptyExportIsTheHeaderAlone() {
        let stale = [entry(at: now.addingTimeInterval(-8 * 86_400), output: 1)]

        XCTAssertEqual(UsageExport.csv(from: [], now: now, calendar: paris), Self.header + "\n")
        XCTAssertEqual(UsageExport.csv(from: stale, now: now, calendar: paris), Self.header + "\n")
        XCTAssertTrue(UsageExport.rows(from: stale, now: now, calendar: paris).isEmpty)
    }

    func testPriceKeepsFourDecimalsWithAPoint() {
        let entries = [
            entry(at: "2026-11-10T08:10:00Z", output: 1, weight: 0.1),
            entry(at: "2026-11-10T08:20:00Z", output: 1, weight: 0.2),
            entry(at: "2026-11-10T08:10:00Z", model: "claude-haiku-5", output: 1, weight: 12.345_67),
        ]

        let prices = UsageExport.csv(from: entries, now: now, calendar: paris)
            .split(separator: "\n").dropFirst().map { $0.split(separator: ",").last.map(String.init) }

        XCTAssertEqual(prices, ["12.3457", "0.3000"])
    }

    func testFileNameCarriesTheLocalDate() {
        let lateEvening = date("2026-11-10T23:30:00Z")

        XCTAssertEqual(UsageExport.fileName(now: lateEvening, calendar: calendar("UTC")), "claudy-usage-2026-11-10.csv")
        XCTAssertEqual(UsageExport.fileName(now: lateEvening, calendar: paris), "claudy-usage-2026-11-11.csv")
    }

    // MARK: - Sources

    func testSourceWithoutAHistoryHasNothingToExport() async throws {
        let entries = try await StubSource().recentEntries()

        XCTAssertTrue(entries.isEmpty)
    }

    func testLocalSourceExportsItsHistory() async throws {
        let scanner = HeldScanner(entries: [entry(at: now, output: 42)])
        await scanner.release()
        let source = LocalUsageDataSource(scanner: scanner, isInstalled: { true })

        let entries = try await source.recentEntries()

        XCTAssertEqual(entries.map(\.outputTokens), [42])
    }

    /// An export clicked during a refresh joins the pass under way instead of reading the
    /// transcripts a second time.
    func testExportJoinsAPassUnderWay() async throws {
        let scanner = HeldScanner(entries: [entry(at: now, output: 1)])
        let source = LocalUsageDataSource(scanner: scanner, isInstalled: { true })

        let first = Task { try await source.recentEntries() }
        try await waitUntil { await scanner.passes > 0 }
        let second = Task { try await source.recentEntries() }
        try await Task.sleep(nanoseconds: 200_000_000)
        let passes = await scanner.passes
        await scanner.release()
        _ = try await first.value
        _ = try await second.value

        XCTAssertEqual(passes, 1)
    }

    func testLocalSourceWithoutClaudeCodeSaysSo() async {
        let source = LocalUsageDataSource(scanner: HeldScanner(entries: []), isInstalled: { false })

        do {
            _ = try await source.recentEntries()
            XCTFail("no Claude Code must surface, not read as an idle week")
        } catch UsageDataError.claudeNotInstalled {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// Without Claude Code the card shows the demo set, but the export must never write it out:
    /// a file of invented figures would pass for real ones.
    func testAdaptiveSourceExportsNothingWithoutClaudeCode() async throws {
        let local = LocalUsageDataSource(scanner: HeldScanner(entries: [entry(at: now, output: 1)]),
                                         isInstalled: { false })

        let entries = try await AdaptiveUsageDataSource(local: local).recentEntries()

        XCTAssertTrue(entries.isEmpty)
    }

    func testAdaptiveSourceExportsTheLocalHistory() async throws {
        let scanner = HeldScanner(entries: [entry(at: now, output: 7)])
        await scanner.release()
        let local = LocalUsageDataSource(scanner: scanner, isInstalled: { true })

        let entries = try await AdaptiveUsageDataSource(local: local).recentEntries()

        XCTAssertEqual(entries.map(\.outputTokens), [7])
    }

    // MARK: - Fixtures

    /// 11:30 in Paris, which is UTC+1 in November.
    private let now = UsageExportTests.date("2026-11-10T10:30:00Z")

    private var paris: Calendar { calendar("Europe/Paris") }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func date(_ stamp: String) -> Date {
        ISO8601DateFormatter().date(from: stamp)!
    }

    private func date(_ stamp: String) -> Date { Self.date(stamp) }

    private func entry(at stamp: String, project: String = "/Users/me/Claudy", model: String = "claude-opus-5-5",
                       input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0,
                       weight: Double = 0) -> TranscriptEntry {
        entry(at: date(stamp), project: project, model: model, input: input, output: output,
              cacheRead: cacheRead, cacheWrite: cacheWrite, weight: weight)
    }

    private func entry(at date: Date, project: String = "/Users/me/Claudy", model: String = "claude-opus-5-5",
                       input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0,
                       weight: Double = 0) -> TranscriptEntry {
        TranscriptEntry(date: date, model: model, tokens: input + output + cacheRead + cacheWrite,
                        weight: weight, cwd: project, project: project, sessionID: "s",
                        isSidechain: false, dedupKey: UUID().uuidString,
                        inputTokens: input, outputTokens: output,
                        cacheReadTokens: cacheRead, cacheWriteTokens: cacheWrite)
    }

    private struct Timeout: Error {}

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<40 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw Timeout()
    }
}
