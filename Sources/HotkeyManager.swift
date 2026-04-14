import Carbon
import AppKit

// Carbon event handler callback — must be a free function (C function pointer compatible)
private func hotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr else { return OSStatus(eventNotHandledErr) }

    DispatchQueue.main.async {
        switch hotKeyID.id {
        case 1: manager.onTranscript?()
        case 2: manager.onAssistant?()
        case 3: manager.onDictation?()
        case 4: manager.onStop?()
        default: break
        }
    }
    return noErr
}

class HotkeyManager {
    var onTranscript: (() -> Void)?
    var onAssistant:  (() -> Void)?
    var onDictation:  (() -> Void)?
    var onStop:       (() -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?

    // Virtual key codes (US layout, hardware-independent)
    // kVK_ANSI_T = 0x11, kVK_ANSI_A = 0x00, kVK_ANSI_D = 0x02, kVK_ANSI_S = 0x01
    private let hotkeys: [(id: UInt32, keyCode: UInt32, modifiers: UInt32)] = [
        (1, 0x11, UInt32(controlKey | shiftKey)),  // Ctrl+Shift+T → Transcript
        (2, 0x00, UInt32(controlKey | shiftKey)),  // Ctrl+Shift+A → Assistant
        (3, 0x02, UInt32(controlKey | shiftKey)),  // Ctrl+Shift+D → Dictation
        (4, 0x01, UInt32(controlKey | shiftKey)),  // Ctrl+Shift+S → Stop
    ]

    func register() {
        // Install Carbon event handler on the application event target
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        // InstallApplicationEventHandler is a C macro; call the underlying function directly.
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        // Register each hotkey
        for hk in hotkeys {
            var keyID = EventHotKeyID()
            keyID.signature = OSType(0x5653_4352) // 'VSCR'
            keyID.id = hk.id

            var ref: EventHotKeyRef?
            let err = RegisterEventHotKey(
                hk.keyCode,
                hk.modifiers,
                keyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if err == noErr {
                hotKeyRefs.append(ref)
            } else {
                print("HotkeyManager: Konnte Hotkey \(hk.id) nicht registrieren (err \(err))")
            }
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}
