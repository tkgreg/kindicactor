import Foundation

/// A keyboard shortcut: a key plus modifiers, with the name to show for the key. KIndicator
/// listens for some (launch actions) and presses others (the knob's actions).
package struct Hotkey: Codable, Hashable, Sendable {
    /// A Mac virtual key code (`kVK_…`).
    package var keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value: command, option, control and shift only.
    package var modifiers: UInt
    package var keyName: String

    /// `NSEvent.ModifierFlags` bits, so the core needs no AppKit.
    package static let shift: UInt = 1 << 17
    package static let control: UInt = 1 << 18
    package static let option: UInt = 1 << 19
    package static let command: UInt = 1 << 20

    package init(keyCode: UInt16, modifiers: UInt = 0, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    /// Whether a real keyboard sends this key with Fn set: F-keys, arrows, Home, End, Page Up,
    /// Page Down, Forward Delete and Help. The system's own shortcuts include it: Mission
    /// Control is stored as ⌃Fn↑, so a ⌃↑ pressed without Fn doesn't open it.
    package var sendsFn: Bool { isArrow || Self.fnKeys.contains(keyCode) }

    /// An arrow key, which a real keyboard also sends with the keypad flag.
    package var isArrow: Bool { (123...126).contains(keyCode) }

    /// kVK_F1…kVK_F20, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Help.
    private static let fnKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
        115, 119, 116, 121, 117, 114,
    ]

    /// "⌃⌥⇧⌘E", in the order the Mac's menus use.
    package var display: String {
        (modifiers & Self.control != 0 ? "⌃" : "") + (modifiers & Self.option != 0 ? "⌥" : "")
            + (modifiers & Self.shift != 0 ? "⇧" : "") + (modifiers & Self.command != 0 ? "⌘" : "") + keyName
    }
}
