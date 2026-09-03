import Foundation

struct RunningProcess: Equatable {
    let pid: pid_t
    let parent: pid_t
    /// Start time, which turns a reusable PID into a stable identity.
    let startedAt: Date
    let arguments: String
}

/// A snapshot of the process tree, read in one `ps` pass.
///
/// Attribution does not depend on this table — the environment carries that. The tree serves
/// one purpose: knowing which Claude session is still alive, so the reaper never kills it.
struct ProcessTable {
    let processes: [pid_t: RunningProcess]

    private static let maximumDepth = 64

    private static let executable = "/bin/ps"
    private static let arguments = ["-Ao", "pid=,ppid=,lstart=,args="]
    private static let timeout: TimeInterval = 4

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()

    static func load() -> ProcessTable? {
        guard let output = Subprocess.run(executable, arguments, timeout: timeout) else {
            DiagnosticLog.append("ports: ps failed")
            return nil
        }
        return parse(output)
    }

    /// `lstart` is five whitespace-separated tokens (`Thu Sep  3 19:31:02 2026`), so the split
    /// is positional: pid, ppid, five date tokens, then the argument string verbatim.
    static func parse(_ output: String) -> ProcessTable {
        var processes: [pid_t: RunningProcess] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            var scanner = line.drop { $0 == " " }
            guard let pid = scanner.takeInteger(), let parent = scanner.takeInteger() else { continue }

            var dateTokens: [String] = []
            for _ in 0..<5 {
                guard let token = scanner.takeToken() else { break }
                dateTokens.append(token)
            }
            guard dateTokens.count == 5,
                  let startedAt = dateFormatter.date(from: dateTokens.joined(separator: " "))
            else { continue }

            let arguments = String(scanner.drop { $0 == " " })
            processes[pid] = RunningProcess(pid: pid, parent: parent, startedAt: startedAt, arguments: arguments)
        }

        return ProcessTable(processes: processes)
    }

    /// Ancestors from the closest parent upward. Depth-capped: a malformed table must never
    /// spin the scan.
    func ancestors(of pid: pid_t) -> [RunningProcess] {
        var found: [RunningProcess] = []
        var seen: Set<pid_t> = [pid]
        var current = processes[pid]?.parent

        while let parent = current, parent > 1, found.count < Self.maximumDepth, !seen.contains(parent) {
            guard let process = processes[parent] else { break }
            found.append(process)
            seen.insert(parent)
            current = process.parent
        }
        return found
    }

    /// The live Claude session a process belongs to, when there is one.
    func claudeSessionRoot(of pid: pid_t) -> RunningProcess? {
        ancestors(of: pid).first { Self.isClaudeBinary($0.arguments) }
    }

    static func isClaudeBinary(_ arguments: String) -> Bool {
        let path = arguments.split(separator: " ", maxSplits: 1).first.map(String.init) ?? arguments
        if (path as NSString).lastPathComponent == "claude" { return true }
        return path.contains("anthropic.claude-code") || path.contains("@anthropic-ai/claude-code")
    }
}

private extension Substring {
    mutating func takeToken() -> String? {
        self = drop { $0 == " " }
        guard let end = firstIndex(of: " ") else {
            guard !isEmpty else { return nil }
            defer { self = self[endIndex...] }
            return String(self)
        }
        let token = String(self[startIndex..<end])
        self = self[end...]
        return token
    }

    mutating func takeInteger() -> pid_t? {
        guard let token = takeToken(), let value = pid_t(token) else { return nil }
        return value
    }
}
