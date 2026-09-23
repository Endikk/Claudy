import Foundation

/// Turns raw readings into a displayable snapshot.
///
/// Percentages come from the account alone. Nothing is estimated: Anthropic's response carries
/// `limit_dollars: null`, so the quota is not a token tally and no local count could reproduce it.
/// Without a real quota the gauges declare themselves unmeasured and the UI shows "—". Local
/// transcripts keep one role only — the token detail, which describes *this machine*.
enum UsageAggregator {

    /// Length of the weekly quota window.
    private static let weeklyWindow: TimeInterval = 7 * 86_400

    /// Length of one Claude Code session window.
    static let sessionWindow: TimeInterval = 5 * 3600
    private static let day: TimeInterval = 86_400

    static func snapshot(from entries: [TranscriptEntry], account: Account,
                         reading: QuotaReading?, now: Date = Date()) -> UsageSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let source = reading?.source ?? .unavailable

        let session = sessionGauge(reading?.session, entries: entries, now: now, source: source)
        let weekly = weeklyGauge(reading?.weekly, entries: entries, now: now, source: source,
                                 title: "Weekly", accent: .amber, family: nil)

        let scopedName = reading?.scoped?.label
        let third = weeklyGauge(reading?.scoped, entries: entries, now: now, source: source,
                                title: scopedName ?? "Per model",
                                accent: ModelName.accent((scopedName ?? "").lowercased()),
                                family: scopedName?.lowercased())

        let rolling = entries.filter { $0.date >= now.addingTimeInterval(-7 * day) }
        let rollingTokens = rolling.reduce(0) { $0 + $1.tokens }

