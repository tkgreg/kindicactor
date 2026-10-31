import Foundation

/// Keys KIndicator presses the way the Mac's own media keys do.
package enum MediaKey: String, Codable, CaseIterable, Sendable {
    case volumeDown, volumeUp, mute
    /// Quarter volume steps, as the volume keys with ⌥⇧ held; more of them while the knob
    /// spins (`VolumeAcceleration`).
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

/// What KIndicator does for a knob turn or a mouse double-click: presses a media key or a
/// shortcut, or nothing.
package enum KeyAction: Codable, Hashable, Sendable {
    case nothing
    case media(MediaKey)
    /// Pressed in the frontmost app.
    case shortcut(Hotkey)

    package var title: String {
        switch self {
        case .nothing: "Nothing"
        case .media(let key): key.title
        case .shortcut(let hotkey): Shortcuts.all.first { $0.hotkey == hotkey }?.name ?? hotkey.display
        }
    }

    /// Shortcuts most apps share, offered by name. Virtual key codes: kVK_ANSI_LeftBracket,
    /// kVK_ANSI_RightBracket, kVK_ANSI_W, kVK_ANSI_T, kVK_UpArrow, kVK_DownArrow.
    package enum Shortcuts {
        package static let back = Hotkey(keyCode: 0x21, modifiers: Hotkey.command, keyName: "[")
        package static let forward = Hotkey(keyCode: 0x1E, modifiers: Hotkey.command, keyName: "]")
        package static let closeWindow = Hotkey(keyCode: 0x0D, modifiers: Hotkey.command, keyName: "W")
        package static let newTab = Hotkey(keyCode: 0x11, modifiers: Hotkey.command, keyName: "T")
        package static let reopenTab = Hotkey(keyCode: 0x11, modifiers: Hotkey.command | Hotkey.shift, keyName: "T")
        /// The system's default shortcuts for these, in Keyboard Shortcuts › Mission Control.
        package static let missionControl = Hotkey(keyCode: 0x7E, modifiers: Hotkey.control, keyName: "↑")
        package static let appWindows = Hotkey(keyCode: 0x7D, modifiers: Hotkey.control, keyName: "↓")

        package static let all: [(name: String, hotkey: Hotkey)] = [
            ("Back", back), ("Forward", forward), ("Close Window", closeWindow), ("New Tab", newTab),
            ("Reopen Closed Tab", reopenTab), ("Mission Control", missionControl), ("App Windows", appWindows),
        ]
    }

    /// How many times to press for one click of the knob, `interval` seconds after the click
    /// before in the same direction: precise volume speeds up while the knob spins.
    package func presses(after interval: Double?) -> Int {
        switch self {
        case .media(.preciseVolumeDown), .media(.preciseVolumeUp):
            VolumeAcceleration.quarterSteps(for: VolumeAcceleration.step(after: interval))
        default: 1
        }
    }
}

/// Precise volume speeds up while the knob spins: the sooner a click follows the one before,
/// the more of the volume it moves. The volume key with ⌥⇧ moves a quarter step, so a click
/// presses it as many times as comes nearest.
package enum VolumeAcceleration {
    /// The share of full volume a key's quarter step moves: 1/16 per step, 4 quarters each.
    package static let quarterStep = 1.0 / 64

    /// The share of full volume a click should move, by seconds since the click before.
    package static func step(after interval: Double?) -> Double {
        guard let interval else { return 0.01 }
        switch interval {
        case ..<0.04: return 0.08 // a very fast spin
        case ..<0.10: return 0.04 // a medium one
        case ..<0.20: return 0.02 // a normal turn
        default: return 0.01 // slow, fine-tuning
        }
    }

    /// The quarter steps nearest to `step`, at least one: 1, 1, 3 and 5 for 1, 2, 4 and 8%.
    package static func quarterSteps(for step: Double) -> Int {
        max(1, Int((step / quarterStep).rounded()))
    }
}

/// One action per input of a device, e.g. the knob's turns and press. Nil leaves the input to
/// the mapping below: an app's falls back to the one for all apps, and that one to nothing.
package protocol ActionMapping: Codable, Hashable, Sendable {
    associatedtype Input: Hashable, Sendable

    init()
    subscript(input: Input) -> KeyAction? { get set }
}

extension ActionMapping {
    /// What to do for `input` while the app with `bundleID` is frontmost.
    package static func action(for input: Input, app bundleID: String?, allApps: Self,
                               apps: [AppActions<Self>]) -> KeyAction {
        let app = bundleID.flatMap { id in apps.first { $0.bundleID == id } }
        return app?.mapping[input] ?? allApps[input] ?? .nothing
    }
}

/// A device's actions in one app.
package struct AppActions<Mapping: ActionMapping>: Codable, Hashable, Identifiable, Sendable {
    package var bundleID: String
    package var name: String
    /// Where the app was when it was added, for its icon.
    package var path: String?
    package var mapping: Mapping

    package init(bundleID: String, name: String, path: String? = nil, mapping: Mapping = Mapping()) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.mapping = mapping
    }

    package var id: String { bundleID }
}
