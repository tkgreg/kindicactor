import AppKit
import Combine
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "lighting")

/// Reads and changes the keyboard's RGB lighting: per layer, off while the displays sleep,
/// and the mic indicator's key. What to send is decided by `LightingPlan` and
/// `MicIndicatorPlan`; this class reads the keyboard, sends the requests and keeps the state.
///
/// `saved` is the lighting stored on the keyboard. A layer's own lighting, or Off while the
/// Mac's displays sleep, is put on top without saving, and `saved` comes back on layers set
/// to Keep. The mic indicator changes one key's colour, also without saving.
@MainActor
final class LightingController: ObservableObject {
    /// The lighting stored on the keyboard; nil until it has been read.
    @Published private(set) var saved: Lighting? {
        didSet {
            if let effect = saved?.effect, effect != LightingEffect.off, effect != keptEffect { keptEffect = effect }
        }
    }

    /// The effect the keyboard keeps while its lights are off: the last one seen on.
    /// A layer's lighting replaces it, so it's put back before the lights go off.
    private var keptEffect: UInt8? {
        didSet { if let keptEffect { UserDefaults.standard.set(Int(keptEffect), forKey: Self.keptEffectKey) } }
    }
    private static let keptEffectKey = "keptLightingEffect"

    private let monitor: KeyboardMonitor
    private let settings: AppSettings
    private let microphone: MicrophoneMonitor
    private let maps: KeyboardMaps
    private var indicatorShown: ShownIndicator?
    /// The keyboard may have lost the indicator's colour (it was disconnected, or another
    /// app had it open), so it's sent again.
    private var indicatorStale = false
    /// Lighting shown on top of the saved one (a layer's, or Off while the displays sleep),
    /// not saved; nil while the keyboard shows the saved lighting.
    private var applied: LayerLighting?
    /// `applied` is Off for the displays' sleep.
    private var lightsOffShown = false
    private var displaysAsleep = false {
        didSet {
            guard displaysAsleep != oldValue else { return }
            log.notice("displays \(self.displaysAsleep ? "asleep" : "awake", privacy: .public)")
            scheduleSync()
        }
    }
    /// Menu changes not yet sent; a refresh in between would undo them in the menu.
    private var pendingChanges = 0
    private var queue: Task<Void, Never>?
    private var syncQueued = false
    private var refreshTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    init(monitor: KeyboardMonitor, settings: AppSettings, microphone: MicrophoneMonitor, maps: KeyboardMaps) {
        self.monitor = monitor
        self.settings = settings
        self.microphone = microphone
        self.maps = maps
        keptEffect = (UserDefaults.standard.object(forKey: Self.keptEffectKey) as? Int).flatMap(UInt8.init(exactly:))
    }