        return UsageSnapshot(
            session: session,
            weekly: weekly,
            sonnet: third,
            spend: spendGauge(reading?.spend, source: source),
            history: history(rolling, today: today, calendar: calendar),
            models: models(rolling),
            projects: projects(rolling),
            account: account,
            activeModel: dominantModel(entries, since: session.windowStart),
            todayTokens: entries.filter { $0.date >= today }.reduce(0) { $0 + $1.tokens },
            weekTokens: rollingTokens,
            sessionCount: Set(entries.filter { $0.date >= today && !$0.isSidechain }.map(\.sessionID)).count,
            updatedAt: now,
            quotaSource: source
        )
    }

    /// Five-hour window. The percentage is the account's, the tokens are this machine's, and the
    /// two never merge into one number.
    private static func sessionGauge(_ quota: QuotaWindow?, entries: [TranscriptEntry],
                                     now: Date, source: QuotaSource) -> UsageWindow {
        let block = currentLocalBlock(entries, now: now)
        guard let quota, source.isMeasured else {
            return UsageWindow(
                title: "Session", window: "5h",
                percent: 0, tokensUsed: block?.tokens ?? 0,
                windowStart: block?.start ?? now,
                resetDate: block?.end ?? now,
                accent: .coral,
                isMeasured: false
            )
        }

        let start = quota.resetsAt?.addingTimeInterval(-sessionWindow) ?? now
        return UsageWindow(
            title: "Session", window: "5h",
            percent: quota.percent,
            tokensUsed: entries.filter { $0.date >= start }.reduce(0) { $0 + $1.tokens },
            windowStart: start, resetDate: quota.resetsAt ?? now,
            accent: .coral,
            isMeasured: true,
            localActivityEnd: block?.end
        )
    }

    /// Seven-day window, optionally narrowed to one model family for the per-model gauge.
    private static func weeklyGauge(_ quota: QuotaWindow?, entries: [TranscriptEntry], now: Date,
                                    source: QuotaSource, title: String, accent: Theme.Accent,
                                    family: String?) -> UsageWindow {
        guard let quota, source.isMeasured else {
            return UsageWindow(
                title: title, window: "7d",
                percent: 0, tokensUsed: 0,
                windowStart: now, resetDate: now,
                accent: accent,
                isMeasured: false
            )
        }

        let start = quota.resetsAt?.addingTimeInterval(-weeklyWindow) ?? now
        let scoped = entries.filter { entry in
            guard entry.date >= start else { return false }
            guard let family else { return true }
            return ModelName.family(entry.model) == family
        }
        return UsageWindow(
            title: title, window: "7d",
            percent: quota.percent,
            tokensUsed: scoped.reduce(0) { $0 + $1.tokens },
            windowStart: start, resetDate: quota.resetsAt ?? now,
            accent: accent,
            isMeasured: true
        )
    }

    /// Monthly spend cap. The window is the calendar month, so the pace marker reads as it does
    /// elsewhere: halfway through the month, steady spending sits at 50 %.
    private static func spendGauge(_ spend: SpendReading?, source: QuotaSource) -> UsageWindow? {
        guard let spend, source.isMeasured else { return nil }
        return UsageWindow(
            title: "Spend", window: "month",
            percent: spend.percent, tokensUsed: 0,
            windowStart: spend.startsAt, resetDate: spend.resetsAt,
            accent: .coral,
            isMeasured: true,
            amount: spend
        )
    }

    private struct Block {
        let start: Date
        var end: Date { start.addingTimeInterval(sessionWindow) }
        var tokens: Int
    }

    /// Current local window, used only to situate activity when the account gives no quota. Split
    /// the way Claude Code does: opens on the first message, closes after five hours or a longer idle.
    private static func currentLocalBlock(_ entries: [TranscriptEntry], now: Date) -> Block? {
        var blocks: [Block] = []
        var previous: Date?

        for entry in entries {
            let expired = blocks.last.map { entry.date >= $0.end } ?? true
            let idle = previous.map { entry.date.timeIntervalSince($0) >= sessionWindow } ?? true

            if expired || idle {
                blocks.append(Block(start: floorToHour(entry.date), tokens: entry.tokens))
            } else {
                blocks[blocks.count - 1].tokens += entry.tokens
            }
            previous = entry.date
        }
        return blocks.last.flatMap { $0.end > now ? $0 : nil }
    }

    private static func floorToHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }

    /// Model that weighed the most since a given date. The *last* line's model is often a hook
    /// or a subagent; the window's dominant model is what describes the real work.
    private static func dominantModel(_ entries: [TranscriptEntry], since: Date) -> String {
        var totals: [String: Double] = [:]
        for entry in entries where entry.date >= since {
            totals[ModelName.display(entry.model), default: 0] += entry.weight
        }
        return totals.max { $0.value < $1.value }?.key ?? ""
    }

    /// Seven rolling days. Idle days must exist as points, or the curve skips its own troughs.
    private static func history(_ entries: [TranscriptEntry], today: Date, calendar: Calendar) -> [TokenSample] {
        var totals: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            totals[day, default: 0] += entry.tokens
        }
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return TokenSample(date: day, tokens: totals[day] ?? 0)
        }
    }

    /// Rows shown per split.
    private static let rowLimit = 4

    /// Tokens and weight summed under one key.
    private struct Tally {
        var tokens = 0
        var weight = 0.0
    }

    private static func tally(_ entries: [TranscriptEntry],
                              by key: (TranscriptEntry) -> String) -> [(key: String, value: Tally)] {
        var totals: [String: Tally] = [:]
        for entry in entries {
            totals[key(entry), default: Tally()].tokens += entry.tokens
            totals[key(entry), default: Tally()].weight += entry.weight
        }
        return totals.sorted { $0.value.weight > $1.value.weight }
    }

    /// Split by model, ranked and shared by weight: raw tokens are mostly cache reads and would
    /// crown whichever model re-reads the longest context, not the one using the quota. Dated
    /// snapshots of one version (`claude-haiku-4-5` and `claude-haiku-4-5-20251001`) are one row.
    /// Below 1 % a row adds nothing but a "0 %" and an invisible bar.
    private static func models(_ entries: [TranscriptEntry]) -> [ModelUsage] {
        let rows = tally(entries) { ModelName.display($0.model) }
        let total = rows.reduce(0) { $0 + $1.value.weight }
        guard total > 0 else { return [] }

        return rows.filter { $0.value.weight / total >= 0.01 }.prefix(rowLimit).map { name, tally in
            ModelUsage(
                id: name,
                name: name,
                tokens: tally.tokens,
                share: tally.weight / total,
                accent: ModelName.accent(name)
            )
        }
    }

    /// Split by project, ranked and shared by weight like the models.
    private static func projects(_ entries: [TranscriptEntry]) -> [ProjectUsage] {
        let rows = tally(entries, by: \.project)
        let total = rows.reduce(0) { $0 + $1.value.weight }
        guard total > 0 else { return [] }

        let top = Array(rows.prefix(rowLimit))
        let names = displayNames(for: top.map(\.key))
        return top.map { path, tally in
            ProjectUsage(
                id: path,
                name: names[path] ?? path,
                tokens: tally.tokens,
                share: tally.weight / total
            )
        }
    }

    /// Folder name, prefixed by its parent when two shown projects share one, so `work/api` and
    /// `personal/api` stay distinguishable.
    static func displayNames(for paths: [String]) -> [String: String] {
        func name(_ path: String) -> String {
            let last = (path as NSString).lastPathComponent
            return last.isEmpty || last == "/" ? "—" : last
        }
        let counts = Dictionary(grouping: paths, by: name).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: paths.map { path in
            let short = name(path)
            guard counts[short, default: 0] > 1 else { return (path, short) }
            let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            return (path, parent.isEmpty || parent == "/" ? short : "\(parent)/\(short)")
        })
    }
}
