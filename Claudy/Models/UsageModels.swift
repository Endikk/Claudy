import Foundation

/// Une fenêtre de quota (session 5h, hebdomadaire, quota Sonnet…).
struct UsageWindow: Identifiable, Equatable {
    let id: String
    /// Titre affiché : « Session », « Hebdo », « Sonnet ».
    let title: String
    /// Qualificatif de fenêtre : « 5h », « 7j ».
    let window: String
    /// 0…1
    var percent: Double
    var tokensUsed: Int
    var tokensLimit: Int
    /// Début de la fenêtre : c'est lui qui donne le rythme attendu.
    var windowStart: Date
    var resetDate: Date

    var accent: Theme.Accent

    /// Faux quand aucune fenêtre n'est en cours (aucune session ouverte) : il n'y a alors
    /// rien à décompter, et afficher une heure de reset passée serait faux.
    var isActive: Bool { resetDate > Date() }

    /// Part de la fenêtre déjà écoulée, 0…1. C'est la position du repère de rythme :
    /// à la moitié d'une fenêtre, une consommation régulière serait à 50 %.
    var elapsed: Double {
        let duration = resetDate.timeIntervalSince(windowStart)
        guard duration > 0 else { return 0 }
        return min(max(Date().timeIntervalSince(windowStart) / duration, 0), 1)
    }

    /// Écart au rythme, en points de pourcentage. Positif = consommation en avance sur l'horloge.
    var paceDelta: Double { percent - elapsed }
}

/// Un point de l'historique quotidien alimentant la sparkline.
struct TokenSample: Identifiable, Equatable {
    let id: Date
    let date: Date
    var tokens: Int

    init(date: Date, tokens: Int) {
        self.id = date
        self.date = date
        self.tokens = tokens
    }
}

/// Répartition par modèle sur 7 jours.
struct ModelUsage: Identifiable, Equatable {
    let id: String
    let name: String
    var tokens: Int
    /// Part du total, 0…1
    var share: Double
    let accent: Theme.Accent
}

/// Répartition par projet sur 7 jours.
struct ProjectUsage: Identifiable, Equatable {
    let id: String
    let name: String
    var tokens: Int
    /// Part du total, 0…1
    var share: Double
}

/// Compte connecté.
struct Account: Equatable {
    let name: String
    let email: String
    let plan: String
    let organization: String
    let isAdmin: Bool

    var initial: String {
        let letter = name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        return letter.isEmpty ? "?" : letter
    }
}

/// État complet rendu par la vue à un instant donné.
/// Une seule structure : le ViewModel n'expose qu'elle, donc pas d'état partiel incohérent à l'écran.
struct UsageSnapshot: Equatable {
    var session: UsageWindow
    var weekly: UsageWindow
    var sonnet: UsageWindow

    /// 7 points, du plus ancien au plus récent (le dernier étant le jour en cours, partiel).
    var history: [TokenSample]
    var models: [ModelUsage]
    var projects: [ProjectUsage]

    var account: Account
    var activeModel: String
    var todayTokens: Int
    var weekTokens: Int
    var sessionCount: Int
    var updatedAt: Date

    /// Vrai quand Claude Code est absent de la machine : l'interface l'annonce au lieu de faire
    /// passer des valeurs inventées pour un relevé réel.
    var isDemo: Bool

    /// Vrai quand les quotas affichés datent d'un passage précédent (API injoignable) :
    /// l'interface le signale discrètement au lieu de remettre les jauges à zéro.
    var quotaStale: Bool = false

    /// Vrai quand un jeton Claude est disponible : les jauges affichent les quotas réels.
    /// Faux = mode « estimé » (référence personnelle), avec invitation à se connecter.
    var isSignedIn: Bool = false

    /// Aucune activité relevée sur la fenêtre de 7 jours.
    var isEmpty: Bool { weekTokens == 0 }

    /// État affiché avant le premier `fetch()` — jamais visible plus de quelques millisecondes,
    /// mais évite un optionnel dans toutes les vues.
    static let placeholder = UsageSnapshot(
        session: UsageWindow(id: "session", title: "Session", window: "5h",
                             percent: 0, tokensUsed: 0, tokensLimit: 1,
                             windowStart: .now, resetDate: .now, accent: .coral),
        weekly: UsageWindow(id: "weekly", title: "Hebdo", window: "7j",
                            percent: 0, tokensUsed: 0, tokensLimit: 1,
                            windowStart: .now, resetDate: .now, accent: .amber),
        sonnet: UsageWindow(id: "sonnet", title: "Sonnet", window: "7j",
                            percent: 0, tokensUsed: 0, tokensLimit: 1,
                            windowStart: .now, resetDate: .now, accent: .violet),
        history: [],
        models: [],
        projects: [],
        account: Account(name: "", email: "", plan: "", organization: "", isAdmin: false),
        activeModel: "",
        todayTokens: 0,
        weekTokens: 0,
        sessionCount: 0,
        updatedAt: .now,
        isDemo: false
    )
}
