import Foundation

/// Transforme les relevés bruts en instantané affichable.
///
/// **Pourquoi des pourcentages relatifs.** Anthropic n'expose aucune API publique donnant le
/// quota restant d'une fenêtre 5 h ou hebdomadaire, et les transcripts n'en portent aucune trace.
/// Un pourcentage « sur le quota réel » serait donc inventé. Claudy affiche à la place la
/// consommation rapportée à la *référence personnelle* de la machine : le 90ᵉ centile des
/// fenêtres déjà écoulées. 100 % signifie « au niveau de tes plus grosses fenêtres », pas
/// « quota épuisé ». Chaque référence est remplaçable par une valeur explicite
/// (`claudy.limit.session`, `claudy.limit.weekly`, `claudy.limit.model` dans les préférences).
enum UsageAggregator {

    /// Durée d'une fenêtre de session Claude Code.
    static let sessionWindow: TimeInterval = 5 * 3600
    private static let day: TimeInterval = 86_400

    static func snapshot(from entries: [TranscriptEntry], account: Account, now: Date = Date()) -> UsageSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // Semaine calendaire, et pas fenêtre glissante : c'est ce qui donne un vrai instant de
        // remise à zéro — et donc un rythme attendu à comparer à la consommation réelle.
        // Le premier jour suit la locale du système (lundi en France, dimanche aux États-Unis).
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: today, duration: 7 * day)

        // — Fenêtre 5 h —
        let blocks = sessionBlocks(entries)
        let active = blocks.last.flatMap { $0.end > now ? $0 : nil }
        let closed = blocks.filter { $0.end <= now }
        let sessionReference = limit(named: "session", observed: closed.map(\.tokens), current: active?.tokens ?? 0)

        // — Semaine en cours —
        let weekEntries = entries.filter { week.contains($0.date) }
        let weekTokens = weekEntries.reduce(0) { $0 + $1.tokens }

        let weekReference = limit(named: "weekly",
                                  observed: weekEquivalents(entries, today: today, calendar: calendar),
                                  current: weekTokens)

        // Troisième jauge : la fenêtre Sonnet, qui a son propre quota chez Anthropic — mais si
        // cette machine n'utilise pas Sonnet, la colonne resterait morte. On bascule alors sur
        // la famille la plus consommée, dont le nom devient le titre.
        let focus = focusFamily(weekEntries)
        let focusEntries = entries.filter { ModelName.family($0.model) == focus }
        let focusTokens = focusEntries.filter { week.contains($0.date) }.reduce(0) { $0 + $1.tokens }
        let focusReference = limit(named: "model",
                                   observed: weekEquivalents(focusEntries, today: today, calendar: calendar),
                                   current: focusTokens)

        // L'historique et les répartitions restent sur 7 jours glissants : une sparkline qui
        // repart à un point le lundi n'apprendrait rien.
        let rolling = entries.filter { $0.date >= now.addingTimeInterval(-7 * day) }
        let rollingTokens = rolling.reduce(0) { $0 + $1.tokens }

        return UsageSnapshot(
            session: UsageWindow(
                id: "session", title: "Session", window: "5h",
                percent: ratio(active?.tokens ?? 0, sessionReference),
                tokensUsed: active?.tokens ?? 0,
                tokensLimit: sessionReference,
                windowStart: active?.start ?? now,
                // Sans fenêtre active, la prochaine démarrera au premier message : rien à décompter.
                resetDate: active?.end ?? now,
                accent: .coral
            ),
            weekly: UsageWindow(
                id: "weekly", title: "Hebdo", window: "sem.",
                percent: ratio(weekTokens, weekReference),
                tokensUsed: weekTokens, tokensLimit: weekReference,
                windowStart: week.start, resetDate: week.end, accent: .amber
            ),
            sonnet: UsageWindow(
                id: "focus", title: ModelName.display(focus), window: "sem.",
                percent: ratio(focusTokens, focusReference),
                tokensUsed: focusTokens, tokensLimit: focusReference,
                windowStart: week.start, resetDate: week.end, accent: ModelName.accent(focus)
            ),
            history: history(rolling, today: today, calendar: calendar),
            models: models(rolling, total: rollingTokens),
            projects: projects(rolling, total: rollingTokens),
            account: account,
            // Le modèle de la *dernière* ligne est souvent celui d'un hook ou d'un sous-agent :
            // c'est le modèle dominant de la fenêtre en cours qui décrit le travail réel.
            activeModel: dominantModel(entries, since: active?.start ?? today),
            todayTokens: entries.filter { $0.date >= today }.reduce(0) { $0 + $1.tokens },
            weekTokens: rollingTokens,
            // Les sous-agents portent leur propre identifiant de session : les compter gonflerait
            // le chiffre d'un ordre de grandeur.
            sessionCount: Set(entries.filter { $0.date >= today && !$0.isSidechain }.map(\.sessionID)).count,
            updatedAt: now,
            isDemo: false
        )
    }

    // MARK: - Fenêtres de session

    struct Block {
        let start: Date
        var end: Date { start.addingTimeInterval(sessionWindow) }
        var tokens: Int
    }

    /// Découpe en fenêtres de 5 h, à la manière de Claude Code : une fenêtre s'ouvre au premier
    /// message (calé sur l'heure ronde) et se referme au bout de 5 h — ou plus tôt si l'activité
    /// s'interrompt plus longtemps que la fenêtre elle-même.
    static func sessionBlocks(_ entries: [TranscriptEntry]) -> [Block] {
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
        return blocks
    }

    private static func floorToHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }

    // MARK: - Références

    /// Équivalents-semaine : sept fois chaque total journalier des jours *terminés*.
    ///
    /// On ne compare pas des semaines entre elles — la fenêtre de rétention n'en contient
    /// jamais assez pour que ce soit stable. Sept journées bien remplies forment une semaine
    /// chargée : c'est la référence, et elle dispose d'autant d'échantillons que de jours.
    private static func weekEquivalents(_ entries: [TranscriptEntry], today: Date, calendar: Calendar) -> [Int] {
        var totals: [Date: Int] = [:]
        for entry in entries where entry.date < today {
            totals[calendar.startOfDay(for: entry.date), default: 0] += entry.tokens
        }
        return totals.values.map { $0 * 7 }
    }

    /// Référence d'une jauge : préférence explicite, sinon 90ᵉ centile des fenêtres observées.
    /// Sans historique du tout, la consommation courante fait office de référence — la jauge
    /// affiche alors 100 % et se recalibre dès la première fenêtre écoulée.
    private static func limit(named key: String, observed: [Int], current: Int) -> Int {
        if let override = UserDefaults.standard.object(forKey: "claudy.limit.\(key)") as? Int, override > 0 {
            return override
        }
        let sorted = observed.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return max(current, 1) }

        let index = Int((Double(sorted.count - 1) * 0.9).rounded())
        return max(sorted[index], 1)
    }

    /// Modèle ayant consommé le plus de tokens depuis une date donnée.
    private static func dominantModel(_ entries: [TranscriptEntry], since: Date) -> String {
        var totals: [String: Int] = [:]
        for entry in entries where entry.date >= since { totals[entry.model, default: 0] += entry.tokens }
        guard let top = totals.max(by: { $0.value < $1.value })?.key else { return "" }
        return ModelName.display(top)
    }

    /// Famille mise en avant par la troisième jauge : Sonnet quand elle est utilisée
    /// (elle porte son propre quota), sinon la famille la plus consommée de la semaine.
    private static func focusFamily(_ entries: [TranscriptEntry]) -> String {
        var totals: [String: Int] = [:]
        for entry in entries { totals[ModelName.family(entry.model), default: 0] += entry.tokens }

        if let sonnet = totals["sonnet"], sonnet > 0 { return "sonnet" }
        return totals.max { $0.value < $1.value }?.key ?? "sonnet"
    }

    private static func ratio(_ used: Int, _ reference: Int) -> Double {
        guard reference > 0 else { return 0 }
        return min(Double(used) / Double(reference), 1)
    }

    // MARK: - Répartitions

    private static func history(_ entries: [TranscriptEntry], today: Date, calendar: Calendar) -> [TokenSample] {
        var totals: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            totals[day, default: 0] += entry.tokens
        }
        // Les jours sans activité doivent exister, sinon la courbe saute les creux.
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return TokenSample(date: day, tokens: totals[day] ?? 0)
        }
    }

    private static func models(_ entries: [TranscriptEntry], total: Int) -> [ModelUsage] {
        var totals: [String: Int] = [:]
        for entry in entries { totals[entry.model, default: 0] += entry.tokens }

        // Sous 1 %, la ligne n'apporte rien qu'un « 0 % » et une barre invisible.
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
