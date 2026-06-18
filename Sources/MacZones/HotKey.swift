import Cocoa
import Carbon.HIToolbox

/// A global hotkey via Carbon's RegisterEventHotKey. Event-driven and
/// effectively free at idle — no polling, no monitors.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onPressed: () -> Void

    /// `keyCode` is a Carbon virtual key code (e.g. kVK_ANSI_Z).
    /// `modifiers` is a combination of cmdKey / optionKey / shiftKey / controlKey.
    init?(keyCode: UInt32, modifiers: UInt32, onPressed: @escaping () -> Void) {
        self.onPressed = onPressed

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData = userData else { return noErr }
                let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                me.onPressed()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler)

        guard handlerStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D584F4E /* "MXON" */), id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            if let handler = eventHandler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
    }

    /// Human-readable description of the default shortcut.
    static var defaultDescription: String { "⌃⌥Z" }
}
