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
            history: history(rolling, today: today, calendar: calendar),
            models: models(rolling, total: rollingTokens),
            projects: projects(rolling, total: rollingTokens),
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
        guard let quota, source.isMeasured else {
            let block = currentLocalBlock(entries, now: now)
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
            isMeasured: true
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

    /// Model that consumed the most tokens since a given date. The *last* line's model is often a
    /// hook or a subagent; the window's dominant model is what describes the real work.
    private static func dominantModel(_ entries: [TranscriptEntry], since: Date) -> String {
        var totals: [String: Int] = [:]
        for entry in entries where entry.date >= since { totals[entry.model, default: 0] += entry.tokens }
        guard let top = totals.max(by: { $0.value < $1.value })?.key else { return "" }
        return ModelName.display(top)
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

    /// Split by model. Below 1 % a row adds nothing but a "0 %" and an invisible bar.
    private static func models(_ entries: [TranscriptEntry], total: Int) -> [ModelUsage] {
        var totals: [String: Int] = [:]
        for entry in entries { totals[entry.model, default: 0] += entry.tokens }

        let significant = totals.filter { total == 0 || Double($0.value) / Double(total) >= 0.01 }
        return significant.sorted { $0.value > $1.value }.prefix(4).map { model, tokens in
            ModelUsage(
                id: model,
                name: ModelName.display(model),
                tokens: tokens,
                share: total > 0 ? Double(tokens) / Double(total) : 0,
                accent: ModelName.accent(model)
            )
        }
    }

    /// Split by project, top four.
    private static func projects(_ entries: [TranscriptEntry], total: Int) -> [ProjectUsage] {
        var totals: [String: Int] = [:]
        for entry in entries { totals[entry.project, default: 0] += entry.tokens }

        return totals.sorted { $0.value > $1.value }.prefix(4).map { project, tokens in
            ProjectUsage(
                id: project,
                name: project,
                tokens: tokens,
                share: total > 0 ? Double(tokens) / Double(total) : 0
            )
        }
    }
}
