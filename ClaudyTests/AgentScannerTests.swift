import XCTest
@testable import Claudy

/// The agents list read from a fake Claude Code home: `sessions/<pid>.json` for the open sessions,
/// `projects/<folder>/<session>/subagents/agent-<id>.{meta.json,jsonl}` for what they launched.
final class AgentScannerTests: XCTestCase {

    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_793_468_000)
    private let livePID: Int32 = 4242
    private let closedPID: Int32 = 4343

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudy-agents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixture

    private func scanner() -> AgentScanner {
        let root = self.root!, now = self.now, livePID = self.livePID
        return AgentScanner(
            sessionsDirectory: { root.appendingPathComponent("sessions", isDirectory: true) },
            projectsDirectories: { [root.appendingPathComponent("projects", isDirectory: true)] },
            isLive: { pid, _ in pid == livePID },
            now: { now }
        )
    }

    private func writeSession(pid: Int32, id: String, name: String?, cwd: String, procStart: String? = nil) throws {
        var session: [String: Any] = ["pid": pid, "sessionId": id, "cwd": cwd, "status": "busy"]
        session["name"] = name
        session["procStart"] = procStart
        let folder = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: session).write(to: folder.appendingPathComponent("\(pid).json"))
    }

    private func subagents(of session: String) throws -> URL {
        let folder = root.appendingPathComponent("projects/-Users-me-Claire/\(session)/subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @discardableResult
    private func writeAgent(session: String, id: String, meta: [String: Any], lines: [[String: Any]],
                            modified: Date) throws -> URL {
        let folder = try subagents(of: session)
        try JSONSerialization.data(withJSONObject: meta)
            .write(to: folder.appendingPathComponent("agent-\(id).meta.json"))
        let transcript = folder.appendingPathComponent("agent-\(id).jsonl")
        try jsonl(lines).write(to: transcript)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: transcript.path)
        return transcript
    }

    private func jsonl(_ lines: [[String: Any]]) throws -> Data {
        var data = Data()
        for line in lines {
            data += try JSONSerialization.data(withJSONObject: line)
            data += Data("\n".utf8)
        }
        return data
    }

    private func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func prompt(at date: Date) -> [String: Any] {
        ["type": "user", "timestamp": stamp(date), "message": ["role": "user", "content": "Do the thing"]]
    }

    private func tool(_ id: String, _ name: String, _ input: [String: Any], at date: Date) -> [String: Any] {
        ["type": "assistant", "timestamp": stamp(date),
         "message": ["content": [["type": "tool_use", "id": id, "name": name, "input": input]]]]
    }

    private let running: [String: Any] = ["agentType": "general-purpose",
                                          "description": "Make prescription file reading reliable"]

    // MARK: - Tests

    func testListsWhatALiveSessionLaunched() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        try writeAgent(session: "s1", id: "a1", meta: running, lines: [
            prompt(at: now.addingTimeInterval(-600)),
            tool("t1", "Read", ["file_path": "/Users/me/Claire/a.ts"], at: now.addingTimeInterval(-500)),
            tool("t2", "Write", ["file_path": "/Users/me/Claire/banc.ts"], at: now.addingTimeInterval(-20)),
        ], modified: now.addingTimeInterval(-20))

        let agents = await scanner().scan()

        XCTAssertEqual(agents.count, 1)
        let agent = try XCTUnwrap(agents.first)
        XCTAssertEqual(agent.id, "a1")
        XCTAssertEqual(agent.title, "Make prescription file reading reliable")
        XCTAssertEqual(agent.sessionName, "claire-bb")
        XCTAssertEqual(agent.sessionPID, livePID)
        XCTAssertEqual(agent.startedAt.timeIntervalSince1970, now.addingTimeInterval(-600).timeIntervalSince1970,
                       accuracy: 0.01)
        XCTAssertEqual(agent.actionCount, 2)
        XCTAssertEqual(agent.editedFiles, ["banc.ts"])
        XCTAssertEqual(agent.lastAction?.file, "banc.ts")
        XCTAssertEqual(agent.lastAction?.kind, .edit)
        XCTAssertEqual(agent.status(at: now), .working)
    }

    /// The session file's start time reaches the liveness check, so a reused pid is told apart
    /// from the process that wrote the file.
    func testSessionStartTimeReachesTheLivenessCheck() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire",
                         procStart: "Mon Nov  9 22:26:03 2026")
        try writeAgent(session: "s1", id: "a1", meta: running, lines: [prompt(at: now)], modified: now)
        let root = self.root!, now = self.now, livePID = self.livePID
        let seen = Seen()
        let scanner = AgentScanner(
            sessionsDirectory: { root.appendingPathComponent("sessions", isDirectory: true) },
            projectsDirectories: { [root.appendingPathComponent("projects", isDirectory: true)] },
            isLive: { pid, start in seen.record(start); return pid == livePID },
            now: { now }
        )

        let agents = await scanner.scan()

        let expected = ProcessIdentity.date(fromProcStart: "Mon Nov  9 22:26:03 2026")
        XCTAssertNotNil(expected)
        XCTAssertEqual(seen.dates, [expected])
        XCTAssertEqual(agents.first?.sessionStartedAt, expected)
    }

    func testIgnoresTheAgentsOfAClosedSession() async throws {
        try writeSession(pid: closedPID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        try writeAgent(session: "s1", id: "a1", meta: running, lines: [prompt(at: now)], modified: now)

        let agents = await scanner().scan()

        XCTAssertTrue(agents.isEmpty)
    }

    /// A finished agent stays ten minutes, marked done, then leaves the list.
    func testFinishedAgentLingersTenMinutesThenLeaves() async throws {
        var finished = running
        finished["finished"] = true
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        try writeAgent(session: "s1", id: "recent", meta: finished, lines: [prompt(at: now.addingTimeInterval(-900))],
                       modified: now.addingTimeInterval(-9 * 60))
        try writeAgent(session: "s1", id: "old", meta: finished, lines: [prompt(at: now.addingTimeInterval(-1800))],
                       modified: now.addingTimeInterval(-11 * 60))

        let agents = await scanner().scan()

        XCTAssertEqual(agents.map(\.id), ["recent"])
        XCTAssertEqual(agents.first?.status(at: now), .done)
    }

    /// Not finished but silent for half an hour: interrupted, not at work.
    func testSilentAgentIsDropped() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        try writeAgent(session: "s1", id: "a1", meta: running, lines: [prompt(at: now.addingTimeInterval(-3600))],
                       modified: now.addingTimeInterval(-31 * 60))

        let agents = await scanner().scan()

        XCTAssertTrue(agents.isEmpty)
    }

    /// Claude Code can write the same tool call on more than one line.
    func testSameToolCallWrittenTwiceCountsOnce() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        let call = tool("t1", "Bash", ["command": "ls", "description": "List files"], at: now.addingTimeInterval(-10))
        try writeAgent(session: "s1", id: "a1", meta: running,
                       lines: [prompt(at: now.addingTimeInterval(-60)), call, call],
                       modified: now.addingTimeInterval(-10))

        let agents = await scanner().scan()

        XCTAssertEqual(agents.first?.actionCount, 1)
    }

    func testPicksUpWhatWasAppendedSinceTheLastPass() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        let transcript = try writeAgent(session: "s1", id: "a1", meta: running, lines: [
            prompt(at: now.addingTimeInterval(-120)),
            tool("t1", "Read", ["file_path": "/x/a.ts"], at: now.addingTimeInterval(-100)),
        ], modified: now.addingTimeInterval(-100))
        let scanner = scanner()
        _ = await scanner.scan()

        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: jsonl([tool("t2", "Edit", ["file_path": "/x/b.ts"], at: now.addingTimeInterval(-5))]))
        try handle.close()
        let agents = await scanner.scan()

        XCTAssertEqual(agents.first?.actionCount, 2)
        XCTAssertEqual(agents.first?.editedFiles, ["b.ts"])
    }

    /// A session resumed while its first process still runs has two pid files and one id.
    func testSessionOpenTwiceListsItsAgentsOnce() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        try writeSession(pid: livePID + 1, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        try writeAgent(session: "s1", id: "a1", meta: running, lines: [prompt(at: now)], modified: now)
        let root = self.root!, now = self.now, livePID = self.livePID
        let scanner = AgentScanner(
            sessionsDirectory: { root.appendingPathComponent("sessions", isDirectory: true) },
            projectsDirectories: { [root.appendingPathComponent("projects", isDirectory: true)] },
            isLive: { pid, _ in pid == livePID || pid == livePID + 1 },
            now: { now }
        )

        let agents = await scanner.scan()

        XCTAssertEqual(agents.map(\.id), ["a1"])
    }

    func testSessionWithoutANameTakesItsFolderName() async throws {
        try writeSession(pid: livePID, id: "s1", name: nil, cwd: "/Users/me/EVAN")
        try writeAgent(session: "s1", id: "a1", meta: running, lines: [prompt(at: now)], modified: now)

        let agents = await scanner().scan()

        XCTAssertEqual(agents.first?.sessionName, "EVAN")
    }

    func testOldestAgentComesFirst() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        try writeAgent(session: "s1", id: "late", meta: running, lines: [prompt(at: now.addingTimeInterval(-60))],
                       modified: now)
        try writeAgent(session: "s1", id: "early", meta: running, lines: [prompt(at: now.addingTimeInterval(-600))],
                       modified: now)

        let agents = await scanner().scan()

        XCTAssertEqual(agents.map(\.id), ["early", "late"])
    }
}

/// Records the start dates handed to the liveness check.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var _dates: [Date?] = []
    var dates: [Date?] { lock.withLock { _dates } }
    func record(_ date: Date?) { lock.withLock { _dates.append(date) } }
}
