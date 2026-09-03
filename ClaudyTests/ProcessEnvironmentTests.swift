import XCTest
@testable import Claudy

final class ProcessEnvironmentTests: XCTestCase {

    /// Builds a KERN_PROCARGS2 buffer: argc, exec path, padding, arguments, environment.
    private func buffer(argc: Int32, execPath: String, args: [String], env: [String]) -> [UInt8] {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: argc.littleEndian) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(execPath.utf8))
        bytes.append(contentsOf: [0, 0, 0])
        for argument in args {
            bytes.append(contentsOf: Array(argument.utf8))
            bytes.append(0)
        }
        for entry in env {
            bytes.append(contentsOf: Array(entry.utf8))
            bytes.append(0)
        }
        return bytes
    }

    func testDetectsClaudeCodeMarker() {
        let raw = buffer(
            argc: 2, execPath: "/usr/bin/python3",
            args: ["python3", "-m"],
            env: ["PATH=/usr/bin", "CLAUDECODE=1", "TERM=xterm"]
        )
        let markers = ProcessEnvironment.parse(raw)
        XCTAssertEqual(markers, ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil))
    }

    func testReadsProjectDirectory() {
        let raw = buffer(
            argc: 1, execPath: "/bin/bun", args: ["bun"],
            env: ["CLAUDE_PROJECT_DIR=/Users/x/Dev/Surikat"]
        )
        let markers = ProcessEnvironment.parse(raw)
        XCTAssertEqual(markers?.isClaude, true)
        XCTAssertEqual(markers?.projectDirectory, "/Users/x/Dev/Surikat")
    }

    func testEntrypointAloneIsEnough() {
        let raw = buffer(argc: 1, execPath: "/bin/zsh", args: ["zsh"],
                         env: ["CLAUDE_CODE_ENTRYPOINT=cli"])
        XCTAssertEqual(ProcessEnvironment.parse(raw)?.isClaude, true)
    }

    /// The decisive case: a command line that merely mentions the marker must not attribute
    /// the process. Arguments are skipped by counting argc, never by searching for text.
    func testCommandLineMentionIsNotAnAttribution() {
        let raw = buffer(
            argc: 2, execPath: "/bin/echo",
            args: ["echo", "CLAUDECODE=1"],
            env: ["PATH=/usr/bin"]
        )
        XCTAssertEqual(ProcessEnvironment.parse(raw)?.isClaude, false)
    }

    func testUnrelatedProcessHasNoMarkers() {
        let raw = buffer(argc: 1, execPath: "/usr/bin/node", args: ["node"],
                         env: ["PATH=/usr/bin", "HOME=/Users/x"])
        XCTAssertEqual(ProcessEnvironment.parse(raw), ProcessEnvironment.Markers(isClaude: false, projectDirectory: nil))
    }

    func testTruncatedBufferReturnsNil() {
        XCTAssertNil(ProcessEnvironment.parse([1, 0]))
    }
}
