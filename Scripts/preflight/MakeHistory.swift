// Writes a synthetic Claude Code history for the pre-release checks: session transcripts under
// `<out>/projects/`, shaped like real ones, so the first read can be timed at any size without
// anybody's own data.
//
//   swiftc -O MakeHistory.swift -o make-history && ./make-history <out> <megabytes>
//
// What matters for timing is kept from real histories: most bytes sit in lines with no usage
// block (tool results, file snapshots), each response is written twice (a partial output count,
// then the final one), subagents write their own files, and timestamps span the last seven days.
// A given size always gives the same history, dated from the moment it is written.

import Foundation

guard CommandLine.arguments.count == 3, let megabytes = Int(CommandLine.arguments[2]), megabytes > 0 else {
    FileHandle.standardError.write(Data("usage: make-history <out> <megabytes>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let projects = out.appendingPathComponent("projects", isDirectory: true)
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

/// Small deterministic generator: the same size gives the same history.
struct Random {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}

var random = Random(state: UInt64(megabytes))
let words = ["claudy", "quota", "session", "token", "window", "swift", "actor", "scanner", "history",
             "transcript", "refresh", "keychain", "menu", "widget", "pace", "gauge", "build", "test"]
let models = ["claude-opus-5", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"]

/// JSON-safe prose of about `bytes` bytes, with the escapes real content carries.
func prose(_ bytes: Int) -> String {
    var text = ""
    text.reserveCapacity(bytes + 16)
    while text.utf8.count < bytes {
        text += words[random.int(0...(words.count - 1))]
        text += random.int(0...9) == 0 ? "\\n" : (random.int(0...19) == 0 ? " \\\"quoted\\\" " : " ")
    }
    return text
}

let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

let target = megabytes * 1_000_000
let now = Date()
var written = 0
var responses = 0
var sessionIndex = 0

while written < target {
    sessionIndex += 1
    let project = "-Users-preflight-Dev-project\(sessionIndex % 12)"
    let session = String(format: "%08x-0000-4000-8000-%012x", sessionIndex, sessionIndex * 7919)
    let cwd = "/Users/preflight/Dev/project\(sessionIndex % 12)"
    let isSubagent = sessionIndex % 4 == 0
    let directory = isSubagent
        ? projects.appendingPathComponent("\(project)/\(session)/subagents", isDirectory: true)
        : projects.appendingPathComponent(project, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(isSubagent ? "agent-\(session).jsonl" : "\(session).jsonl")

    var body = ""
    var time = now.addingTimeInterval(-Double(random.int(60...(7 * 86_400 - 3_600))))
    let length = random.int(10...120)
    for turn in 0..<length where written + body.utf8.count < target {
        time = min(time.addingTimeInterval(Double(random.int(2...90))), now.addingTimeInterval(-30))
        let stamp = iso.string(from: time)
        let model = models[random.int(0...(models.count - 1))]
        let messageID = "msg_\(sessionIndex)_\(turn)"
        let requestID = "req_\(sessionIndex)_\(turn)"
        let input = random.int(1...40)
        let cacheRead = random.int(10_000...180_000)
        let cacheWrite = random.int(0...40_000)
        let output = random.int(20...4_000)

        // Tool result: the bulk of a history, and never a usage block.
        body += #"{"parentUuid":null,"isSidechain":\#(isSubagent),"type":"user","cwd":"\#(cwd)","sessionId":"\#(session)","message":{"role":"user","content":[{"type":"tool_result","content":"\#(prose(random.int(500...50_000)))"}]},"timestamp":"\#(stamp)"}"# + "\n"
        if turn % 3 == 0 {
            body += #"{"type":"file-history-snapshot","messageId":"\#(messageID)","snapshot":{"trackedFileBackups":{"a.swift":"\#(prose(random.int(5_000...50_000)))"}},"isSnapshotUpdate":false}"# + "\n"
        }
        // One response, written twice: early lines carry a partial output count.
        for (index, count) in [(0, min(output, 4)), (1, output)] {
            body += #"{"parentUuid":null,"isSidechain":\#(isSubagent),"type":"assistant","cwd":"\#(cwd)","sessionId":"\#(session)","requestId":"\#(requestID)","message":{"id":"\#(messageID)","type":"message","role":"assistant","model":"\#(model)","content":[{"type":"text","text":"\#(prose(random.int(800...5_000)))"}],"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead),"cache_creation":{"ephemeral_5m_input_tokens":\#(cacheWrite),"ephemeral_1h_input_tokens":0},"output_tokens":\#(count),"service_tier":"standard"}},"uuid":"u\#(index)","timestamp":"\#(stamp)"}"# + "\n"
        }
        responses += 1
    }
    try Data(body.utf8).write(to: file)
    written += body.utf8.count
}

print("\(written / 1_000_000) MB, \(responses) responses, \(sessionIndex) files in \(projects.path)")
