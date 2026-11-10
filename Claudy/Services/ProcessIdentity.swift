import Darwin
import Foundation

/// What the kernel says about a process Claudy only knows by pid: whether it runs, when it
/// started, which binary it is. A pid is reused once its process exits, so the pid in a session
/// file says little on its own; the start time the file records tells the two apart.
enum ProcessIdentity {

    /// `kill` with no signal only asks whether the process exists. `EPERM` means it does, under
    /// another user.
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// When the process started, from the kernel's own record; nil when it is gone or not ours.
    static func startDate(of pid: Int32) -> Date? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                    + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    /// The path of the binary the process runs; nil when it is gone or not ours.
    static func executablePath(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        // `PROC_PIDPATHINFO_MAXSIZE` is a macro Swift does not see: four times `MAXPATHLEN`.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Start times agree within this: the session file writes whole seconds.
    static let startTolerance: TimeInterval = 2

    /// The process a session file describes still runs: alive, started when the file says, or,
    /// for a file that says nothing, a Claude Code binary. Pid 0 and 1 are never a session.
    static func isSession(pid: Int32, startedAt: Date?) -> Bool {
        guard pid > 1, isAlive(pid) else { return false }
        if let startedAt {
            guard let actual = startDate(of: pid) else { return false }
            return matches(actual, startedAt)
        }
        guard let path = executablePath(of: pid) else { return false }
        return ProcessTable.isClaudeBinary(path) || (path as NSString).lastPathComponent == "node"
    }

    /// The file's start time is read as UTC, which is what Claude Code writes on this Mac. Read as
    /// local time too, in case another build writes the clock it shows: the hour's shift between
    /// the two is far larger than the tolerance, so a reused pid still never matches both.
    static func matches(_ actual: Date, _ recorded: Date) -> Bool {
        if abs(actual.timeIntervalSince(recorded)) <= startTolerance { return true }
        let offset = TimeInterval(TimeZone.current.secondsFromGMT(for: recorded))
        return abs(actual.timeIntervalSince(recorded.addingTimeInterval(-offset))) <= startTolerance
    }

    /// Sends a signal; 0 on success, else `errno`: `ESRCH` for a process that is gone, `EPERM`
    /// for another user's.
    static func send(_ signal: Int32, to pid: Int32) -> Int32 {
        guard pid > 1 else { return EINVAL }
        return kill(pid, signal) == 0 ? 0 : errno
    }

    /// The `procStart` of a session file, written as `ctime` does: "Mon Nov  9 22:26:03 2026".
    /// Claude Code writes it in UTC: checked against the kernel's start times of the sessions
    /// open on this Mac, which were one hour off the local reading and on the UTC one.
    static func date(fromProcStart text: String) -> Date? {
        let collapsed = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return procStartFormatter.date(from: collapsed)
    }

    private static let procStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()
}
