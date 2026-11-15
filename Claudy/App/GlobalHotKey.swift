import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut heard from any app: ⌃⌥C shows or hides Claudy, ⌃⌥R opens the agent room.
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
    /// The agent room's own shortcut.
    static let roomDisplay = "⌃⌥R"
    static let roomKeyEquivalent = "r"

    /// False when another app holds the shortcut: the menu says so instead of promising it.
    private(set) var isRegistered = false

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let keyCode: Int
    /// Tells this shortcut apart from Claudy's others: every handler hears every one of them.
    private let id: UInt32
    private let display: String
    /// Carbon calls back through a C function: it finds this object again by this pointer.
    private var selfPointer: UnsafeMutableRawPointer?

    /// "Clau": the signature Carbon files the shortcut under.
    private static let signature: OSType = 0x436C_6175

    init(keyCode: Int = kVK_ANSI_C, id: UInt32 = 1, display: String = GlobalHotKey.display,
         action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.id = id
        self.display = display
        self.action = action
    }

    /// Runs the action when the shortcut pressed is this one.
    private func pressed(_ pressedID: UInt32) -> Bool {
        guard pressedID == id else { return false }
        action()
        return true
    }

    func register() {
        guard hotKey == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        selfPointer = pointer
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard read == noErr else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            let pressedID = pressed.id
            let isMine = MainActor.assumeIsolated { hotKey.pressed(pressedID) }
            return isMine ? noErr : OSStatus(eventNotHandledErr)
        }, 1, &spec, pointer, &handler)
        guard installed == noErr else {
            DiagnosticLog.append("hotkey: handler not installed (\(installed))")
            return
        }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey), hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKey)
        isRegistered = status == noErr
        if !isRegistered {
            DiagnosticLog.append("hotkey: \(display) not registered (\(status)), taken by another app?")
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
