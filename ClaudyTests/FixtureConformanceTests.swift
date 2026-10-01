import XCTest
@testable import Claudy

/// The cases in `Fixtures/` describe, as plain data, what Claudy reads from Anthropic's answers.
/// Each one runs here against the real parsers, so the data and the app can never drift apart:
/// a case that no longer holds fails this test.
final class FixtureConformanceTests: XCTestCase {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    private static let stamp = ISO8601DateFormatter()

    func testUsageAnswers() throws {
        let folder = Self.root.appendingPathComponent("usage", isDirectory: true)
        let expectations = try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".expected.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(expectations.isEmpty, "no usage case found in \(folder.path)")

        for expectedURL in expectations {
            let name = expectedURL.lastPathComponent.replacingOccurrences(of: ".expected.json", with: "")
            let payload = try Data(contentsOf: folder.appendingPathComponent("\(name).json"))
            let expected = try object(at: expectedURL)
            let now = try XCTUnwrap(Self.stamp.date(from: try XCTUnwrap(expected["now"] as? String)), name)

            let reading = ClaudeAccountClient.parseUsage(payload, now: now)
            guard let wanted = expected["reading"] as? [String: Any] else {
                XCTAssertNil(reading, "\(name): no reading expected")
                continue
            }
            let actual = try XCTUnwrap(reading, "\(name): a reading was expected")
            XCTAssertEqual(actual.source, .api, name)
            try check(actual.session, against: wanted["session"], "\(name).session")
            try check(actual.weekly, against: wanted["weekly"], "\(name).weekly")
            try check(actual.scoped, against: wanted["scoped"], "\(name).scoped")
            try check(actual.spend, against: wanted["spend"], "\(name).spend")
        }
    }

    /// Each case is a `projects` folder, copied to a temporary one with `{{RECENT}}` replaced by
    /// a timestamp ten minutes old: only the last days of history are read.
    func testTranscripts() async throws {
        let folder = Self.root.appendingPathComponent("transcripts", isDirectory: true)
        let cases = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertFalse(cases.isEmpty, "no transcript case found in \(folder.path)")
        let recent = Self.stamp.string(from: Date().addingTimeInterval(-600))

        for name in cases {
            let source = folder.appendingPathComponent("\(name)/projects", isDirectory: true)
            let projects = FileManager.default.temporaryDirectory
                .appendingPathComponent("claudy-fixture-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: projects) }

            let walker = try XCTUnwrap(FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil))
            for case let file as URL in walker where file.pathExtension == "jsonl" {
                let relative = file.path.replacingOccurrences(of: source.path + "/", with: "")
                let target = projects.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let text = try String(contentsOf: file, encoding: .utf8)
                try text.replacingOccurrences(of: "{{RECENT}}", with: recent)
                    .write(to: target, atomically: true, encoding: .utf8)
            }

            let entries = try await TranscriptScanner(projectsDirectories: { [projects] }).scan()
            let expected = try object(at: folder.appendingPathComponent("\(name)/expected.json"))
            let tokens = try XCTUnwrap(expected["tokens"] as? [Int], name)
            XCTAssertEqual(entries.map(\.tokens).sorted(), tokens, name)
        }
    }

    func testPlanLabels() throws {
        for item in try cases("plan-labels.json") {
            let candidates = try XCTUnwrap(item["candidates"] as? [Any]).map { $0 as? String }
            XCTAssertEqual(AccountLoader.planLabel(candidates: candidates), item["label"] as? String,
                           "\(candidates)")
        }
    }

    func testModelNames() throws {
        for item in try cases("model-names.json") {
            let identifier = try XCTUnwrap(item["identifier"] as? String)
            XCTAssertEqual(ModelName.display(identifier), item["display"] as? String, identifier)
            XCTAssertEqual("\(ModelName.accent(identifier))", item["accent"] as? String, identifier)
        }
    }

    // MARK: - Helpers

    private func object(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                      url.lastPathComponent)
    }

    private func cases(_ file: String) throws -> [[String: Any]] {
        try XCTUnwrap(object(at: Self.root.appendingPathComponent(file))["cases"] as? [[String: Any]], file)
    }

    private func date(_ raw: Any?) -> Date? {
        (raw as? String).flatMap(Self.stamp.date(from:))
    }

    private func check(_ window: QuotaWindow?, against raw: Any?, _ label: String) throws {
        guard let wanted = raw as? [String: Any] else {
            XCTAssertNil(window, "\(label): none expected")
            return
        }
        let window = try XCTUnwrap(window, "\(label): expected")
        XCTAssertEqual(window.percent, try XCTUnwrap(wanted["percent"] as? Double), accuracy: 0.0001, label)
        XCTAssertEqual(window.resetsAt, date(wanted["resetsAt"]), label)
        XCTAssertEqual(window.label, wanted["label"] as? String, label)
    }

    private func check(_ spend: SpendReading?, against raw: Any?, _ label: String) throws {
        guard let wanted = raw as? [String: Any] else {
            XCTAssertNil(spend, "\(label): none expected")
            return
        }
        let spend = try XCTUnwrap(spend, "\(label): expected")
        XCTAssertEqual(spend.used, try XCTUnwrap(wanted["used"] as? Double), accuracy: 0.0001, label)
        XCTAssertEqual(spend.limit, try XCTUnwrap(wanted["limit"] as? Double), accuracy: 0.0001, label)
        XCTAssertEqual(spend.percent, try XCTUnwrap(wanted["percent"] as? Double), accuracy: 0.00001, label)
        XCTAssertEqual(spend.currency, wanted["currency"] as? String, label)
        XCTAssertEqual(spend.isLimitReached, wanted["isLimitReached"] as? Bool, label)
        XCTAssertEqual(spend.resetsAt, date(wanted["resetsAt"]), label)
    }
}
