import AppKit
import Carbon
import Combine
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "knob")

/// Knob Control. Keychron Launcher can't put macros on the knob, so KIndicator sets it to send
/// F18, F19 and F20 on the chosen layers, saved on the keyboard as Launcher does, and gives it
/// its own keys back on the other layers or when turned off. The F-keys come back as global
/// hotkeys and become the actions set for the frontmost app.
///
/// What to write is decided by `KnobTakeover`; the knob's own keys are remembered here until
/// they're back on the keyboard.
@MainActor
final class KnobController: ObservableObject {
    enum State: Equatable {
        /// The knob sends its own keys.
        case off
        /// The knob sends F18-F20 on the chosen layers.
        case on
        /// The keyboard can't be changed now: not connected, or another app has it open.
        case waiting
        /// No known knob on this keyboard.
        case unsupported
        /// The keyboard didn't answer; tried again when it answers again.
        case failed
    }

    @Published private(set) var state = State.off
    /// Whether macOS lets KIndicator press keys (Accessibility).
    @Published private(set) var canPressKeys = KeyPresser.isAllowed

    /// What the knob sends, as Mac key codes, in `KnobInput` order.
    private static let fKeys = [kVK_F18, kVK_F19, kVK_F20]
    private static let ownKeysKey = "knobOwnKeys"

    private let monitor: KeyboardMonitor
    private let settings: AppSettings
    private let maps: KeyboardMaps
    private var syncing: Task<Void, Never>?
    private var syncAgain = false
    private var subscriptions: Set<AnyCancellable> = []

    init(monitor: KeyboardMonitor, settings: AppSettings, maps: KeyboardMaps) {
        self.monitor = monitor
        self.settings = settings
        self.maps = maps
    }

    /// The knob's own keys on each layer where it may send F18-F20, to give back.
    private var ownKeys: [Int: KnobKeys] {
        get {
            UserDefaults.standard.data(forKey: Self.ownKeysKey)
                .flatMap { try? JSONDecoder().decode([Int: KnobKeys].self, from: $0) } ?? [:]
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.ownKeysKey) }
    }

    func start() {
        settings.$knobControl.map(\.enabled).removeDuplicates()
            .sink { [weak self] in self?.listen($0) }
            .store(in: &subscriptions)
        // Other layers, another keyboard, or the keyboard answering again: Keychron Launcher
        // may have changed the knob meanwhile.
        settings.$knobControl.map { $0.enabled ? $0.layers : [] }.removeDuplicates().map { _ in () }
            .merge(with: monitor.$status.removeDuplicates().map { _ in () },
                   monitor.$layerCount.removeDuplicates().map { _ in () },
                   monitor.$productID.removeDuplicates().map { _ in () })
            .sink { [weak self] in self?.sync() }
            .store(in: &subscriptions)
    }

    /// Shows macOS's prompt for Accessibility unless KIndicator may already press keys.
    func requestPermission() {
        if !KeyPresser.isAllowed { KeyPresser.requestPermission() }
        refreshPermission()
    }

    func refreshPermission() {
        let allowed = KeyPresser.isAllowed
        if canPressKeys != allowed { canPressKeys = allowed }
    }

    /// A shortcut the knob's hotkeys would catch again, endlessly.
    static func isKnobKey(_ hotkey: Hotkey) -> Bool {
        hotkey.modifiers == 0 && fKeys.contains(Int(hotkey.keyCode))
    }

    // MARK: - Actions

    /// F18-F20 as global hotkeys while Knob Control is on.
    private func listen(_ enabled: Bool) {
        let bindings = zip(KnobInput.allCases, Self.fKeys).map { input, key -> HotkeyCenter.Binding in
            (hotkey: Hotkey(functionKey: key), action: { [weak self] in self?.handle(input) })
        }
        HotkeyCenter.shared.set(enabled ? bindings : [], for: .knob)
    }

    private func handle(_ input: KnobInput) {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let action = settings.knobControl.action(for: input, app: app)
        log.debug("\(input.rawValue, privacy: .public) in \(app ?? "-", privacy: .public): \(action.title, privacy: .public)")
        if case .shortcut(let hotkey) = action, Self.isKnobKey(hotkey) { return }
        KeyPresser.perform(action)
        if !canPressKeys { refreshPermission() }
    }

    // MARK: - The keyboard

    private func sync() {
        guard syncing == nil else {
            syncAgain = true
            return
        }
        syncing = Task {
            await apply()
            syncing = nil
            if syncAgain {
                syncAgain = false
                sync()
            }
        }
    }

    /// Reads what the knob sends on the layers concerned and writes what the plan says.
    private func apply() async {
        let control = settings.knobControl
        let ownKeys = self.ownKeys
        guard control.enabled || !ownKeys.isEmpty else { return setState(.off) }
        guard monitor.isConnected, let layerCount = monitor.layerCount else { return setState(.waiting) }
        guard let knob = maps.layout.flatMap(KnobLocation.init) else { return setState(.unsupported) }

        var now: [Int: KnobKeys] = [:]
        for layer in KnobTakeover.layersToRead(control, originals: ownKeys, layerCount: layerCount) {
            var keycodes: [UInt16] = []
            for request in knob.readRequests(layer: layer) {
                guard let reply = await monitor.request(request), let keycode = KeyboardReply.keycode(reply) else {
                    log.error("can't read the knob on layer \(layer)")
                    return setState(.failed)
                }
                keycodes.append(keycode)
            }
            now[layer] = KnobKeys(turnLeft: keycodes[0], turnRight: keycodes[1], press: keycodes[2])
        }

        let plan = KnobTakeover.plan(now: now, layers: control.enabled ? control.layers : [], originals: ownKeys)
        // Remembered first, so keys about to be replaced aren't lost if the app quits meanwhile.
        self.ownKeys = plan.originals
        for write in plan.writes {
            guard await monitor.request(knob.request(write)) != nil else {
                log.error("can't change the knob on layer \(write.layer)")
                return setState(.failed)
            }
            log.notice("knob on layer \(write.layer) \(write.input.rawValue, privacy: .public): \(Keycode.label(write.keycode), privacy: .public)")
        }
        self.ownKeys = plan.originalsAfterwards
        setState(control.enabled ? .on : .off)
    }

    private func setState(_ state: State) {
        guard self.state != state else { return }
        log.notice("knob: \(String(describing: state), privacy: .public)")
        self.state = state
    }
}
