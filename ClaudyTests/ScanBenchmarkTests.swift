import XCTest
@testable import Claudy

/// Times the first read of a history, in whatever build it runs in. Skipped in a normal test run:
/// `Scripts/preflight.sh` points it at synthetic histories, in a Release build, through
/// `TEST_RUNNER_CLAUDY_BENCHMARK_HISTORY` and `TEST_RUNNER_CLAUDY_BENCHMARK_REPORT`.
///
/// Each history is read three times as it is, then three times confined to the efficiency cores
/// at background priority: the closest this Mac comes to a slower one.
final class ScanBenchmarkTests: XCTestCase {

    func testFirstReadOfAHistory() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let history = environment["CLAUDY_BENCHMARK_HISTORY"],
              let report = environment["CLAUDY_BENCHMARK_REPORT"] else {
            throw XCTSkip("Run by Scripts/preflight.sh only.")
        }
        let projects = URL(fileURLWithPath: history, isDirectory: true).appendingPathComponent("projects")

        let normal = try await medianFirstRead(of: projects)
        setpriority(PRIO_DARWIN_PROCESS, 0, PRIO_DARWIN_BG)
        defer { setpriority(PRIO_DARWIN_PROCESS, 0, 0) }
        let efficiency = try await medianFirstRead(of: projects)

        let result: [String: Any] = [
            "responses": normal.responses,
            "seconds": normal.seconds,
            "efficiencySeconds": efficiency.seconds,
        ]
        try JSONSerialization.data(withJSONObject: result).write(to: URL(fileURLWithPath: report))
        XCTAssertGreaterThan(normal.responses, 0, "the history read as empty")
    }

    /// A new scanner each time, so every read is a first one.
    private func medianFirstRead(of projects: URL) async throws -> (seconds: Double, responses: Int) {
        var times: [Double] = []
        var responses = 0
        for _ in 0..<3 {
            let start = Date()
            responses = try await TranscriptScanner(projectsDirectories: { [projects] }).scan().count
            times.append(Date().timeIntervalSince(start))
        }
        return (times.sorted()[1], responses)
    }
}
