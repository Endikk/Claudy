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
    /// `message.id:requestId`. Claude Code writes the same response across several lines, one per
    /// content block; without this key every response would be counted several times. `nil` means
    /// no identifiers, so the line counts on its own.
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
/// Reads are synchronous and block a cooperative-pool thread: about two seconds on the first pass
/// over a 900 MB history, a few milliseconds afterwards. A deliberate trade-off.
actor TranscriptScanner {

    /// Window kept in memory. The widest view is seven days; the margin absorbs time-zone
    /// offsets and weeks that straddle a boundary.
    private let retention: TimeInterval = 9 * 86_400

    /// Read state for one file. Responses are attached to their file so they can be purged if it
    /// is truncated or replaced.
    private struct FileState {
        var offset: UInt64
        /// File identifier (inode): detects a replacement of equal or greater size.
        var fileID: NSObject?
        /// Responses read so far, by `dedupKey`. One without identifiers is keyed by file name and
        /// byte offset: apart from every other line, yet one key for a copy of the same transcript.
        var responses: [String: TranscriptEntry]
        var lastSeen: Date
    }

    private var files: [URL: FileState] = [:]

    private var resolver = ProjectResolver()
    private let projectsDirectories: () -> [URL]

    init(projectsDirectories: @escaping () -> [URL] = { ClaudeHome.projectsDirectories }) {
        self.projectsDirectories = projectsDirectories
    }

    private var skippedLines = 0
    private var warnedUsageKeys: Set<String> = []


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
        for (url, state) in files {
            files[url]?.responses = state.responses.filter { $0.value.date >= cutoff }
        }

        var all = assignProjects(uniqueResponses())
        all.sort { $0.date < $1.date }

        if skippedLines > 0 {
            NSLog("[Claudy] Skipped %d unreadable transcript line(s).", skippedLines)
        }
        return all
    }

    /// One entry per response across every file: a resumed session (`--resume`) rewrites the same
    /// responses into another transcript. Settled here rather than while reading, so the result
    /// does not depend on the order the disk lists files in, and a file rewritten without a
    /// response cannot take it away from the other file holding it.
    private func uniqueResponses() -> [TranscriptEntry] {
        var unique: [String: TranscriptEntry] = [:]
        for state in files.values {
            for (key, entry) in state.responses {
                if let held = unique[key], !Self.isMoreComplete(entry, than: held) { continue }
                unique[key] = entry
            }
        }
        return Array(unique.values)
    }

    /// Claude Code streams a response over several lines, one per content block, and the early
    /// ones carry the output count reached so far: keeping the first line undercounted output by
    /// about 40 %. Counters only grow, so the largest copy is the final one. Ties go to the
    /// earliest copy, then to the session name, so the choice never depends on reading order.
    private static func isMoreComplete(_ candidate: TranscriptEntry, than held: TranscriptEntry) -> Bool {
        if candidate.tokens != held.tokens { return candidate.tokens > held.tokens }
        if candidate.date != held.date { return candidate.date < held.date }
        return candidate.sessionID < held.sessionID
    }

    /// Transcripts under every projects folder. Each folder is resolved first: `projects` moved to
    /// another disk behind a symbolic link would otherwise read as empty, since the enumerator
    /// does not follow a link at its root. Two paths leading to one folder are read once.
    ///
    /// The first folder that exists must be readable, or the error surfaces. Any later one is a
    /// fallback: a permission quirk there must not blank a folder that reads fine.
    private func transcriptURLs(modifiedSince cutoff: Date) throws -> [URL] {
        var visited: Set<String> = []
        var found: [URL] = []
        var hasReadAFolder = false
        for folder in projectsDirectories() {
            let root = folder.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: root.path),
                  visited.insert(root.path).inserted else { continue }
            do {
                found += try transcriptURLs(in: root, modifiedSince: cutoff)
                hasReadAFolder = true
            } catch UsageDataError.projectsUnreadable where hasReadAFolder {
                NSLog("[Claudy] Skipped unreadable transcripts folder %@.", root.path)
            }
        }
        return found
    }

    private func transcriptURLs(in root: URL, modifiedSince cutoff: Date) throws -> [URL] {
        let manager = FileManager.default
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

        var state = files[url] ?? FileState(offset: 0, fileID: currentID, responses: [:], lastSeen: now)
        state.lastSeen = now
        defer { files[url] = state }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0

        let replaced = state.fileID != nil && currentID != nil && !state.fileID!.isEqual(currentID)
        if replaced || size < state.offset {
            state.offset = 0
            state.responses = [:]
            state.fileID = currentID
        }
        if state.fileID == nil { state.fileID = currentID }

        guard size > state.offset,
              (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return }

        let (lines, consumed) = Self.usageLines(in: data)
        let base = state.offset
        state.offset += UInt64(consumed)

        for range in lines {
            switch parse(data.subdata(in: range)) {
            case .entry(let entry):
                guard entry.date >= cutoff else { continue }
                let key = entry.dedupKey ?? "\(url.lastPathComponent)@\(base + UInt64(range.lowerBound))"
                if let held = state.responses[key], !Self.isMoreComplete(entry, than: held) { continue }
                state.responses[key] = entry
            case .malformed:
                skippedLines += 1
            case .irrelevant:
                continue
            }
        }
    }

    /// The lines of `data` holding a `"usage"` block, as byte ranges, and how many bytes were
    /// consumed. Every complete line is. The tail after the last newline is either a write in
    /// progress, left for the next pass, or a final line lacking its newline, taken when its
    /// JSON parses.
    ///
    /// Most lines (prompts, attachments, snapshots) carry no usage block, so they are skipped with
    /// `memchr` and `memmem` before any parsing. The generic `Data.split` and `range(of:)` did the
    /// same work several times slower: over three seconds on a 900 MB history.
    ///
    /// Ranges count from the first byte, so `data` must start at index 0, as `readToEnd` gives it.
    private static func usageLines(in data: Data) -> (lines: [Range<Int>], consumed: Int) {
        data.withUnsafeBytes { raw -> ([Range<Int>], Int) in
            guard let bytes = raw.baseAddress else { return ([], 0) }
            var lines: [Range<Int>] = []
            var lineStart = 0
            while lineStart < raw.count,
                  let newline = memchr(bytes + lineStart, 0x0A, raw.count - lineStart) {
                let lineEnd = bytes.distance(to: UnsafeRawPointer(newline))
                if holdsUsage(bytes + lineStart, lineEnd - lineStart) { lines.append(lineStart..<lineEnd) }
                lineStart = lineEnd + 1
            }
            guard lineStart < raw.count else { return (lines, raw.count) }

            let tail = Data(bytes: bytes + lineStart, count: raw.count - lineStart)
            guard (try? JSONSerialization.jsonObject(with: tail)) != nil else { return (lines, lineStart) }
            if holdsUsage(bytes + lineStart, raw.count - lineStart) { lines.append(lineStart..<raw.count) }
            return (lines, raw.count)
        }
    }

    private static let usageMarker: [UInt8] = Array("\"usage\"".utf8)

    private static func holdsUsage(_ bytes: UnsafeRawPointer, _ count: Int) -> Bool {
        usageMarker.withUnsafeBytes { marker in
            memmem(bytes, count, marker.baseAddress, marker.count) != nil
        }
    }

    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)

    // MARK: - Timestamps

    /// A line's `timestamp`. Claude Code writes `2026-09-24T07:05:12.345Z`, which is read here
    /// digit by digit: `ISO8601DateFormatter` costs some forty microseconds a date, close to two
    /// seconds over a large history. Any other form, an offset for one, goes to the formatters,
    /// which stay this actor's own.
    func timestamp(_ stamp: String) -> Date? {
        Self.utcTimestamp(stamp) ?? withFraction.date(from: stamp) ?? withoutFraction.date(from: stamp)
    }

    private let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let withoutFraction = ISO8601DateFormatter()

    /// Digits of a fraction of a second read here; nanoseconds are more than a transcript holds,
    /// and a longer run would overflow. Anything longer goes to the formatters.
    private static let maxFractionDigits = 9

    /// `YYYY-MM-DDTHH:MM:SS[.fraction]Z`, or nil for anything else, an impossible date included.
    private static func utcTimestamp(_ stamp: String) -> Date? {
        let bytes = Array(stamp.utf8)
        guard bytes.count >= 20, bytes.last == UInt8(ascii: "Z"),
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"), bytes[10] == UInt8(ascii: "T"),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":") else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(bytes[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              (1...12).contains(month), (1...daysIn(month, of: year)).contains(day),
              hour < 24, minute < 60, second < 60 else { return nil }

        var fraction = 0.0
        if bytes.count > 20 {
            let count = bytes.count - 21
            guard bytes[19] == UInt8(ascii: "."), (1...maxFractionDigits).contains(count),
                  let digits = number(20..<(bytes.count - 1)) else { return nil }
            fraction = Double(digits) / pow(10, Double(count))
        }
        let seconds = daysSinceEpoch(year: year, month: month, day: day) * 86_400
            + hour * 3_600 + minute * 60 + second
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    private static func daysIn(_ month: Int, of year: Int) -> Int {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days from 1970-01-01 to a Gregorian date (Howard Hinnant's `days_from_civil`).
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

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
              let date = timestamp(stamp)
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
