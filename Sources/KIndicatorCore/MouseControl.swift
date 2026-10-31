import Foundation

/// A mouse button KIndicator can give actions: the middle, Back and Forward buttons, as macOS
/// numbers them from 0 (left, right, middle, back, forward), or a button the mouse sends as
/// a key, such as F13.
package enum MouseButton: Hashable, Sendable {
    case middle, back, forward
    case key(Hotkey)

    /// The mouse's own buttons, before any keys.
    package static let buttons: [MouseButton] = [.middle, .back, .forward]

    package init?(buttonNumber: Int64) {
        switch buttonNumber {
        case 2: self = .middle
        case 3: self = .back
        case 4: self = .forward
        default: return nil
        }
    }

    /// Nil for a key.
    package var buttonNumber: Int64? {
        switch self {
        case .middle: 2
        case .back: 3
        case .forward: 4
        case .key: nil
        }
    }

    package var title: String {
        switch self {
        case .middle: "Middle"
        case .back: "Back"
        case .forward: "Forward"
        case .key(let hotkey): hotkey.display
        }
    }

    /// How settings name it: "back", or "key 105 0 F13" (key code, modifiers, name).
    fileprivate var name: String {
        switch self {
        case .middle: "middle"
        case .back: "back"
        case .forward: "forward"
        case .key(let hotkey): "key \(hotkey.keyCode) \(hotkey.modifiers) \(hotkey.keyName)"
        }
    }

    fileprivate init?(name: String) {
        switch name {
        case "middle": self = .middle
        case "back": self = .back
        case "forward": self = .forward
        default:
            let parts = name.split(separator: " ", maxSplits: 3)
            guard parts.count == 4, parts[0] == "key",
                  let keyCode = UInt16(parts[1]), let modifiers = UInt(parts[2]) else { return nil }
            self = .key(Hotkey(keyCode: keyCode, modifiers: modifiers, keyName: String(parts[3])))
        }
    }
}

/// Buttons are stored by name, also as dictionary keys, so settings read {"back": …}.
extension MouseButton: Codable, CodingKeyRepresentable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    package var codingKey: CodingKey { Key(stringValue: name) }

    package init?<T: CodingKey>(codingKey: T) {
        self.init(name: codingKey.stringValue)
    }

    package init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let button = MouseButton(name: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No button \(name)"))
        }
        self = button
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

/// A click or a double-click of a button.
package enum MouseInput: Hashable, Sendable {
    case click(MouseButton)
    case doubleClick(MouseButton)
}

/// What clicking and double-clicking each button does. Nothing (or no action at all) leaves
/// the button to click as usual.
package struct MouseMapping: ActionMapping {
    package var clicks: [MouseButton: KeyAction] = [:]
    package var doubleClicks: [MouseButton: KeyAction] = [:]

    package init() {}

    package init(clicks: [MouseButton: KeyAction] = [:], doubleClicks: [MouseButton: KeyAction] = [:]) {
        self.clicks = clicks
        self.doubleClicks = doubleClicks
    }

    package subscript(input: MouseInput) -> KeyAction? {
        get {
            switch input {
            case .click(let button): clicks[button]
            case .doubleClick(let button): doubleClicks[button]
            }
        }
        set {
            switch input {
            case .click(let button): clicks[button] = newValue
            case .doubleClick(let button): doubleClicks[button] = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case clicks, doubleClicks
        /// Before clicks had actions, only Back and Forward had, for a double-click.
        case back, forward
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clicks = try container.decodeIfPresent([MouseButton: KeyAction].self, forKey: .clicks) ?? [:]
        doubleClicks = try container.decodeIfPresent([MouseButton: KeyAction].self, forKey: .doubleClicks) ?? [:]
        if let back = try container.decodeIfPresent(KeyAction.self, forKey: .back) { doubleClicks[.back] = back }
        if let forward = try container.decodeIfPresent(KeyAction.self, forKey: .forward) { doubleClicks[.forward] = forward }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clicks, forKey: .clicks)
        try container.encode(doubleClicks, forKey: .doubleClicks)
    }

    mutating func forget(_ button: MouseButton) {
        clicks[button] = nil
        doubleClicks[button] = nil
    }

    /// Back and Forward as ⌘[ and ⌘], which most apps take for back and forward: Safari
    /// ignores the buttons themselves.
    package static let navigation = MouseMapping(clicks: [
        .back: .shortcut(KeyAction.Shortcuts.back),
        .forward: .shortcut(KeyAction.Shortcuts.forward),
    ])
}

/// Mouse buttons: clicking or double-clicking the middle, Back or Forward button runs an
/// action, for all apps or the frontmost one.
package struct MouseControl: Codable, Equatable, Sendable {
    package var enabled = false
    /// How long a click waits for a second one, in seconds.
    package var doubleClickInterval = 0.3
    /// Keys the mouse sends for buttons of its own, e.g. F13: each gets actions like a button.
    package var keys: [Hotkey] = []
    package var allApps = MouseMapping()
    package var apps: [AppActions<MouseMapping>] = []

    package static let intervals = 0.2...0.5

    package init(enabled: Bool = false, doubleClickInterval: Double = 0.3, keys: [Hotkey] = [],
                 allApps: MouseMapping = MouseMapping(), apps: [AppActions<MouseMapping>] = []) {
        self.enabled = enabled
        self.doubleClickInterval = doubleClickInterval
        self.keys = keys
        self.allApps = allApps
        self.apps = apps
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, doubleClickInterval, keys, allApps, apps
    }

    /// Fields missing from older settings keep their defaults.
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        doubleClickInterval = try container.decodeIfPresent(Double.self, forKey: .doubleClickInterval) ?? 0.3
        keys = try container.decodeIfPresent([Hotkey].self, forKey: .keys) ?? []
        allApps = try container.decodeIfPresent(MouseMapping.self, forKey: .allApps) ?? MouseMapping()
        apps = try container.decodeIfPresent([AppActions<MouseMapping>].self, forKey: .apps) ?? []
    }

    /// The buttons with actions to set: the mouse's own, then its keys.
    package var allButtons: [MouseButton] {
        MouseButton.buttons + keys.map(MouseButton.key)
    }

    /// Forgets a key and its actions.
    package mutating func removeKey(_ hotkey: Hotkey) {
        keys.removeAll { $0 == hotkey }
        allApps.forget(.key(hotkey))
        for index in apps.indices { apps[index].mapping.forget(.key(hotkey)) }
    }

    /// What `input` does while the app with `bundleID` is frontmost.
    package func action(for input: MouseInput, app bundleID: String?) -> KeyAction {
        MouseMapping.action(for: input, app: bundleID, allApps: allApps, apps: apps)
    }

    /// Which of `button`'s clicks have actions in that app.
    package func actions(for button: MouseButton, app bundleID: String?) -> ButtonActions {
        ButtonActions(click: action(for: .click(button), app: bundleID) != .nothing,
                      doubleClick: action(for: .doubleClick(button), app: bundleID) != .nothing)
    }
}

