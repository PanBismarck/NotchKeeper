import Carbon.HIToolbox

/// One system-wide shortcut via Carbon `RegisterEventHotKey` — no Accessibility permission, no event tap,
/// zero cost until pressed.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func set(_ shortcut: AppSettings.Shortcut) {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        guard let (key, modifiers) = Self.carbon(shortcut) else { return }
        installHandlerOnce()
        let id = EventHotKeyID(signature: OSType(0x4E4F5443), id: 1)   // 'NOTC'
        RegisterEventHotKey(key, modifiers, id, GetEventDispatcherTarget(), 0, &ref)
    }

    private func installHandlerOnce() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handler)
    }

    private static func carbon(_ shortcut: AppSettings.Shortcut) -> (UInt32, UInt32)? {
        switch shortcut {
        case .off: nil
        case .optionCommandN: (UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey))
        case .controlOptionN: (UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        }
    }
}
