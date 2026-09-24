import XCTest
@testable import Claudy

/// Times the first read of histories, in whatever build it runs in. Skipped in a normal test run:
/// `Scripts/preflight.sh` sets, in a Release build,
///
/// - `TEST_RUNNER_CLAUDY_BENCHMARK_HISTORIES`: history folders, separated by `:`;
/// - `TEST_RUNNER_CLAUDY_BENCHMARK_REPORT`: the JSON file to write, keyed by folder name;
/// - `TEST_RUNNER_CLAUDY_BENCHMARK_EFFICIENCY=1`: also read each history confined to the
///   efficiency cores at background priority, the closest a Mac comes to a slower one.
///
/// Each figure is the best of three reads, the one least disturbed by whatever else runs.
final class ScanBenchmarkTests: XCTestCase {

    func testFirstReadOfHistories() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let histories = environment["CLAUDY_BENCHMARK_HISTORIES"],
              let report = environment["CLAUDY_BENCHMARK_REPORT"] else {
            throw XCTSkip("Run by Scripts/preflight.sh only.")
        }
        let measuresEfficiency = environment["CLAUDY_BENCHMARK_EFFICIENCY"] == "1"

        var results: [String: [String: Any]] = [:]
        for history in histories.split(separator: ":").map(String.init) {
            let projects = URL(fileURLWithPath: history, isDirectory: true).appendingPathComponent("projects")
            let normal = try await bestFirstRead(of: projects)
            XCTAssertGreaterThan(normal.responses, 0, "\(history) read as empty")
            var result: [String: Any] = ["responses": normal.responses, "seconds": normal.seconds]
            if measuresEfficiency {
                setpriority(PRIO_DARWIN_PROCESS, 0, PRIO_DARWIN_BG)
                defer { setpriority(PRIO_DARWIN_PROCESS, 0, 0) }
                result["efficiencySeconds"] = try await bestFirstRead(of: projects).seconds
            }
            results[URL(fileURLWithPath: history).lastPathComponent] = result
        }
        try JSONSerialization.data(withJSONObject: results).write(to: URL(fileURLWithPath: report))
    }

    /// A new scanner each time, so every read is a first one.
    private func bestFirstRead(of projects: URL) async throws -> (seconds: Double, responses: Int) {
        var times: [Double] = []
        var responses = 0
        for _ in 0..<3 {
            let start = Date()
            responses = try await TranscriptScanner(projectsDirectories: { [projects] }).scan().count
            times.append(Date().timeIntervalSince(start))
        }
        return (times.min() ?? 0, responses)
    }
}
