import Foundation

/// Runs a short-lived command and returns its standard output.
///
/// Absolute executable path and an argument array only: no shell is ever involved, so no
/// string built here can be reinterpreted as a command. The timeout matters as much as the
/// result — a scan that hangs would freeze the widget's refresh.
enum Subprocess {
    /// `acceptedStatuses` exists for tools that report "nothing matched" as a non-zero exit —
    /// lsof returns 1 on an empty result, which is an answer, not a failure.
    static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval,
        acceptedStatuses: Set<Int32> = [0]
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            DiagnosticLog.append("subprocess: could not launch \(executable)")
            return nil
        }

        var data = Data()
        let reader = DispatchQueue(label: "com.claudy.subprocess.read")
        let finished = DispatchSemaphore(value: 0)
        reader.async {
            data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
            finished.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            DiagnosticLog.append("subprocess: \(executable) timed out")
            return nil
        }
        process.waitUntilExit()

        guard acceptedStatuses.contains(process.terminationStatus) else {
            DiagnosticLog.append("subprocess: \(executable) exited \(process.terminationStatus)")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
