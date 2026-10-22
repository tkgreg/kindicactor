import Carbon

struct InputSource: Identifiable, Hashable {
    /// E.g. "com.apple.keylayout.ABC".
    let id: String
    /// E.g. "ABC".
    let name: String
}

/// Keyboard layouts and input methods, via the Text Input Sources API.
enum InputSources {
    /// The ones the user can switch to (System Settings › Keyboard › Input Sources).
    static func available() -> [InputSource] {
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as CFString,
            kTISPropertyInputSourceIsSelectCapable: true,
        ] as CFDictionary
        return sources(matching: filter).compactMap { source in
            guard let id = string(of: source, kTISPropertyInputSourceID) else { return nil }
            return InputSource(id: id, name: string(of: source, kTISPropertyLocalizedName) ?? id)
        }
    }

    @discardableResult
    static func select(_ id: String) -> Bool {
        guard let source = sources(matching: [kTISPropertyInputSourceID: id] as CFDictionary).first else {
            return false
        }
        return TISSelectInputSource(source) == noErr
    }

    private static func sources(matching filter: CFDictionary) -> [TISInputSource] {
        TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func string(of source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