    func start() {
        // @Published fires before the value changes; the queued work runs after, so it sees it.
        monitor.$status.removeDuplicates()
            .sink { [weak self] _ in
                self?.indicatorStale = true
                self?.scheduleRefresh()
                self?.scheduleSync()
            }
            .store(in: &subscriptions)
        monitor.$layer.removeDuplicates()
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &subscriptions)
        settings.$layerLighting.combineLatest(settings.$layerLightingEnabled, settings.$lightsOffWhileDisplaysSleep,
                                              settings.$micIndicator)
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &subscriptions)
        // The indicator shows only with Per-key RGB, which the light keys can switch away from.
        $saved.map { $0?.effect }.removeDuplicates()
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &subscriptions)
        microphone.$recordingApps.map(\.isEmpty).removeDuplicates()
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &subscriptions)
        maps.$ledMap.removeDuplicates()
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &subscriptions)

        // Like a MacBook's keyboard backlight. Sleeping the Mac also counts: its displays
        // may be reported asleep too late to turn the lights off in time.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.willSleepNotification))
            .sink { [weak self] _ in self?.displaysAsleep = true }
            .store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.screensDidWakeNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didWakeNotification))
            .sink { [weak self] _ in self?.displaysAsleep = false }
            .store(in: &subscriptions)

        // Picks up changes made with the keyboard's light keys or in Keychron Launcher.
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                scheduleRefresh()
            }
        }
    }

    /// Changes the saved lighting, like Keychron Launcher does. The menu shows the new
    /// value at once; the keyboard gets it as soon as it answers.
    func change(_ update: (inout Lighting) -> Void) {
        guard let before = saved else {
            log.error("change ignored: lighting not read yet")
            return
        }
        var lighting = before
        update(&lighting)
        guard lighting != before else { return }
        log.notice("change requested: \(lighting.summary, privacy: .public) (was \(before.summary, privacy: .public))")
        saved = lighting
        pendingChanges += 1

        enqueue {
            defer { self.pendingChanges -= 1 }
            guard await self.monitor.waitUntilConnected() else {
                log.error("change dropped: keyboard not answering")
                return
            }
            // Saving stores whatever the keyboard shows, so a layer's own lighting makes way first.
            guard await self.write(lighting, over: LightingPlan.shown(saved: before, applied: self.applied)) else {
                log.error("change failed: keyboard didn't confirm")
                return
            }
            await self.save()
            log.notice("saved \(LightingEffect.name(lighting.effect), privacy: .public)")
            if let applied = self.applied {
                await self.write(LightingPlan.overlay(applied, on: lighting), over: lighting)
            }
        }
    }

    /// Puts the saved lighting back before the app quits, without waiting for replies.
    func restoreBeforeQuit() {
        if let indicatorShown {
            monitor.sendNow(.setKeyColors(first: indicatorShown.led, [indicatorShown.own]))
        }
        guard let applied, let saved else { return }
        LightingPlan.requests(from: LightingPlan.overlay(applied, on: saved), to: saved, keptEffect: keptEffect)
            .forEach(monitor.sendNow)
    }

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        enqueue {
            self.syncQueued = false
            await self.syncLayerLighting()
            await self.syncMicIndicator()
        }
    }

    // MARK: - Per-layer lighting

    private func syncLayerLighting() async {
        guard monitor.isConnected, let layer = monitor.layer else { return }
        let lightsOff = displaysAsleep && settings.lightsOffWhileDisplaysSleep
        let target = LightingPlan.target(
            layerLighting: settings.layerLightingEnabled ? settings.lighting(for: layer) : nil,
            lightsOff: lightsOff, applied: applied, saved: saved)
        guard target != applied else { return }

        // The keyboard may have restarted while its lights were off and show the saved
        // lighting again, so wake up through that: restoring it reads what the keyboard shows.
        if lightsOffShown, !lightsOff {
            await restoreSaved()
            guard applied == nil else { return }
            log.notice("lights back on")
            guard target != nil else { return }
        }

        if let target {
            // The 3 s refresh may not have seen lights just turned off with the keyboard's keys,
            // and colour sent before turning them back on is ignored: read them now.
            if applied == nil { await refreshSaved() }
            guard let saved else { return }
            guard await write(LightingPlan.overlay(target, on: saved),
                              over: LightingPlan.shown(saved: saved, applied: applied)) else { return }
            applied = target
            lightsOffShown = lightsOff
            log.notice("layer \(layer) lighting: \(lightsOff ? "off while displays sleep" : LightingEffect.name(target.effect), privacy: .public)")
        } else {
            await restoreSaved()
            log.notice("layer \(layer) lighting: saved")
        }
    }

    private func restoreSaved() async {
        guard let applied, let saved else {
            self.applied = nil
            lightsOffShown = false
            return
        }
        let now = await read()
        if let now { log.notice("keyboard shows \(now.summary, privacy: .public)") }
        let restore = LightingPlan.restore(saved: saved, applied: applied, keyboardShows: now)
        guard await write(restore.lighting, over: restore.current) else { return }
        if restore.needsSave { await save() }
        self.saved = restore.lighting
        self.applied = nil
        lightsOffShown = false
    }

    // MARK: - Mic indicator

    /// Carries out `MicIndicatorPlan`'s steps until there's nothing left to do, or the
    /// keyboard doesn't answer (the next sync tries again).
    private func syncMicIndicator() async {
        guard monitor.isConnected else { return }
        let wanted = MicIndicatorPlan.wanted(
            settings.micIndicator, micInUse: microphone.inUse,
            shownEffect: saved.map { LightingPlan.shown(saved: $0, applied: applied).effect }, ledMap: maps.ledMap)

        while true {
            switch MicIndicatorPlan.step(shown: indicatorShown, wanted: wanted, stale: indicatorStale) {
            case .nothing:
                return
            case .restore(let shown):
                guard await setKeyColor(shown.led, shown.own) else { return }
                indicatorShown = nil
                log.notice("mic indicator off: LED \(shown.led)")
            case .light(let wanted):
                guard let own = await keyColor(wanted.led) else { return }
                let color = MicIndicatorPlan.color(for: wanted, own: own)
                guard await setKeyColor(wanted.led, color) else { return }
                indicatorShown = ShownIndicator(led: wanted.led, own: own, shown: color)
                indicatorStale = false
                log.notice("mic indicator on: LED \(wanted.led) (own colour h\(own.hue) s\(own.saturation) v\(own.value))")
            case .recolor(let shown, let color):
                guard await setKeyColor(shown.led, color) else { return }
                indicatorShown = ShownIndicator(led: shown.led, own: shown.own, shown: color)
                indicatorStale = false
            }
        }
    }

    // MARK: - Keyboard requests

    private func scheduleRefresh() {
        guard applied == nil, pendingChanges == 0, monitor.isConnected else { return }
        enqueue { await self.refreshSaved() }
    }

    private func refreshSaved() async {
        guard applied == nil, pendingChanges == 0, let lighting = await read() else { return }
        if saved != lighting {
            log.notice("read \(lighting.summary, privacy: .public)")
            saved = lighting
        }
    }

    private func read() async -> Lighting? {
        guard let effect = await get(.effect) else { return nil }
        // Right after reconnecting over 2.4 GHz a reply can be garbage (effect 63 was seen).
        guard LightingEffect.ids.contains(effect[0]) else {
            log.error("read ignored: unknown effect \(effect[0])")
            return nil
        }
        guard let brightness = await get(.brightness),
              let speed = await get(.speed),
              let color = await get(.color), color.count >= 2
        else { return nil }
        return Lighting(effect: effect[0], brightness: brightness[0], speed: speed[0],
                        hue: color[0], saturation: color[1])
    }

    /// Sends the values of `target` that differ from `current`, stopping at the first
    /// one the keyboard doesn't answer.
    @discardableResult
    private func write(_ target: Lighting, over current: Lighting) async -> Bool {
        let requests = LightingPlan.requests(from: current, to: target, keptEffect: keptEffect)
        // "0217 0415ff": value id and data of each set request, in order.
        let sent = requests.map { $0.bytes.dropFirst(2).map { String(format: "%02x", $0) }.joined() }
        log.notice("write \(target.summary, privacy: .public) over \(current.summary, privacy: .public): \(sent.joined(separator: " "), privacy: .public)")
        for request in requests {
            guard await monitor.request(request) != nil else { return false }
        }
        return true
    }

    private func get(_ value: KeyboardRequest.LightingValue) async -> [UInt8]? {
        await monitor.request(.getLighting(value)).flatMap(KeyboardReply.lightingValue)
    }

    private func save() async {
        // In case saving also stores the key colours, the indicator's key makes way meanwhile.
        if let indicatorShown { await setKeyColor(indicatorShown.led, indicatorShown.own) }
        _ = await monitor.request(.saveLighting)
        if let indicatorShown { await setKeyColor(indicatorShown.led, indicatorShown.shown) }
    }

    private func keyColor(_ led: UInt8) async -> KeyColor? {
        await monitor.request(.getKeyColors(first: led, count: 1))
            .flatMap { KeyboardReply.keyColors($0, count: 1)?.first }
    }

    @discardableResult
    private func setKeyColor(_ led: UInt8, _ color: KeyColor) async -> Bool {
        await monitor.request(.setKeyColors(first: led, [color])) != nil
    }

    /// Runs keyboard work one piece at a time, in order.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }
}
