import Foundation

/// The last seven days of usage as a CSV file: one line per local hour, project and model, for a
/// spreadsheet or a script. Built from the local transcripts alone.
///
/// The file must read the same on every Mac: dates are Gregorian whatever the user's calendar,
/// prices take a point whatever their locale, and a folder name never runs as a formula.
enum UsageExport {

    static let header = "hour,project,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,list_price_usd"

    /// How far back the export reaches: the week the card shows. The scanner keeps nine days in
    /// memory, so the whole window is there.
    static let window: TimeInterval = 7 * 86_400

    /// One line of the file.
    struct Row: Equatable {
        /// Local hour, `2026-11-10T09:00`.
        let hour: String
        /// The project's display name, as the card shows it.
        let project: String
        /// The raw model id.
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int
        /// What the tokens weigh in dollars at list price: the sum of `TranscriptEntry.weight`.
        let listPrice: Double
    }

    /// The file for `entries`. `calendar` gives the time zone the hours are read in.
    static func csv(from entries: [TranscriptEntry], now: Date, calendar: Calendar) -> String {
        csv(rows(from: entries, now: now, calendar: calendar))
    }

    /// Header first, one line per row, each ending in `\n`.
    static func csv(_ rows: [Row]) -> String {
        let lines = rows.map { row in
            [
                row.hour, row.project, row.model,
                String(row.inputTokens), String(row.outputTokens),
                String(row.cacheReadTokens), String(row.cacheWriteTokens),
                // `String(format:)` takes no locale, so the separator is a point even in France.
                String(format: "%.4f", row.listPrice),
            ].map(escape).joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\n") + "\n"
    }

    /// The responses of the last seven days, summed per local hour, project and model, sorted in
    /// that order. A project's name is settled over every project the export holds, so `work/api`
    /// and `personal/api` keep their prefix even in an hour where only one of them worked.
    static func rows(from entries: [TranscriptEntry], now: Date, calendar: Calendar) -> [Row] {
        let cutoff = now.addingTimeInterval(-window)
        let recent = entries.filter { $0.date >= cutoff }
        // `displayNames` builds its dictionary from unique keys: a path listed twice would trap.
        let names = UsageAggregator.displayNames(for: Array(Set(recent.map(\.project))))
        let hours = formatter("yyyy-MM-dd'T'HH':00'", timeZone: calendar.timeZone)

        // Grouped by the hour as written, not by the instant: the hour repeated when clocks go
        // back in autumn stays one line, as a reader of the file would expect.
        let groups = Dictionary(grouping: recent) { entry in
            Key(hour: hours.string(from: entry.date), path: entry.project, model: entry.model)
        }
        return groups
            .map { key, entries in
                (path: key.path, row: Row(
                    hour: key.hour,
                    project: projectName(names[key.path] ?? key.path),
                    model: key.model,
                    inputTokens: entries.reduce(0) { $0 + $1.inputTokens },
                    outputTokens: entries.reduce(0) { $0 + $1.outputTokens },
                    cacheReadTokens: entries.reduce(0) { $0 + $1.cacheReadTokens },
                    cacheWriteTokens: entries.reduce(0) { $0 + $1.cacheWriteTokens },
                    listPrice: entries.reduce(0) { $0 + $1.weight }
                ))
            }
            // The path settles a tie between two projects whose names still match after the
            // parent prefix, so the file does not change from one export to the next.
            .sorted { ($0.row.hour, $0.row.project, $0.row.model, $0.path)
                < ($1.row.hour, $1.row.project, $1.row.model, $1.path) }
            .map { $0.row }
    }

    /// The card names a response with no folder "—"; a file reads better with the cell left empty.
    private static func projectName(_ name: String) -> String {
        name == "—" ? "" : name
    }

    /// `claudy-usage-2026-11-10.csv`, dated in the calendar's time zone.
    static func fileName(now: Date, calendar: Calendar) -> String {
        "claudy-usage-\(formatter("yyyy-MM-dd", timeZone: calendar.timeZone).string(from: now)).csv"
    }

    /// A value as a CSV field. One holding a comma, a double quote or a line break is quoted, its
    /// quotes doubled. One starting with `=`, `+`, `-`, `@`, a tab or a carriage return takes a
    /// leading `'`, so a spreadsheet shows it as text instead of running it as a formula: folder
    /// names are the user's, and a cloned repository chooses its own.
    ///
    /// Read as Unicode scalars: Swift holds CR LF as a single `Character`, which equals neither
    /// CR nor LF and would slip through a test on characters.
    static func escape(_ value: String) -> String {
        let startsFormula = value.unicodeScalars.first.map(formulaStarts.contains) ?? false
        let guarded = startsFormula ? "'" + value : value
        guard guarded.unicodeScalars.contains(where: quotedScalars.contains) else { return guarded }
        return "\"" + guarded.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let formulaStarts: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
    private static let quotedScalars: Set<Unicode.Scalar> = [",", "\"", "\r", "\n"]

    private struct Key: Hashable {
        let hour: String
        let path: String
        let model: String
    }

    /// A fresh formatter per export: the time zone is the caller's, and an export is rare enough
    /// that caching one would buy nothing.
    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
