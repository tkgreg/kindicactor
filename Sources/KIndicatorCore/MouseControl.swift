import Foundation

/// A mouse's side buttons, as macOS numbers them from 0 (left, right, middle, back, forward).
package enum MouseButton: String, Codable, CaseIterable, Sendable {
    case back, forward

    package init?(buttonNumber: Int64) {
        switch buttonNumber {
        case 3: self = .back
        case 4: self = .forward
        default: return nil
        }
    }

    package var buttonNumber: Int64 {
        switch self {
        case .back: 3
        case .forward: 4
        }
    }
}

/// What double-clicking each side button does.
package struct MouseMapping: ActionMapping {
    package var back: KeyAction?
    package var forward: KeyAction?

    package init() {}

    package init(back: KeyAction? = nil, forward: KeyAction? = nil) {
        self.back = back
        self.forward = forward
    }

    package subscript(button: MouseButton) -> KeyAction? {
        get {
            switch button {
            case .back: back
            case .forward: forward
            }
        }
        set {
            switch button {
            case .back: back = newValue
            case .forward: forward = newValue
            }
        }
    }
}

/// Mouse double-clicks: double-clicking Back or Forward runs an action, for all apps or the
/// frontmost one, while a single click still goes back or forward.
package struct MouseControl: Codable, Equatable, Sendable {
    package var enabled = false
    /// How long a click waits for a second one, in seconds.
    package var doubleClickInterval = 0.3
    package var allApps = MouseMapping()
    package var apps: [AppActions<MouseMapping>] = []

    package static let intervals = 0.2...0.5

    package init(enabled: Bool = false, doubleClickInterval: Double = 0.3, allApps: MouseMapping = MouseMapping(),
                 apps: [AppActions<MouseMapping>] = []) {
        self.enabled = enabled
        self.doubleClickInterval = doubleClickInterval
        self.allApps = allApps
        self.apps = apps
    }

    /// What double-clicking `button` does while the app with `bundleID` is frontmost.
    package func action(for button: MouseButton, app bundleID: String?) -> KeyAction {
        MouseMapping.action(for: button, app: bundleID, allApps: allApps, apps: apps)
    }
}

/// Tells single clicks of the side buttons from double ones. A press of a button that has a
/// double-click action is held back. A second press within the interval runs the action, and
/// neither click reaches the app; otherwise the click is sent on as it was, that much later.
/// Another button, or the interval running out while the button is still down, sends it on
/// at once.
package struct DoubleClick: Equatable, Sendable {
    package enum Phase: Equatable, Sendable {
        case idle
        /// The first press, held back, made at `since`.
        case pressed(MouseButton, since: Double)
        /// The first press and its release, held back.
        case clicked(MouseButton, since: Double)
        /// The second press ran the action; its release is held back too.
        case doubled(MouseButton)
    }

    package enum Effect: Equatable, Sendable {
        /// Send the press held back after all, and its release if `released`.
        case replay(MouseButton, released: Bool)
        /// Run the button's double-click action.
        case run(MouseButton)
    }

    /// Seconds a press waits for the second one.
    package var interval: Double
    package private(set) var phase = Phase.idle

    package init(interval: Double) {
        self.interval = interval
    }

    /// When `timeout` is due, while a press is held back.
    package var deadline: Double? {
        switch phase {
        case .pressed(_, let since), .clicked(_, let since): since + interval
        case .idle, .doubled: nil
        }
    }

    /// A press or release of `button` at `time`, in seconds; `wanted` when a press has a
    /// double-click action. Says whether to let it through, and what to do before.
    package mutating func handle(_ button: MouseButton, isDown: Bool, at time: Double,
                                 wanted: Bool) -> (pass: Bool, effects: [Effect]) {
        // A second press that comes too late: the first was a single click.
        var effects = deadline.map { time >= $0 ? timeout(at: time) : [] } ?? []
        switch phase {
        case .idle:
            guard isDown && wanted else { return (true, effects) }
            phase = .pressed(button, since: time)
            return (false, effects)
        case .pressed(let held, let since):
            if button == held && !isDown {
                phase = .clicked(held, since: since)
                return (false, effects)
            }
            effects.append(.replay(held, released: false))
        case .clicked(let held, _):
            if button == held && isDown {
                phase = .doubled(held)
                return (false, effects + [.run(held)])
            }
            effects.append(.replay(held, released: true))
        case .doubled(let held):
            if button == held && !isDown {
                phase = .idle
                return (false, effects)
            }
        }
        // Anything else: whatever was held back goes first, then this as if nothing was.
        phase = .idle
        let next = handle(button, isDown: isDown, at: time, wanted: wanted)
        return (next.pass, effects + next.effects)
    }

    /// The interval since the held press ran out: it was a single click, or the button is
    /// being held down.
    package mutating func timeout(at time: Double) -> [Effect] {
        guard let deadline, time >= deadline else { return [] }
        return flush()
    }

    /// Sends on whatever is held back, e.g. when turned off.
    package mutating func flush() -> [Effect] {
        let effects: [Effect] = switch phase {
        case .pressed(let held, _): [.replay(held, released: false)]
        case .clicked(let held, _): [.replay(held, released: true)]
        case .idle, .doubled: []
        }
        phase = .idle
        return effects
    }
}
