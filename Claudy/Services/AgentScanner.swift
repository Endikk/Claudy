import Foundation

protocol AgentScanning: Sendable {
    func scan() async -> [RunningAgent]
}

/// Finds the subagents Claude Code is running on this Mac, from the files it keeps anyway:
///
/// - `<config>/sessions/<pid>.json`, one per open Claude Code process, with the session's id and
///   name. A file whose process is gone is a session that closed without cleaning up.
/// - `<projects>/<folder>/<session>/subagents/agent-<id>.meta.json`, written when an agent is
///   launched (its description) and again when it finishes (`finished`).
/// - `agent-<id>.jsonl` beside it, the agent's transcript: one line per message, its tool calls
///   among them.
///
/// Nothing is installed in Claude Code for this. As with `TranscriptScanner`, a cursor per
/// transcript means each pass reads only what was appended since the previous one: an agent's
/// transcript passes ten megabytes on a long task.
actor AgentScanner: AgentScanning {

    /// A finished agent keeps its row this long, marked done, so its end is seen.
    static let doneLinger: TimeInterval = 60
    /// An unfinished agent silent this long was interrupted: its session lives on, it does not.
    static let silenceLimit: TimeInterval = 30 * 60

    private struct Session {
        let id: String
        let name: String
    }

    private struct SessionFile: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String?
        let name: String?
    }

    private struct Meta: Decodable {
        let agentType: String?
        let description: String?
        let finished: Bool?
    }

    /// Read state for one transcript.
    private struct Transcript {
        var offset: UInt64 = 0
        /// File identifier (inode): detects a replacement of equal or greater size.
        var fileID: NSObject?
        var startedAt: Date?
        /// Tool call ids already counted: one call can be written on more than one line.
        var seen: Set<String> = []
        var count = 0
        var recent: [AgentAction] = []
        var last: AgentAction?
        var edited: [String] = []
    }

    private var transcripts: [URL: Transcript] = [:]
    /// Where each session's subagents live, once found: looking means listing every project.
    private var folders: [String: URL] = [:]

    private let sessionsDirectory: @Sendable () -> URL
    private let projectsDirectories: @Sendable () -> [URL]
    private let isAlive: @Sendable (Int32) -> Bool
    private let now: @Sendable () -> Date

    private let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let withoutFraction = ISO8601DateFormatter()

    init(sessionsDirectory: @escaping @Sendable () -> URL = {
             ClaudeHome.configDirectory.appendingPathComponent("sessions", isDirectory: true)
         },
         projectsDirectories: @escaping @Sendable () -> [URL] = { ClaudeHome.projectsDirectories },
         isAlive: @escaping @Sendable (Int32) -> Bool = { AgentScanner.processIsAlive($0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.sessionsDirectory = sessionsDirectory
        self.projectsDirectories = projectsDirectories
        self.isAlive = isAlive
        self.now = now
    }

    /// The agents of every open session, oldest first.
    func scan() -> [RunningAgent] {
        let moment = now()
        var agents: [RunningAgent] = []
        var visited: Set<URL> = []
        let sessions = liveSessions()
        for session in sessions {
            guard let folder = subagentsFolder(of: session.id) else { continue }
            // `insert` also keeps a session open in two processes from listing its agents twice.
            for url in transcriptURLs(in: folder) where visited.insert(url).inserted {
                if let agent = agent(at: url, in: session, now: moment) { agents.append(agent) }
            }
        }
        transcripts = transcripts.filter { visited.contains($0.key) }
        let open = Set(sessions.map(\.id))
        folders = folders.filter { open.contains($0.key) }
        return agents.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    /// `kill` with no signal only asks whether the process exists. `EPERM` means it does, under
    /// another user.
    static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Sessions

    private func liveSessions() -> [Session] {
        let folder = sessionsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(SessionFile.self, from: data),
                  isAlive(file.pid) else { return nil }
            let folderName = file.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            let name = [file.name, folderName].compactMap { $0 }.first { !$0.isEmpty } ?? "session"
            return Session(id: file.sessionId, name: name)
        }
    }

    /// The project folder is named after the session's working directory, with every character
    /// but letters and digits replaced: rebuilding that name would break on the first change of
    /// rule, so the folder is looked for instead.
    private func subagentsFolder(of session: String) -> URL? {
        let manager = FileManager.default
        if let known = folders[session], manager.fileExists(atPath: known.path) { return known }
        for projects in projectsDirectories() {
            guard let projectFolders = try? manager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)
            else { continue }
            for project in projectFolders {
                let candidate = project.appendingPathComponent(session, isDirectory: true)
                    .appendingPathComponent("subagents", isDirectory: true)
                if manager.fileExists(atPath: candidate.path) {
                    folders[session] = candidate
                    return candidate
                }
            }
        }
        return nil
    }

    /// Workflows nest their agents one folder deeper, hence the walk.
    private func transcriptURLs(in folder: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-") }
    }

    // MARK: - One agent

    private func agent(at url: URL, in session: Session, now: Date) -> RunningAgent? {
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate else { return nil }
        let meta = Self.meta(beside: url)
        let isFinished = meta?.finished == true
        guard now.timeIntervalSince(modified) < (isFinished ? Self.doneLinger : Self.silenceLimit) else {
            transcripts[url] = nil
            return nil
        }

        let state = read(url, now: now)
        let id = String(url.deletingPathExtension().lastPathComponent.dropFirst("agent-".count))
        let title = [meta?.description, meta?.agentType].compactMap { $0 }.first { !$0.isEmpty } ?? "Agent"
        return RunningAgent(id: id, sessionID: session.id, sessionName: session.name, title: title,
                            startedAt: state.startedAt ?? modified, lastActivity: modified,
                            isFinished: isFinished, actionCount: state.count, recent: state.recent,
                            lastAction: state.last, editedFiles: state.edited)
    }

    private static func meta(beside transcript: URL) -> Meta? {
        let url = transcript.deletingPathExtension().appendingPathExtension("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    // MARK: - Reading

    private func read(_ url: URL, now: Date) -> Transcript {
        let currentID = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier as? NSObject
        var state = transcripts[url] ?? Transcript(fileID: currentID)
        defer {
            let cutoff = now.addingTimeInterval(-RunningAgent.trackSpan)
            state.recent.removeAll { $0.date < cutoff }
            transcripts[url] = state
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return state }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0

        let replaced = state.fileID != nil && currentID != nil && !state.fileID!.isEqual(currentID)
        if replaced || size < state.offset { state = Transcript(fileID: currentID) }

        guard size > state.offset,
              (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return state }

        let (lines, consumed) = Self.lines(in: data)
        state.offset += UInt64(consumed)
        for range in lines where state.startedAt == nil || Self.holdsToolUse(data, range) {
            absorb(data.subdata(in: range), into: &state)
        }
        return state
    }

    /// Picks the start date off the first dated line, and every tool call off the others.
    private func absorb(_ line: Data, into state: inout Transcript) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let date = (object["timestamp"] as? String).flatMap(date(from:)) else { return }
        if state.startedAt == nil { state.startedAt = date }

        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return }
        for block in content where block["type"] as? String == "tool_use" {
            guard let id = block["id"] as? String, let tool = block["name"] as? String,
                  state.seen.insert(id).inserted else { continue }
            let input = block["input"] as? [String: Any]
            let path = (input?["file_path"] as? String) ?? (input?["notebook_path"] as? String)
            let action = AgentAction(date: date, kind: AgentActionKind(tool: tool), tool: tool,
                                     file: path.map { ($0 as NSString).lastPathComponent })
            state.count += 1
            state.last = action
            state.recent.append(action)
            if action.kind == .edit, let file = action.file, !state.edited.contains(file) {
                state.edited.append(file)
            }
        }
    }

    private func date(from stamp: String) -> Date? {
        withFraction.date(from: stamp) ?? withoutFraction.date(from: stamp)
    }

    /// The complete lines of `data`, as byte ranges, and how many bytes they span. The tail after
    /// the last newline is a write in progress, left for the next pass, unless its JSON already
    /// parses: some transcripts end without a newline.
    ///
    /// Ranges count from the first byte, so `data` must start at index 0, as `readToEnd` gives it.
    private static func lines(in data: Data) -> (lines: [Range<Int>], consumed: Int) {
        data.withUnsafeBytes { raw -> ([Range<Int>], Int) in
            guard let bytes = raw.baseAddress else { return ([], 0) }
            var lines: [Range<Int>] = []
            var start = 0
            while start < raw.count, let newline = memchr(bytes + start, 0x0A, raw.count - start) {
                let end = bytes.distance(to: UnsafeRawPointer(newline))
                if end > start { lines.append(start..<end) }
                start = end + 1
            }
            guard start < raw.count else { return (lines, raw.count) }
            let tail = Data(bytes: bytes + start, count: raw.count - start)
            guard (try? JSONSerialization.jsonObject(with: tail)) != nil else { return (lines, start) }
            lines.append(start..<raw.count)
            return (lines, raw.count)
        }
    }

    private static let toolUseMarker: [UInt8] = Array("\"tool_use\"".utf8)

    /// Most lines are tool results and prompts: skipped with `memmem` before any parsing.
    private static func holdsToolUse(_ data: Data, _ range: Range<Int>) -> Bool {
        data.withUnsafeBytes { raw in
            guard let bytes = raw.baseAddress else { return false }
            return toolUseMarker.withUnsafeBytes { marker in
                memmem(bytes + range.lowerBound, range.count, marker.baseAddress, marker.count) != nil
            }
        }
    }
}
