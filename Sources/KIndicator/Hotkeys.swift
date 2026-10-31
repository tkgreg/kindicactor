import AppKit
import Carbon
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "hotkeys")

extension Hotkey {
    /// Plain keys would steal typing, so only these may be listened for without a modifier.
    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    /// `allowsPlainKeys` for a shortcut KIndicator presses rather than listens for, e.g. → alone.
    init?(event: NSEvent, allowsPlainKeys: Bool = false) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        guard allowsPlainKeys || !flags.isEmpty || Self.functionKeys[code] != nil else { return nil }
        self.init(keyCode: event.keyCode, modifiers: flags.rawValue,
                  keyName: Self.functionKeys[code] ?? Self.specialKeys[code] ?? Self.character(for: event.keyCode) ?? "?")
    }

    /// An F-key alone, e.g. one the knob sends.
    init(functionKey keyCode: Int) {
        self.init(keyCode: UInt16(keyCode), keyName: Self.functionKeys[keyCode] ?? "?")
    }

    var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        return (flags.contains(.command) ? UInt32(cmdKey) : 0) | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.control) ? UInt32(controlKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }

    /// The key's letter on an ABC-style layout, so ⌃⌥⌘E reads the same with Russian selected.
    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                           characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

/// Registers global hotkeys with the Carbon Event Manager, which needs no permissions.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    /// Who the hotkeys are for; each sets its own.
    enum Group: CaseIterable {
        case launchActions, knob, mouse
    }

    typealias Binding = (hotkey: Hotkey, action: () -> Void)

    private var groups: [Group: [Binding]] = [:]
    /// Every group's, in the order registered: a hotkey's ID is its index.
    private var bindings: [Binding] = []
    private var registered: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var suspended = false

    /// Replaces the hotkeys of `group`.
    func set(_ bindings: [Binding], for group: Group) {
        groups[group] = bindings
        self.bindings = Group.allCases.flatMap { groups[$0] ?? [] }
        if !suspended { registerAll() }
    }

    /// While a shortcut is being recorded, so pressing an existing one records it instead.
    func suspend() {
        suspended = true
        unregisterAll()
    }

    func resume() {
        suspended = false
        registerAll()
    }

    private func registerAll() {
        unregisterAll()
        installHandlerIfNeeded()
        for (index, binding) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4B49_4E44), id: UInt32(index)) // "KIND"
            let status = RegisterEventHotKey(UInt32(binding.hotkey.keyCode), binding.hotkey.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered.append(ref)
            } else {
                log.error("can't register \(binding.hotkey.display, privacy: .public): \(status)")
            }
        }
    }

    private func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            MainActor.assumeIsolated { HotkeyCenter.shared.fire(index) }
            return noErr
        }, 1, &pressed, nil, &handler)
    }

    private func fire(_ index: Int) {
        guard bindings.indices.contains(index) else { return }
        bindings[index].action()
    }
}
