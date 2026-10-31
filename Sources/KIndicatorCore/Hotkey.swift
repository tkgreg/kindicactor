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

    /// "⌃⌥⇧⌘E", in the order the Mac's menus use.
    package var display: String {
        (modifiers & Self.control != 0 ? "⌃" : "") + (modifiers & Self.option != 0 ? "⌥" : "")
            + (modifiers & Self.shift != 0 ? "⇧" : "") + (modifiers & Self.command != 0 ? "⌘" : "") + keyName
    }
}
