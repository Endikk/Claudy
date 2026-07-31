import Foundation
import ServiceManagement

/// Enregistrement au démarrage via `SMAppService`.
///
/// Attention : `register()` échoue tant que l'app n'est pas signée avec une identité stable
/// (`Error Domain=SMAppServiceErrorDomain Code=1`). En build ad-hoc, l'échec est donc normal —
/// on le remonte plutôt que de laisser l'interface prétendre que l'option est active.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Retourne l'état réellement obtenu, qui peut différer de celui demandé.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[Claudy] Lancement au démarrage indisponible : \(error.localizedDescription)")
        }
        return isEnabled
    }
}
