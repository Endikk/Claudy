import Foundation

/// Reads the Claude Code markers out of a process's environment.
///
/// The environment is inherited by every descendant and outlives the session that created it,
/// so it is the only attribution signal that still holds once launchd has reparented an
/// orphaned server. A process environment routinely carries tokens: nothing but the presence
/// flag and the project directory ever leaves this type.
enum ProcessEnvironment {

    struct Markers: Equatable {
        let isClaude: Bool
        let projectDirectory: String?
    }

    static func markers(pid: pid_t) -> Markers? {
        guard let raw = procArgs(pid: pid) else { return nil }
        return parse(raw)
    }

    /// `KERN_PROCARGS2` layout: argc, the executable path, padding NULs, then exactly argc
    /// arguments, then the environment. The arguments are skipped by counting, never by
    /// searching: a command line containing `CLAUDECODE=1` would otherwise attribute a process
    /// that Claude never launched.
    static func parse(_ raw: [UInt8]) -> Markers? {
        guard raw.count > 4 else { return nil }

        let argc = Int(UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24)
        guard argc >= 0 else { return nil }

        var index = 4
        while index < raw.count, raw[index] != 0 { index += 1 }
        while index < raw.count, raw[index] == 0 { index += 1 }

        var skipped = 0
        while skipped < argc, index < raw.count {
            while index < raw.count, raw[index] != 0 { index += 1 }
            index += 1
            skipped += 1
        }
        guard skipped == argc else { return nil }

        var isClaude = false
        var projectDirectory: String?
        var start = index

        while index <= raw.count {
            let isEnd = index == raw.count
            if isEnd || raw[index] == 0 {
                if start < index {
                    let entry = String(decoding: raw[start..<index], as: UTF8.self)
                    if entry.hasPrefix("CLAUDECODE=") || entry.hasPrefix("CLAUDE_CODE_ENTRYPOINT=") {
                        isClaude = true
                    } else if let value = entry.dropPrefix("CLAUDE_PROJECT_DIR=") {
                        isClaude = true
                        projectDirectory = value
                    }
                }
                start = index + 1
            }
            index += 1
        }

        return Markers(isClaude: isClaude, projectDirectory: projectDirectory)
    }

    /// The buffer is sized from `kern.argmax`: asking `sysctl` for the size of
    /// `KERN_PROCARGS2` is not supported and fails with EINVAL.
    private static func procArgs(pid: pid_t) -> [UInt8]? {
        var argmaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        guard sysctl(&argmaxMib, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return nil }

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = Int(argmax)
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Array(buffer.prefix(size))
    }
}

private extension String {
    /// The value behind a `KEY=` prefix, or nil when the prefix does not match.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
