import AppKit
import UserNotifications

/// Where notifications go: Notification Center in the app, a recorder in the tests.
@MainActor
protocol NotificationPosting: AnyObject {
    /// Asks once, the first time something is to be said; then answers from what the user chose.
    func authorize() async -> Bool
    /// Whether the user turned Claudy's notifications off in System Settings. Never asks.
    func isDenied() async -> Bool
    func post(_ alert: Alert)
    func withdraw(_ ids: [String])
}

/// Sends Claudy's notifications, each kind behind its own switch, and brings forward the session
/// a banner spoke of when it is clicked.
@MainActor
final class Notifier: ObservableObject {

    /// The kinds switched on, kept across launches.
    @Published private(set) var enabled: Set<NotificationKind>
    /// The user turned Claudy's notifications off in System Settings: the switches can do nothing
    /// until they are turned back on there, and the menu says so.
    @Published private(set) var isDenied = false

    /// A click on a banner about a session.
    var onOpenSession: ((String) -> Void)?

    private let poster: NotificationPosting
    private let store: UserDefaults

    init(poster: NotificationPosting? = nil, store: UserDefaults = .standard) {
        self.store = store
        self.poster = poster ?? SystemNotifications()
        enabled = Set(NotificationKind.allCases.filter { kind in
            store.object(forKey: Self.key(kind)) as? Bool ?? kind.isOnByDefault
        })
        (self.poster as? SystemNotifications)?.onOpen = { [weak self] sessionID in
            self?.onOpenSession?(sessionID)
        }
    }

    /// Reads whether notifications are allowed, without asking: at launch, and as a menu opens,
    /// since the user may have changed it in System Settings meanwhile.
    func refreshPermission() {
        Task { isDenied = await poster.isDenied() }
    }

    func isEnabled(_ kind: NotificationKind) -> Bool { enabled.contains(kind) }

    func toggle(_ kind: NotificationKind) {
        set(kind, on: !isEnabled(kind))
    }

    func set(_ kind: NotificationKind, on: Bool) {
        if on { enabled.insert(kind) } else { enabled.remove(kind) }
        store.set(on, forKey: Self.key(kind))
    }

    /// Posts the alerts whose kind is switched on. The system is asked for permission the first
    /// time there is something to say, not at launch: the question then comes with its reason.
    func deliver(_ alerts: [Alert]) {
        let wanted = alerts.filter { isEnabled($0.kind) }
        guard !wanted.isEmpty else { return }
        Task {
            let allowed = await poster.authorize()
            // A refusal is the user's; a failed request is not, and must not read as one.
            isDenied = allowed ? false : await poster.isDenied()
            guard allowed else { return }
            for alert in wanted { poster.post(alert) }
        }
    }

    /// Takes back banners whose event no longer holds: a session answered elsewhere.
    func withdraw(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        poster.withdraw(ids)
    }

    /// Claudy's pane in System Settings ▸ Notifications.
    func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.claudy.Claudy"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func key(_ kind: NotificationKind) -> String {
        "claudy.notify.\(kind.rawValue)"
    }
}

/// Notification Center. Claudy is an agent app: while its card is key it counts as the app in
/// front, and macOS keeps a front app's notifications out of sight unless the app asks to show
/// them, which it does.
@MainActor
final class SystemNotifications: NSObject, NotificationPosting, UNUserNotificationCenterDelegate {

    var onOpen: ((String) -> Void)?
    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        // Hosting the tests, Claudy posts nothing: the center is not touched.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        center.delegate = self
    }

    func authorize() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        case .denied: return false
        default:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                DiagnosticLog.append("notifications: authorization failed: \(error.localizedDescription)")
                return false
            }
        }
    }

    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    func post(_ alert: Alert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = alert.kind.isQuota ? "quota" : "sessions"
        if let sessionID = alert.sessionID { content.userInfo = ["sessionID": sessionID] }
        center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)) { error in
            if let error {
                DiagnosticLog.append("notifications: post failed: \(error.localizedDescription)")
            }
        }
    }

    func withdraw(_ ids: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        else { return }
        await MainActor.run { onOpen?(sessionID) }
    }
}
