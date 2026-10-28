import Carbon.HIToolbox
import CarbonCore

/// A system-wide shortcut through `RegisterEventHotKey`, which needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// ⌥⌘C by default, Show Carbon's shortcut.
    init(keyCode: Int = kVK_ANSI_C, modifiers: Int = optionKey | cmdKey, action: @escaping @MainActor () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4352_424E), id: 1),
            GetApplicationEventTarget(), 0, &hotKey)
    }

    convenience init(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) {
        let modifiers: [(Shortcut.Modifiers, Int)] = [
            (.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey),
        ]
        self.init(
            keyCode: shortcut.keyCode,
            modifiers: modifiers.filter { shortcut.modifiers.contains($0.0) }.reduce(0) { $0 | $1.1 },
            action: action)
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
