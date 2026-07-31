import Foundation
import Security
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

    /// Vrai si le binaire courant est signé ad hoc : `register()` refusera systématiquement,
    /// l'interface doit donc annoncer l'option comme indisponible plutôt que la proposer.
    static let isAdHocSigned: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let rawFlags = dict[kSecCodeInfoFlags as String] as? UInt32 else { return false }
        return SecCodeSignatureFlags(rawValue: rawFlags).contains(.adhoc)
    }()

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
