import AppKit
import IOKit.hidsystem
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "keys")

/// Presses keys for the knob's actions as if typed: media keys the way the Mac's own keys
/// send them, so the volume and brightness show on screen, and shortcuts. macOS lets an app
/// do this only with Accessibility permission; without it the keys are dropped.
@MainActor
enum KeyPresser {
    static var isAllowed: Bool { CGPreflightPostEventAccess() }

    /// Asks once with macOS's own prompt, and lists KIndicator in Accessibility settings.
    static func requestPermission() {
        CGRequestPostEventAccess()
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func perform(_ action: KeyAction, times: Int = 1) {
        for _ in 0..<times {
            switch action {
            case .nothing: break
            case .media(let key): press(key)
            case .shortcut(let hotkey): press(hotkey)
            }
        }
    }

    private static func press(_ key: MediaKey) {
        let (code, modifiers): (Int32, NSEvent.ModifierFlags) = switch key {
        case .volumeDown: (NX_KEYTYPE_SOUND_DOWN, [])
        case .volumeUp: (NX_KEYTYPE_SOUND_UP, [])
        case .mute: (NX_KEYTYPE_MUTE, [])
        // The system takes quarter steps when ⌥⇧ come with the volume key.
        case .preciseVolumeDown: (NX_KEYTYPE_SOUND_DOWN, [.option, .shift])
        case .preciseVolumeUp: (NX_KEYTYPE_SOUND_UP, [.option, .shift])
        // What Apple keyboards' ⏪ ⏯ ⏩ keys send.
        case .previousTrack: (NX_KEYTYPE_REWIND, [])
        case .playPause: (NX_KEYTYPE_PLAY, [])
        case .nextTrack: (NX_KEYTYPE_FAST, [])
        case .brightnessDown: (NX_KEYTYPE_BRIGHTNESS_DOWN, [])
        case .brightnessUp: (NX_KEYTYPE_BRIGHTNESS_UP, [])
        }
        // A system-defined event of subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS): the key in the
        // high half of data1, then 0xA for down or 0xB for up.
        for state in [0xA, 0xB] {
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)).union(modifiers),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: Int(code) << 16 | state << 8, data2: -1)
            guard let cgEvent = event?.cgEvent else {
                log.error("can't make media key \(key.rawValue, privacy: .public)")
                return
            }
            cgEvent.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    private static func press(_ hotkey: Hotkey) {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifiers = NSEvent.ModifierFlags(rawValue: hotkey.modifiers)
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        // As a real keyboard sends them, or the system's shortcuts (Mission Control) don't match.
        if hotkey.sendsFn { flags.insert(.maskSecondaryFn) }
        if hotkey.isArrow { flags.insert(.maskNumericPad) }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: hotkey.keyCode, keyDown: isDown) else {
                log.error("can't make key \(hotkey.display, privacy: .public)")
                return
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}
