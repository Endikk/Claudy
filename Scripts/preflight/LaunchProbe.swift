// Launches Claudy and times what its card shows, for the pre-release checks.
//
//   swiftc -O LaunchProbe.swift -o launch-probe
//   ./launch-probe <Claudy binary> <report.json> <config dir> [--switch]
//
// Claudy runs as a widget on a stand-in Claude folder (`claudy.configDir`), so nobody's account or
// preferences are touched: launch arguments only live for the process. With no token in that
// folder it shows the sign-in card. With `--switch`, a session file is then dropped into the
// folder, as Claude Code writes one when it signs in, and the probe times how long the card takes
// to leave the sign-in screen on its own. The token is fake: Anthropic answers 401, and the card
// shows its gauges empty, which is enough to prove the switch.
//
// Only window sizes are read, never their content, so no screen-recording permission is needed.

import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write(Data("usage: launch-probe <binary> <report.json> <config dir> [--switch]\n".utf8))
    exit(2)
}
let binary = arguments[1]
let report = URL(fileURLWithPath: arguments[2])
let config = URL(fileURLWithPath: arguments[3], isDirectory: true)
let switchesSession = arguments.contains("--switch")
let timeout: TimeInterval = 30

let app = Process()
app.executableURL = URL(fileURLWithPath: binary)
app.arguments = ["-claudy.inMenuBar", "NO", "-claudy.isMinimal", "NO", "-claudy.configDir", config.path]
var environment = ProcessInfo.processInfo.environment
environment["CLAUDY_LOG_DIRECTORY"] = config.appendingPathComponent("logs").path
app.environment = environment

/// The card's window, as `width x height` in points, or nil before it shows.
func cardSize(of pid: pid_t) -> (width: Int, height: Int)? {
    let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = Int((bounds["Width"] as? Double) ?? 0), height = Int((bounds["Height"] as? Double) ?? 0)
        if width > 120, height > 40 { return (width, height) }
    }
    return nil
}

/// Loading card and minimal strip are short; the sign-in card and the full card are tall.
let tallCard = 300

let start = Date()
try app.run()
var timeline: [[String: Any]] = []
var lastSize = ""
var cardAt: Double?
var signInSize = ""
var droppedAt: Double?
var switchedAt: Double?

while Date().timeIntervalSince(start) < timeout, app.isRunning {
    let now = Date().timeIntervalSince(start)
    if let size = cardSize(of: app.processIdentifier) {
        let label = "\(size.width)x\(size.height)"
        if label != lastSize {
            timeline.append(["seconds": now, "size": label])
            lastSize = label
        }
        if cardAt == nil, size.height >= tallCard {
            cardAt = now
            signInSize = label
        }
        if switchesSession, cardAt != nil, droppedAt == nil, now - (cardAt ?? now) > 1 {
            let expires = Int((Date().timeIntervalSince1970 + 3_600) * 1_000)
            let session = #"{"claudeAiOauth":{"accessToken":"preflight-not-a-real-token","expiresAt":\#(expires)}}"#
            try Data(session.utf8).write(to: config.appendingPathComponent(".credentials.json"))
            droppedAt = now
        }
        if let droppedAt, switchedAt == nil, size.height >= tallCard, label != signInSize {
            switchedAt = now - droppedAt
        }
    }
    if cardAt != nil, !switchesSession || switchedAt != nil { break }
    usleep(50_000)
}

app.terminate()
app.waitUntilExit()

var result: [String: Any] = ["timeline": timeline, "cardSize": signInSize]
if let cardAt { result["cardSeconds"] = cardAt }
if let switchedAt { result["switchSeconds"] = switchedAt }
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: report)
print(String(data: try Data(contentsOf: report), encoding: .utf8) ?? "")
