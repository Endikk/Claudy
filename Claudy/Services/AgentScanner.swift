import Foundation

protocol AgentScanning: Sendable {
    func scanActivity() async -> ClaudeActivity
}

/// Finds the Claude Code sessions open on this Mac and the subagents they run, from the files
/// Claude Code keeps anyway:
///
/// - `<config>/sessions/<pid>.json`, one per open Claude Code process, with the session's id,
///   name and status: at work, at its prompt, or waiting on the user. A file whose process is
///   gone is a session that closed without cleaning up.
/// - `<projects>/<folder>/<session>.jsonl`, the session's transcript, for the last thing the
///   user asked it.
/// - `<projects>/<folder>/<session>/subagents/agent-<id>.meta.json`, written when an agent is
///   launched (its description) and again when it finishes (`finished`).
/// - `agent-<id>.jsonl` beside it, the agent's transcript: one line per message, its tool calls
///   among them.
///
/// Nothing is installed in Claude Code for this. As with `TranscriptScanner`, a cursor per
/// transcript means each pass reads only what was appended since the previous one: an agent's
/// transcript passes ten megabytes on a long task.
actor AgentScanner: AgentScanning {

    /// A finished agent keeps its row this long, marked done, so its end and what it wrote are
    /// seen even by someone who looks at the card now and then.
    static let doneLinger: TimeInterval = 10 * 60
    /// An unfinished agent silent this long was interrupted: its session lives on, it does not.
    static let silenceLimit: TimeInterval = 30 * 60
    /// How far back from the end of a session's transcript its last prompt is looked for, the
    /// first time: a turn's tool results run long, but rarely past this.
    static let promptLookback: UInt64 = 512 * 1024
    /// A prompt is cut past this many characters: it only has to say which conversation it is.
    static let promptLength = 160

    private struct SessionFile: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String?
        let name: String?
        /// "Mon Nov  9 22:26:03 2026": when the process started, which tells a reused pid apart.
        let procStart: String?
        /// Milliseconds since 1970, like `statusUpdatedAt`.
        let startedAt: Double?
        let entrypoint: String?
        let status: String?
        let waitingFor: String?
        let statusUpdatedAt: Double?
    }

    /// Read state for the last prompt of one session transcript.
    private struct PromptCursor {
        var offset: UInt64 = 0
        var fileID: NSObject?
        var prompt: String?
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
    /// The project folder of each session, once found: looking means listing every project.
    private var folders: [String: URL] = [:]
    private var prompts: [URL: PromptCursor] = [:]
    /// The app each session process runs in. It does not change while the process lives.
    private var hosts: [Int32: HostApp?] = [:]

    private let sessionsDirectory: @Sendable () -> URL
    private let projectsDirectories: @Sendable () -> [URL]
    /// Whether the process a session file names is still that session: its pid, and the start
    /// time the file records when it does.
    private let isLive: @Sendable (Int32, Date?) -> Bool
    private let hostApp: @Sendable (Int32) -> HostApp?
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
         isLive: @escaping @Sendable (Int32, Date?) -> Bool = { ProcessIdentity.isSession(pid: $0, startedAt: $1) },
         hostApp: @escaping @Sendable (Int32) -> HostApp? = { ProcessIdentity.hostApp(of: $0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.sessionsDirectory = sessionsDirectory
        self.projectsDirectories = projectsDirectories
        self.isLive = isLive
        self.hostApp = hostApp
        self.now = now
    }

    /// The agents of every open session, oldest first.
    func scan() -> [RunningAgent] {
        scanActivity().agents
    }

    /// Every open session, and the agents they run, oldest first.
    func scanActivity() -> ClaudeActivity {
        let moment = now()
        var agents: [RunningAgent] = []
        var visited: Set<URL> = []
        var readPrompts: Set<URL> = []
        // A session open in two processes is listed once, and its agents once.
        let sessions = Self.unique(liveSessions())
        var listed: [ClaudeSession] = []
        for (session, file) in sessions {
            let project = projectFolder(of: session.id)
            var prompt: String?
            if let project {
                let transcript = project.appendingPathComponent("\(session.id).jsonl")
                readPrompts.insert(transcript)
                prompt = lastPrompt(in: transcript)
                let subagents = project.appendingPathComponent(session.id, isDirectory: true)
                    .appendingPathComponent("subagents", isDirectory: true)
                for url in transcriptURLs(in: subagents) where visited.insert(url).inserted {
                    if let agent = agent(at: url, in: session, now: moment) { agents.append(agent) }
                }
            }
            listed.append(Self.session(file, startedAt: session.processStartedAt, name: session.name,
                                       host: host(of: session.pid), prompt: prompt))
        }
        transcripts = transcripts.filter { visited.contains($0.key) }
        prompts = prompts.filter { readPrompts.contains($0.key) }
        let open = Set(listed.map(\.id))
        folders = folders.filter { open.contains($0.key) }
        let pids = Set(listed.map(\.pid))
        hosts = hosts.filter { pids.contains($0.key) }
        return ClaudeActivity(sessions: listed,
                              agents: agents.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) })
    }

    // MARK: - Sessions

    /// The session files whose process still runs, read as far as the agents need them.
    private func liveSessions() -> [(ClaudeSession, SessionFile)] {
        let folder = sessionsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(SessionFile.self, from: data) else { return nil }
            let startedAt = file.procStart.flatMap(ProcessIdentity.date(fromProcStart:))
            guard isLive(file.pid, startedAt) else { return nil }
            let folderName = file.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            let name = [file.name, folderName].compactMap { $0 }.first { !$0.isEmpty } ?? "session"
            return (Self.session(file, startedAt: startedAt, name: name, host: nil, prompt: nil), file)
        }
    }

    /// One entry per session id: the process whose status changed last speaks for it.
    private static func unique(_ sessions: [(ClaudeSession, SessionFile)]) -> [(ClaudeSession, SessionFile)] {
        var kept: [String: (ClaudeSession, SessionFile)] = [:]
        for entry in sessions {
            let since = entry.1.statusUpdatedAt ?? 0
            if let held = kept[entry.0.id], (held.1.statusUpdatedAt ?? 0) >= since { continue }
            kept[entry.0.id] = entry
        }
        return kept.values.sorted { ($0.0.openedAt ?? .distantPast, $0.0.id) < ($1.0.openedAt ?? .distantPast, $1.0.id) }
    }

    private static func session(_ file: SessionFile, startedAt: Date?, name: String,
                                host: HostApp?, prompt: String?) -> ClaudeSession {
        ClaudeSession(id: file.sessionId, pid: file.pid, processStartedAt: startedAt, name: name, cwd: file.cwd,
                      openedAt: file.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                      status: ClaudeSession.Status(raw: file.status, waitingFor: file.waitingFor),
                      statusSince: file.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                      isBackground: ClaudeSession.isBackground(entrypoint: file.entrypoint),
                      host: host, lastPrompt: prompt)
    }

    private func host(of pid: Int32) -> HostApp? {
        if let known = hosts[pid] { return known }
        let found = hostApp(pid)
        hosts[pid] = found
        return found
    }

    /// The project folder is named after the session's working directory, with every character
    /// but letters and digits replaced: rebuilding that name would break on the first change of
    /// rule, so the folder is looked for instead. It holds the session's transcript and, once it
    /// launches one, a folder for its agents.
    private func projectFolder(of session: String) -> URL? {
        let manager = FileManager.default
        if let known = folders[session], manager.fileExists(atPath: known.path) { return known }
        for projects in projectsDirectories() {
            guard let projectFolders = try? manager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)
            else { continue }
            for project in projectFolders {
                let transcript = project.appendingPathComponent("\(session).jsonl")
                let own = project.appendingPathComponent(session, isDirectory: true)
                if manager.fileExists(atPath: transcript.path) || manager.fileExists(atPath: own.path) {
                    folders[session] = project
                    return project
                }
            }
        }
        return nil
    }

    /// Workflows nest their agents one folder deeper, hence the walk.
    private func transcriptURLs(in folder: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: folder.path),
              let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-") }
    }

    // MARK: - Last prompt

    /// The last thing the user typed in a session, read from its transcript: the first time from
    /// `promptLookback` before its end, then only what was appended.
    private func lastPrompt(in url: URL) -> String? {
        let currentID = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier as? NSObject
        var state = prompts[url] ?? PromptCursor(fileID: currentID)
        defer { prompts[url] = state }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return state.prompt }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0

        let replaced = state.fileID != nil && currentID != nil && !state.fileID!.isEqual(currentID)
        if replaced || size < state.offset { state = PromptCursor(fileID: currentID) }

        let floor = size > Self.promptLookback ? size - Self.promptLookback : 0
        let start = max(state.offset, floor)
        guard size > start,
              (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return state.prompt }

        var (lines, consumed) = Self.lines(in: data)
        // Jumping ahead lands anywhere in a line: what comes before the first newline is not one.
        if start > state.offset, start > 0 {
            let firstNewline = data.firstIndex(of: 0x0A) ?? data.endIndex
            lines.removeAll { $0.lowerBound <= firstNewline }
        }
        state.offset = start + UInt64(consumed)
        for range in lines where Self.holds(Self.lastPromptMarker, data, range) || Self.holds(Self.userMarker, data, range) {
            if let prompt = Self.prompt(from: data.subdata(in: range)) { state.prompt = prompt }
        }
        return state.prompt
    }

    private static let userMarker: [UInt8] = Array("\"type\":\"user\"".utf8)
    private static let lastPromptMarker: [UInt8] = Array("\"type\":\"last-prompt\"".utf8)

    /// What the user typed, from one transcript line. Claude Code writes it down itself, often, in
    /// a `last-prompt` line; failing that, a user message that is neither a tool result, nor what
    /// Claude Code adds on its own (reminders, the IDE's context, slash command echoes, all in
    /// tags), nor an interruption notice, nor a summary of a compacted conversation.
    static func prompt(from line: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        if object["type"] as? String == "last-prompt" {
            return (object["lastPrompt"] as? String).flatMap { typed([$0]) }
        }
        guard object["type"] as? String == "user",
              object["isMeta"] as? Bool != true, object["isSidechain"] as? Bool != true,
              object["isCompactSummary"] as? Bool != true,
              let message = object["message"] as? [String: Any] else { return nil }
        let texts: [String]
        if let content = message["content"] as? String {
            texts = [content]
        } else if let blocks = message["content"] as? [[String: Any]] {
            guard !blocks.contains(where: { $0["type"] as? String == "tool_result" }) else { return nil }
            texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        } else {
            return nil
        }
        return typed(texts)
    }

    /// The last of these texts a person typed, on one line, cut past `promptLength`.
    private static func typed(_ texts: [String]) -> String? {
        let typed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty && !$0.hasPrefix("<") && !$0.hasPrefix("[Request interrupted") }
        guard let typed else { return nil }
        let oneLine = typed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return oneLine.count > promptLength ? String(oneLine.prefix(promptLength)) + "…" : oneLine
    }

    // MARK: - One agent

    private func agent(at url: URL, in session: ClaudeSession, now: Date) -> RunningAgent? {
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
        return RunningAgent(id: id, sessionID: session.id, sessionPID: session.pid,
                            sessionStartedAt: session.processStartedAt, sessionName: session.name, title: title,
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
        holds(toolUseMarker, data, range)
    }

    private static func holds(_ marker: [UInt8], _ data: Data, _ range: Range<Int>) -> Bool {
        data.withUnsafeBytes { raw in
            guard let bytes = raw.baseAddress else { return false }
            return marker.withUnsafeBytes { marker in
                memmem(bytes + range.lowerBound, range.count, marker.baseAddress, marker.count) != nil
            }
        }
    }
}
