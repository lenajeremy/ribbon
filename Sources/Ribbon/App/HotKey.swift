import Carbon
import Foundation

/// A keyboard shortcut that works whichever app is in front. Carbon hot keys need no permission.
@MainActor enum HotKey {
    private static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var installed = false

    /// ⌃⌥⌘O: hide or show the orb.
    static func register(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping @MainActor () -> Void) {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var hotKey = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
                let id = hotKey.id
                DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.handlers[id]?() } }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x5242_4E4F), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { logLine("Couldn't register the keyboard shortcut (error \(status))") }
    }
}
