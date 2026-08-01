import Foundation

/// Jeu de démonstration, utilisé quand Claude Code n'est pas installé sur la machine.
///
/// Rien d'identifiant n'y est écrit : le nom vient de la session macOS courante, les projets
/// portent des noms neutres, et l'instantané est marqué `isDemo` pour que l'interface l'annonce.
actor DemoUsageDataSource: UsageDataSource {

    private var drift: Double = 0
    private var start = Date()

    func fetch() async throws -> UsageSnapshot {
        // Latence simulée : rend l'indicateur de rafraîchissement perceptible.
        try? await Task.sleep(nanoseconds: 250_000_000)

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: today, duration: 7 * 86_400)

        drift += Double.random(in: 0.006...0.02)
        if drift >= 0.62 { drift = 0; start = now }

        let sessionPercent = min(0.34 + drift, 0.99)
        let sessionLimit = 2_400_000
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
                tokensUsed: Int(Double(sessionLimit) * sessionPercent),
                tokensLimit: sessionLimit,
                windowStart: start,
                resetDate: start.addingTimeInterval(UsageAggregator.sessionWindow),
                accent: .coral
            ),
            weekly: UsageWindow(
                title: "Hebdo", window: "sem.",
                percent: weeklyPercent,
                tokensUsed: weekTokens, tokensLimit: weeklyLimit,
                windowStart: week.start, resetDate: week.end,
                accent: .amber
            ),
            sonnet: UsageWindow(
                title: "Sonnet", window: "sem.",
                percent: min(Double(sonnetTokens) / Double(sonnetLimit), 1),
                tokensUsed: sonnetTokens, tokensLimit: sonnetLimit,
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
                ProjectUsage(id: "a", name: "projet-principal", tokens: Int(Double(weekTokens) * 0.44), share: 0.44),
                ProjectUsage(id: "b", name: "api", tokens: Int(Double(weekTokens) * 0.27), share: 0.27),
                ProjectUsage(id: "c", name: "site-web", tokens: Int(Double(weekTokens) * 0.18), share: 0.18),
                ProjectUsage(id: "d", name: "scripts", tokens: Int(Double(weekTokens) * 0.11), share: 0.11)
            ],
            account: AccountLoader.fallback(),
            activeModel: "Opus",
            todayTokens: history.last?.tokens ?? 0,
            weekTokens: weekTokens,
            sessionCount: 3,
            updatedAt: now,
            isDemo: true
        )
    }
}
