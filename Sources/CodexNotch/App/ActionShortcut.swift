import Carbon.HIToolbox
import Foundation

/// Registered only after an explicit menu request. Failure leaves the menu usable.
final class ActionShortcut {
    static let signature = OSType(0x434E_4143) // CNAC
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let onPress: () -> Void

    init?(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == ActionShortcut.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<ActionShortcut>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.onPress() }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler) == noErr else { return nil }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(optionKey | cmdKey | shiftKey),
            EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
            return nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

/// Owns the optional registration, allowing failure to leave the menu usable.
final class ActionShortcutToggle {
    private var registration: AnyObject?
    var isEnabled: Bool { registration != nil }

    func toggle(register: () -> AnyObject?, unavailable: () -> Void) {
        if registration != nil {
            registration = nil
        } else if let newRegistration = register() {
            registration = newRegistration
        } else {
            unavailable()
        }
    }
}
