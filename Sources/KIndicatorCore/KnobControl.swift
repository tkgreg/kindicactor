import Foundation

/// What can be done with the knob.
package enum KnobInput: String, Codable, CaseIterable, Sendable {
    case turnLeft, turnRight, press
}

/// Keys KIndicator presses the way the Mac's own media keys do.
package enum MediaKey: String, Codable, CaseIterable, Sendable {
    case volumeDown, volumeUp, mute
    /// A quarter of a volume step, as the volume keys with ⌥⇧ held.
    case preciseVolumeDown, preciseVolumeUp
    case previousTrack, playPause, nextTrack
    case brightnessDown, brightnessUp

    package var title: String {
        switch self {
        case .volumeDown: "Volume −"
        case .volumeUp: "Volume +"
        case .mute: "Mute"
        case .preciseVolumeDown: "Precise Volume −"
        case .preciseVolumeUp: "Precise Volume +"
        case .previousTrack: "Previous Track"
        case .playPause: "Play/Pause"
        case .nextTrack: "Next Track"
        case .brightnessDown: "Brightness −"
        case .brightnessUp: "Brightness +"
        }
    }
}

/// What KIndicator does for one of the knob's inputs.
package enum KnobAction: Codable, Hashable, Sendable {
    case nothing
    case media(MediaKey)
    /// Pressed in the frontmost app.
    case shortcut(Hotkey)

    package var title: String {
        switch self {
        case .nothing: "Nothing"
        case .media(let key): key.title
        case .shortcut(let hotkey): hotkey.display
        }
    }
}

/// An action per input. Nil leaves the input to the mapping below: an app's falls back to
/// the one for all apps, and that one to nothing.
package struct KnobMapping: Codable, Hashable, Sendable {
    package var turnLeft: KnobAction?
    package var turnRight: KnobAction?
    package var press: KnobAction?

    package init(turnLeft: KnobAction? = nil, turnRight: KnobAction? = nil, press: KnobAction? = nil) {
        self.turnLeft = turnLeft
        self.turnRight = turnRight
        self.press = press
    }

    package subscript(input: KnobInput) -> KnobAction? {
        get {
            switch input {
            case .turnLeft: turnLeft
            case .turnRight: turnRight
            case .press: press
            }
        }
        set {
            switch input {
            case .turnLeft: turnLeft = newValue
            case .turnRight: turnRight = newValue
            case .press: press = newValue
            }
        }
    }
}

/// The knob's actions in one app.
package struct KnobAppMapping: Codable, Hashable, Identifiable, Sendable {
    package var bundleID: String
    package var name: String
    /// Where the app was when it was added, for its icon.
    package var path: String?
    package var mapping: KnobMapping

    package init(bundleID: String, name: String, path: String? = nil, mapping: KnobMapping = KnobMapping()) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.mapping = mapping
    }

    package var id: String { bundleID }
}

/// A whole mapping to start from.
package struct KnobPreset: Identifiable, Sendable {
    package var name: String
    package var mapping: KnobMapping

    package var id: String { name }

    package static let volume = KnobPreset(name: "Volume", mapping: KnobMapping(
        turnLeft: .media(.volumeDown), turnRight: .media(.volumeUp), press: .media(.mute)))
    package static let preciseVolume = KnobPreset(name: "Precise Volume", mapping: KnobMapping(
        turnLeft: .media(.preciseVolumeDown), turnRight: .media(.preciseVolumeUp), press: .media(.mute)))
    package static let tracks = KnobPreset(name: "Tracks", mapping: KnobMapping(
        turnLeft: .media(.previousTrack), turnRight: .media(.nextTrack), press: .media(.playPause)))
    package static let brightness = KnobPreset(name: "Display Brightness", mapping: KnobMapping(
        turnLeft: .media(.brightnessDown), turnRight: .media(.brightnessUp), press: .nothing))
    // Virtual key codes: kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_ANSI_0, kVK_ANSI_Z, kVK_Tab.
    package static let zoom = KnobPreset(name: "Zoom", mapping: KnobMapping(
        turnLeft: .shortcut(Hotkey(keyCode: 0x1B, modifiers: Hotkey.command, keyName: "-")),
        turnRight: .shortcut(Hotkey(keyCode: 0x18, modifiers: Hotkey.command, keyName: "=")),
        press: .shortcut(Hotkey(keyCode: 0x1D, modifiers: Hotkey.command, keyName: "0"))))
    package static let undo = KnobPreset(name: "Undo and Redo", mapping: KnobMapping(
        turnLeft: .shortcut(Hotkey(keyCode: 0x06, modifiers: Hotkey.command, keyName: "Z")),
        turnRight: .shortcut(Hotkey(keyCode: 0x06, modifiers: Hotkey.command | Hotkey.shift, keyName: "Z")),
        press: .nothing))
    package static let tabs = KnobPreset(name: "Tabs", mapping: KnobMapping(
        turnLeft: .shortcut(Hotkey(keyCode: 0x30, modifiers: Hotkey.control | Hotkey.shift, keyName: "⇥")),
        turnRight: .shortcut(Hotkey(keyCode: 0x30, modifiers: Hotkey.control, keyName: "⇥")),
        press: .nothing))

    package static let all = [volume, preciseVolume, tracks, brightness, zoom, undo, tabs]
}

/// Knob Control: the knob sends F18, F19 and F20 on some layers, and KIndicator turns them
/// into actions, for all apps or the frontmost one.
package struct KnobControl: Codable, Equatable, Sendable {
    package var enabled = false
    /// Layers where the knob sends F18-F20; on the others it keeps its own keys (on the
    /// V6's Fn layer: lighting).
    package var layers: Set<Int> = [0]
    package var allApps = KnobPreset.volume.mapping
    package var apps: [KnobAppMapping] = []

    package init(enabled: Bool = false, layers: Set<Int> = [0], allApps: KnobMapping = KnobPreset.volume.mapping,
                 apps: [KnobAppMapping] = []) {
        self.enabled = enabled
        self.layers = layers
        self.allApps = allApps
        self.apps = apps
    }

    /// The keys the knob sends while KIndicator has it: F18 left, F19 right, F20 pressed.
    package static let keys = KnobKeys(turnLeft: 0x006D, turnRight: 0x006E, press: 0x006F)

    /// What to do for `input` while the app with `bundleID` is frontmost.
    package func action(for input: KnobInput, app bundleID: String?) -> KnobAction {
        let app = bundleID.flatMap { id in apps.first { $0.bundleID == id } }
        return app?.mapping[input] ?? allApps[input] ?? .nothing
    }
}
