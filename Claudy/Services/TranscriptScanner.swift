import Foundation

/// One model response recorded in a transcript.
struct TranscriptEntry {
    let date: Date
    let model: String
    let tokens: Int
    /// What the tokens weigh against the quota, in dollars at list price. Cache reads are
    /// most of the volume but cost a tenth of an input token, and an Opus token five Haiku
    /// ones: ranking by raw tokens put a background Haiku job above real work.
    let weight: Double
    /// Directory the model was working in.
    let cwd: String
    /// Project the response belongs to: a repository root path, or the directory itself when
    /// no repository holds it. Resolved by `scan()` once the whole session is known.
    var project: String
    let sessionID: String
    /// A subagent response. Its tokens count, but it is not a user session.
    let isSidechain: Bool
    /// `message.id:requestId`. Claude Code rewrites the same response across several lines, one
    /// per content block, with an identical `usage` block; without this key every response would
    /// be counted several times. `nil` means no identifiers, so it is always counted.
    let dedupKey: String?
}

/// Reads the `<config>/projects/**/*.jsonl` transcripts: the main sessions, and below them the
/// subagent and workflow transcripts (`<session>/subagents/**/agent-*.jsonl`), which hold more
/// than half of the tokens on an agent-heavy week.
///
/// Transcripts only ever grow, so the scanner keeps a cursor per file and re-reads only the tail
/// appended since the previous pass. Without that, refreshing every few minutes would re-read
/// hundreds of megabytes each time.
///
/// Reads are synchronous and block a cooperative-pool thread: a few seconds on the first pass
/// over a large history, a few milliseconds afterwards. A deliberate trade-off.
actor TranscriptScanner {

    /// Window kept in memory. The widest view is seven days; the margin absorbs time-zone
    /// offsets and weeks that straddle a boundary.
    private let retention: TimeInterval = 9 * 86_400

    /// Read state for one file. Entries are attached to their file so they can be purged if it
    /// is truncated or replaced.
    private struct FileState {
        var offset: UInt64
        /// File identifier (inode): detects a replacement of equal or greater size.
        var fileID: NSObject?
        var entries: [TranscriptEntry]
        var lastSeen: Date
    }

    private var files: [URL: FileState] = [:]

    /// Keys already counted, global across files: a resumed session (`--resume`) rewrites the
    /// same responses into a different transcript.
    private var seenKeys: [String: (url: URL, date: Date)] = [:]

    private var resolver = ProjectResolver()
    private let projectsDirectory: () -> URL

    init(projectsDirectory: @escaping () -> URL = { ClaudeHome.projectsDirectory }) {
        self.projectsDirectory = projectsDirectory
    }

    private var skippedLines = 0
    private var warnedUsageKeys: Set<String> = []

    private let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Every response recorded over the retention window, oldest first.
    func scan() throws -> [TranscriptEntry] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-retention)
        skippedLines = 0

        let discovered = try transcriptURLs(modifiedSince: cutoff)
        for url in discovered {
            ingest(url, cutoff: cutoff, now: now)
        }

        let discoveredSet = Set(discovered)
        for (url, state) in files where !discoveredSet.contains(url) && state.lastSeen < cutoff {
            files.removeValue(forKey: url)
        }
        seenKeys = seenKeys.filter { $0.value.date >= cutoff }
        for url in files.keys {
            files[url]?.entries.removeAll { $0.date < cutoff }
        }

        var all = assignProjects(files.values.flatMap(\.entries))
        all.sort { $0.date < $1.date }

        if skippedLines > 0 {
            NSLog("[Claudy] Skipped %d unreadable transcript line(s).", skippedLines)
        }
        return all
    }

    private func transcriptURLs(modifiedSince cutoff: Date) throws -> [URL] {
        let manager = FileManager.default
        let root = projectsDirectory()
        guard manager.fileExists(atPath: root.path) else { return [] }
        guard manager.isReadableFile(atPath: root.path) else { throw UsageDataError.projectsUnreadable }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: keys,
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { throw UsageDataError.projectsUnreadable }

        var found: [URL] = []
        for case let file as URL in walker where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if let modified = values?.contentModificationDate, modified < cutoff { continue }
            found.append(file)
        }
        return found
    }

    /// Attributes each response to a repository. A directory outside any repository (the
    /// scratchpad a session `cd`s into, a deleted temporary folder) takes the repository the
    /// rest of its session worked in, and only failing that stands as a project of its own.
    private func assignProjects(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
        var roots: [String: String?] = [:]
        for cwd in Set(entries.map(\.cwd)) { roots[cwd] = resolver.repositoryRoot(of: cwd) }

        var sessionWeights: [String: [String: Double]] = [:]
        for entry in entries {
            guard let root = roots[entry.cwd] ?? nil else { continue }
            sessionWeights[entry.sessionID, default: [:]][root, default: 0] += entry.weight
        }
        let sessionRoot = sessionWeights.compactMapValues { $0.max { $0.value < $1.value }?.key }

        return entries.map { entry in
            var resolved = entry
            resolved.project = (roots[entry.cwd] ?? nil) ?? sessionRoot[entry.sessionID] ?? entry.cwd
            return resolved
        }
    }

    private func ingest(_ url: URL, cutoff: Date, now: Date) {
        let currentID = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier as? NSObject

        var state = files[url] ?? FileState(offset: 0, fileID: currentID, entries: [], lastSeen: now)
        state.lastSeen = now
        defer { files[url] = state }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0

        let replaced = state.fileID != nil && currentID != nil && !state.fileID!.isEqual(currentID)
        if replaced || size < state.offset {
            state.offset = 0
            state.entries = []
            state.fileID = currentID
            seenKeys = seenKeys.filter { $0.value.url != url }
        }
        if state.fileID == nil { state.fileID = currentID }

        guard size > state.offset,
              (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return }

        // Only consume up to the last newline: a tail without one is either a write in
        // progress (retried next pass) or a final line lacking \n, taken only if its JSON parses.
        let complete: Data
        if let lastBreak = data.lastIndex(of: 0x0A) {
            complete = Data(data[data.startIndex...lastBreak])
        } else if (try? JSONSerialization.jsonObject(with: data)) != nil {
            complete = data
        } else {
            return
        }
        state.offset += UInt64(complete.count)

        for line in complete.split(separator: 0x0A) where !line.isEmpty {
            // Cheap filter before paying for JSON parsing: most transcript lines
            // (attachments, snapshots, prompts) carry no usage block at all.
            guard line.range(of: Self.usageMarker) != nil else { continue }

            switch parse(Data(line)) {
            case .entry(let entry):
                guard entry.date >= cutoff else { continue }
                if let key = entry.dedupKey {
                    if seenKeys[key] != nil { continue }
                    seenKeys[key] = (url, entry.date)
                }
                state.entries.append(entry)
            case .malformed:
                skippedLines += 1
            case .irrelevant:
                continue
            }
        }
    }

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)

    // MARK: - Parsing

    private enum ParseOutcome {
        case entry(TranscriptEntry)
        /// Valid line, but not relevant — not a countable assistant response.
        case irrelevant
        /// A line that should be an assistant response but will not parse: a format canary.
        case malformed
    }

    private func parse(_ line: Data) -> ParseOutcome {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return line.range(of: Self.assistantMarker) != nil ? .malformed : .irrelevant
        }
        guard root["type"] as? String == "assistant" else { return .irrelevant }
        guard let message = root["message"] as? [String: Any] else { return .malformed }
        guard let usage = message["usage"] as? [String: Any] else { return .irrelevant }
        guard let model = message["model"] as? String else { return .malformed }
        guard ModelName.isReal(model) else { return .irrelevant }
        guard let stamp = root["timestamp"] as? String,
              let date = isoWithFraction.date(from: stamp) ?? iso.date(from: stamp)
        else { return .malformed }

        warnAboutUnknownCounters(in: usage)

        func count(_ key: String, in object: [String: Any] = usage) -> Int {
            (object[key] as? NSNumber)?.intValue ?? 0
        }
        let input = count("input_tokens")
        let output = count("output_tokens")
        let cacheWrite = count("cache_creation_input_tokens")
        let cacheRead = count("cache_read_input_tokens")
        let tokens = input + output + cacheWrite + cacheRead
        guard tokens > 0 else { return .irrelevant }

        // A one-hour cache write costs twice the input price, a five-minute one 1.25 times. The
        // split is absent from older lines, which are priced as five-minute writes.
        let longWrites = (usage["cache_creation"] as? [String: Any])
            .map { count("ephemeral_1h_input_tokens", in: $0) } ?? 0
        let inputUnits = Double(input)
            + 5 * Double(output)
            + 1.25 * Double(max(cacheWrite - longWrites, 0)) + 2 * Double(longWrites)
            + 0.1 * Double(cacheRead)
        let weight = inputUnits * ModelName.inputPrice(model) / 1_000_000

        let cwd = (root["cwd"] as? String) ?? ""

        let messageID = message["id"] as? String
        let requestID = root["requestId"] as? String
        let dedupKey: String? = if let messageID, let requestID, !messageID.isEmpty, !requestID.isEmpty {
            "\(messageID):\(requestID)"
        } else {
            nil
        }

        return .entry(TranscriptEntry(
            date: date,
            model: model,
            tokens: tokens,
            weight: weight,
            cwd: cwd,
            project: cwd,
            sessionID: (root["sessionId"] as? String) ?? "",
            isSidechain: (root["isSidechain"] as? Bool) ?? false,
            dedupKey: dedupKey
        ))
    }

    /// Logs, once per key, any new numeric counter appearing in `usage`. `server_tool_use` and
    /// friends are known and deliberately ignored: they count requests (web search and the like),
    /// not tokens.
    private static let knownUsageKeys: Set<String> = [
        "input_tokens", "output_tokens",
        "cache_creation_input_tokens", "cache_read_input_tokens",
        "server_tool_use", "cache_creation", "service_tier",
        "speed", "iterations", "inference_geo",
    ]

    private func warnAboutUnknownCounters(in usage: [String: Any]) {
        for (key, value) in usage where value is NSNumber && !Self.knownUsageKeys.contains(key) {
            guard warnedUsageKeys.insert(key).inserted else { continue }
            NSLog("[Claudy] Unknown usage key in transcripts: %@ (ignored).", key)
        }
    }
}
