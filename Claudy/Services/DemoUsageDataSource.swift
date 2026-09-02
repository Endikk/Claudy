import Foundation

/// Sample data set, used when Claude Code is not installed on the machine.
///
/// Nothing identifying is written into it: the name comes from the current macOS session, the
/// projects carry neutral names, and the snapshot is marked as demo so the UI announces it.
actor DemoUsageDataSource: UsageDataSource {

    private var drift: Double = 0
    private var start = Date()

    func fetch() async throws -> UsageSnapshot {
        try? await Task.sleep(nanoseconds: 250_000_000)

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: today, duration: 7 * 86_400)

        drift += Double.random(in: 0.006...0.02)
        if drift >= 0.62 { drift = 0; start = now }

        let sessionPercent = min(0.34 + drift, 0.99)
        let weeklyLimit = 16_000_000
        let sonnetLimit = 7_000_000

        let daily = [0.52, 0.94, 0.28, 0.71, 1.0, 0.61, 0.38 + drift / 2]
        let peak = 2_200_000.0
        let history = daily.enumerated().map { index, factor -> TokenSample in
            let day = calendar.date(byAdding: .day, value: index - (daily.count - 1), to: today) ?? today
            return TokenSample(date: day, tokens: Int(peak * factor))
        }

        let weekTokens = history.reduce(0) { $0 + $1.tokens }
        let weeklyPercent = min(Double(weekTokens) / Double(weeklyLimit), 1)
        let sonnetTokens = Int(Double(weekTokens) * 0.29)

        return UsageSnapshot(
            session: UsageWindow(
                title: "Session", window: "5h",
                percent: sessionPercent,
                tokensUsed: Int(2_400_000 * sessionPercent),
                windowStart: start,
                resetDate: start.addingTimeInterval(UsageAggregator.sessionWindow),
                accent: .coral
            ),
            weekly: UsageWindow(
                title: "Weekly", window: "7d",
                percent: weeklyPercent,
                tokensUsed: weekTokens,
                windowStart: week.start, resetDate: week.end,
                accent: .amber
            ),
            sonnet: UsageWindow(
                title: "Sonnet", window: "7d",
                percent: min(Double(sonnetTokens) / Double(sonnetLimit), 1),
                tokensUsed: sonnetTokens,
                windowStart: week.start, resetDate: week.end,
                accent: .violet
            ),
            history: history,
            models: [
                ModelUsage(id: "opus", name: "Opus", tokens: Int(Double(weekTokens) * 0.54),
                           share: 0.54, accent: .coral),
                ModelUsage(id: "sonnet", name: "Sonnet", tokens: sonnetTokens,
                           share: 0.29, accent: .violet),
                ModelUsage(id: "haiku", name: "Haiku", tokens: Int(Double(weekTokens) * 0.17),
                           share: 0.17, accent: .sky)
            ],
            projects: [
                ProjectUsage(id: "a", name: "main-project", tokens: Int(Double(weekTokens) * 0.44), share: 0.44),
                ProjectUsage(id: "b", name: "api", tokens: Int(Double(weekTokens) * 0.27), share: 0.27),
                ProjectUsage(id: "c", name: "website", tokens: Int(Double(weekTokens) * 0.18), share: 0.18),
                ProjectUsage(id: "d", name: "scripts", tokens: Int(Double(weekTokens) * 0.11), share: 0.11)
            ],
            account: AccountLoader.fallback(),
            activeModel: "Opus",
            todayTokens: history.last?.tokens ?? 0,
            weekTokens: weekTokens,
            sessionCount: 3,
            updatedAt: now,
            quotaSource: .demo
        )
    }
}
