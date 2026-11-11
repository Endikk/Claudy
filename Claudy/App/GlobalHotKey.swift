import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut heard from any app: ⌃⌥C shows or hides Claudy.
///
/// Carbon's hot keys need no accessibility permission, unlike a global key monitor, and the key
/// never reaches the app in front. ⌥⌘C was the obvious pick, but the Finder already copies a
/// file's path with it.
@MainActor
final class GlobalHotKey {

    /// The shortcut as menus show it.
    static let display = "⌃⌥C"
    static let keyEquivalent = "c"
    static let modifiers: NSEvent.ModifierFlags = [.control, .option]

    /// False when another app holds the shortcut: the menu says so instead of promising it.
    private(set) var isRegistered = false

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    /// Carbon calls back through a C function: it finds this object again by this pointer.
    private var selfPointer: UnsafeMutableRawPointer?

    /// "Clau": the signature Carbon files the shortcut under.
    private static let signature: OSType = 0x436C_6175

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() {
        guard hotKey == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        selfPointer = pointer
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, pointer, &handler)
        guard installed == noErr else {
            DiagnosticLog.append("hotkey: handler not installed (\(installed))")
            return
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        isRegistered = status == noErr
        if !isRegistered {
            DiagnosticLog.append("hotkey: \(Self.display) not registered (\(status)), taken by another app?")
            unregister()
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        isRegistered = false
    }
}
