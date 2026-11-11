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

    private func scanner(host: HostApp? = nil) -> AgentScanner {
        let root = self.root!, now = self.now, livePID = self.livePID
        return AgentScanner(
            sessionsDirectory: { root.appendingPathComponent("sessions", isDirectory: true) },
            projectsDirectories: { [root.appendingPathComponent("projects", isDirectory: true)] },
            isLive: { pid, _ in pid == livePID },
            hostApp: { _ in host },
            now: { now }
        )
    }

    private func writeSession(pid: Int32, id: String, name: String?, cwd: String, procStart: String? = nil,
                              status: String = "busy", extra: [String: Any] = [:]) throws {
        var session: [String: Any] = ["pid": pid, "sessionId": id, "cwd": cwd, "status": status]
        session["name"] = name
        session["procStart"] = procStart
        session.merge(extra) { $1 }
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

    /// The session's own transcript, beside its agents' folder.
    @discardableResult
    private func writeTranscript(session: String, lines: [[String: Any]]) throws -> URL {
        let folder = root.appendingPathComponent("projects/-Users-me-Claire", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(session).jsonl")
        try jsonl(lines).write(to: url)
        return url
    }

    private func typed(_ content: Any, meta: Bool = false) -> [String: Any] {
        var line: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
        if meta { line["isMeta"] = true }
        return line
    }

    // MARK: - Sessions

    /// A session's status, what it waits for and since when, as Claude Code wrote them.
    func testListsOpenSessionsWithTheirStatus() async throws {
        let host = HostApp(name: "Visual Studio Code", bundleURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
        try writeSession(pid: livePID, id: "s1", name: "evan-b6", cwd: "/Users/me/EVAN", status: "waiting",
                         extra: ["waitingFor": "permission prompt", "statusUpdatedAt": 1_793_467_940_000.0,
                                 "startedAt": 1_793_460_000_000.0, "entrypoint": "claude-vscode"])
        try writeSession(pid: closedPID, id: "s2", name: "gone", cwd: "/Users/me/Gone")

        let activity = await scanner(host: host).scanActivity()

        XCTAssertEqual(activity.sessions.count, 1)
        let session = try XCTUnwrap(activity.sessions.first)
        XCTAssertEqual(session.id, "s1")
        XCTAssertEqual(session.name, "evan-b6")
        XCTAssertEqual(session.status, .waiting(reason: "permission prompt"))
        XCTAssertEqual(session.waitingReason, "Permission prompt")
        XCTAssertEqual(session.statusSince, Date(timeIntervalSince1970: 1_793_467_940))
        XCTAssertEqual(session.openedAt, Date(timeIntervalSince1970: 1_793_460_000))
        XCTAssertEqual(session.folderName, "EVAN")
        XCTAssertEqual(session.host, host)
        XCTAssertFalse(session.isBackground)
        XCTAssertTrue(activity.agents.isEmpty)
    }

    /// A session open in two processes is one session.
    func testSessionOpenTwiceIsListedOnce() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        let activity = await scanner().scanActivity()
        XCTAssertEqual(activity.sessions.map(\.id), ["s1"])
    }

    /// The last thing typed: not a tool result, not what Claude Code adds in tags, not a meta line.
    func testReadsTheLastPromptOfASession() async throws {
        try writeSession(pid: livePID, id: "s1", name: "claire-bb", cwd: "/Users/me/Claire")
        let url = try writeTranscript(session: "s1", lines: [
            typed("first question"),
            typed([["type": "text", "text": "<ide_opened_file>a.ts</ide_opened_file>"],
                   ["type": "text", "text": "add the allergens\n  filter to the menu page"]]),
            typed([["type": "tool_result", "tool_use_id": "t1", "content": "ok"]]),
            typed("<command-name>/model</command-name>"),
            typed("Caveat: this is meta", meta: true),
            typed([["type": "text", "text": "[Request interrupted by user]"]]),
        ])
        let scanner = scanner()

        var activity = await scanner.scanActivity()
        XCTAssertEqual(activity.sessions.first?.lastPrompt, "add the allergens filter to the menu page")

        // Appended since: read on the next pass, the rest of the file is not read again.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: try jsonl([typed("now ship it")]))
        try handle.close()
        activity = await scanner.scanActivity()
        XCTAssertEqual(activity.sessions.first?.lastPrompt, "now ship it")
    }

    /// Claude Code's own record of the last prompt is read too, and a compaction summary is not
    /// taken for one.
    func testLastPromptLineAndCompactSummary() {
        func line(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        XCTAssertEqual(AgentScanner.prompt(from: line(["type": "last-prompt", "lastPrompt": "Mettre en place !"])),
                       "Mettre en place !")
        var summary = typed("This session is being continued from a previous conversation")
        summary["isCompactSummary"] = true
        XCTAssertNil(AgentScanner.prompt(from: line(summary)))
    }

    /// A long prompt is cut: it only has to say which conversation it is.
    func testLongPromptIsCut() {
        let long = String(repeating: "word ", count: 100)
        let line = try! JSONSerialization.data(withJSONObject: typed(long))
        let prompt = AgentScanner.prompt(from: line)
        XCTAssertEqual(prompt?.count, AgentScanner.promptLength + 1)
        XCTAssertEqual(prompt?.hasSuffix("…"), true)
    }

    /// The outermost app a binary runs in: VS Code's helper is VS Code.
    func testHostAppIsTheOutermostBundle() {
        let helper = "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"
        XCTAssertEqual(ProcessIdentity.hostApp(executable: helper)?.name, "Visual Studio Code")
        XCTAssertEqual(ProcessIdentity.hostApp(executable: helper)?.bundleURL.path, "/Applications/Visual Studio Code.app")
        XCTAssertEqual(ProcessIdentity.hostApp(executable: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")?.name,
                       "Terminal")
        XCTAssertNil(ProcessIdentity.hostApp(executable: "/opt/homebrew/bin/tmux"))
    }

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