/// Whether a button's click and double-click have actions in the frontmost app.
package struct ButtonActions: Equatable, Sendable {
    package var click: Bool
    package var doubleClick: Bool

    package init(click: Bool = false, doubleClick: Bool = false) {
        self.click = click
        self.doubleClick = doubleClick
    }
}

/// Tells clicks from double-clicks and decides what reaches the app. A button without actions
/// clicks as usual. One with only a click action runs it on the press, and the click doesn't
/// reach the app. One with a double-click action holds its press back: a second press within
/// the interval runs the double-click action; otherwise the click runs its action, or is
/// sent on as it was, that much later. Another button, or the interval running out while the
/// button is still down, settles the held press at once. A mouse key arrives as a press and
/// a release at once, and is never sent on: only its actions run.
package struct DoubleClick: Equatable, Sendable {
    package enum Phase: Equatable, Sendable {
        case idle
        /// The first press, held back, made at `since`; `clickRuns` when the click has an action.
        case pressed(MouseButton, since: Double, clickRuns: Bool)
        /// The first press and its release, held back.
        case clicked(MouseButton, since: Double, clickRuns: Bool)
    }

    package enum Effect: Equatable, Sendable {
        /// Send the press held back after all, and its release if `released`.
        case replay(MouseButton, released: Bool)
        /// Run the button's click action.
        case click(MouseButton)
        /// Run the button's double-click action.
        case doubleClick(MouseButton)
    }

    /// Seconds a press waits for the second one.
    package var interval: Double
    package private(set) var phase = Phase.idle
    /// Buttons whose press ran an action: their release is held back too.
    package private(set) var swallowing: Set<MouseButton> = []

    package init(interval: Double) {
        self.interval = interval
    }

    /// When `timeout` is due, while a press is held back.
    package var deadline: Double? {
        switch phase {
        case .pressed(_, let since, _), .clicked(_, let since, _): since + interval
        case .idle: nil
        }
    }

    /// A press or release of `button` at `time`, in seconds; `actions` are the button's in the
    /// frontmost app. Says whether to let it through, and what to do before.
    package mutating func handle(_ button: MouseButton, isDown: Bool, at time: Double,
                                 actions: ButtonActions) -> (pass: Bool, effects: [Effect]) {
        // A second press that comes too late: the first was a single click.
        var effects = deadline.map { time >= $0 ? timeout(at: time) : [] } ?? []
        switch phase {
        case .idle:
            if !isDown {
                return (swallowing.remove(button) == nil, effects)
            }
            if actions.doubleClick {
                phase = .pressed(button, since: time, clickRuns: actions.click)
                return (false, effects)
            }
            if actions.click {
                swallowing.insert(button)
                return (false, effects + [.click(button)])
            }
            return (true, effects)
        case .pressed(let held, let since, let clickRuns):
            if button == held && !isDown {
                phase = .clicked(held, since: since, clickRuns: clickRuns)
                return (false, effects)
            }
            effects += settle()
        case .clicked(let held, _, _):
            if button == held && isDown {
                phase = .idle
                swallowing.insert(held)
                return (false, effects + [.doubleClick(held)])
            }
            effects += settle()
        }
        // Anything else: the held press settled first, then this as if nothing was held.
        let next = handle(button, isDown: isDown, at: time, actions: actions)
        return (next.pass, effects + next.effects)
    }

    /// The interval since the held press ran out: it was a single click, or the button is
    /// being held down.
    package mutating func timeout(at time: Double) -> [Effect] {
        guard let deadline, time >= deadline else { return [] }
        return settle()
    }

    /// Settles whatever is held back, e.g. when turned off.
    package mutating func flush() -> [Effect] {
        let effects = settle()
        swallowing = []
        return effects
    }

    /// The held press was a single click: its action runs, or it's sent on.
    private mutating func settle() -> [Effect] {
        defer { phase = .idle }
        switch phase {
        case .idle:
            return []
        case .pressed(let held, _, let clickRuns):
            // Still down: with an action, its release is held back when it comes.
            guard clickRuns else { return [.replay(held, released: false)] }
            swallowing.insert(held)
            return [.click(held)]
        case .clicked(let held, _, let clickRuns):
            return clickRuns ? [.click(held)] : [.replay(held, released: true)]
        }
    }
}
