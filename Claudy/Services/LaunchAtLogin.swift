import Foundation
import Security
import ServiceManagement

/// Login-item registration through `SMAppService`.
///
/// `register()` fails until the app is signed with a stable identity
/// (`Error Domain=SMAppServiceErrorDomain Code=1`), so failure is expected in ad-hoc builds.
/// It is reported rather than swallowed, so the UI never claims the option is on when it is not.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the running binary is ad-hoc signed. `register()` will always be refused, so
    /// the UI announces the option as unavailable instead of offering it.
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

    /// Returns the state actually reached, which may differ from the one requested.
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[Claudy] Launch at login unavailable: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
