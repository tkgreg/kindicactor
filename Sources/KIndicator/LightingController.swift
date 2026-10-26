import AppKit
import Combine
import KIndicatorCore
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "lighting")

/// Reads and changes the keyboard's RGB lighting: per layer, off while the displays sleep,
/// brightness following the room's light, and the mic indicator's key. What to send is
/// decided by `LightingPlan`, `RoomLightPlan` and `KeyColorsPlan`; this class reads the
/// keyboard, sends the requests and keeps the state.
///
/// `saved` is the lighting stored on the keyboard. A layer's own lighting, or Off while the
/// Mac's displays sleep, is put on top without saving, and `saved` comes back on layers set
/// to Keep. The room's brightness and the mic indicator's key colours aren't saved either.
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
    private let roomLight: AmbientLightSensor
    /// The brightness shown instead of the saved one, following the room's light, not saved;
    /// nil while the keyboard shows its saved brightness.
    private var roomBrightness: UInt8?
    /// The keyboard may have restarted and show its saved brightness, so the room's is sent again.
    private var roomBrightnessStale = false
    private var fadeTicker: Task<Void, Never>?
    /// Per-key colours shown over the keyboard's own: the mic indicator, and a layer drawn
    /// key by key meanwhile.
    private var keyColors = KeyColors()
    /// The keyboard may have lost the colours shown (it was disconnected, or another app
    /// had it open), so they're sent again.
    private var keyColorsStale = false
    /// A layer's Solid Color, drawn key by key while the mic indicator shows.
    private var keyFill: KeyColor?
    /// When the mic indicator came on, for its pulse.
    private var indicatorSince: ContinuousClock.Instant?
    private var pulseTicker: Task<Void, Never>?
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

    init(monitor: KeyboardMonitor, settings: AppSettings, microphone: MicrophoneMonitor, maps: KeyboardMaps,
         roomLight: AmbientLightSensor) {
        self.monitor = monitor
        self.settings = settings
        self.microphone = microphone
        self.maps = maps
        self.roomLight = roomLight
        keptEffect = (UserDefaults.standard.object(forKey: Self.keptEffectKey) as? Int).flatMap(UInt8.init(exactly:))
    }

    func start() {
        // @Published fires before the value changes; the queued work runs after, so it sees it.
        monitor.$status.removeDuplicates()
            .sink { [weak self] _ in
                self?.keyColorsStale = true
                self?.roomBrightnessStale = true
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
        roomLight.$lux.combineLatest(settings.$roomBrightness)
            .map { lux, room in room.enabled ? lux.map(room.brightness) : nil }
            .removeDuplicates()
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
            let unlayered = LightingPlan.shown(saved: lighting, applied: nil, brightness: self.roomBrightness)
            guard await self.write(unlayered, over: LightingPlan.shown(saved: before, applied: self.applied,
                                                                       brightness: self.roomBrightness)) else {
                log.error("change failed: keyboard didn't confirm")
                return
            }
            await self.save()
            log.notice("saved \(LightingEffect.name(lighting.effect), privacy: .public)")
            if let applied = self.applied {
                await self.write(LightingPlan.shown(saved: lighting, applied: applied, brightness: self.roomBrightness),
                                 over: unlayered)
            }
        }
    }

    /// Gives the keys their own colours and puts the saved lighting back, before the app quits.
    func restoreBeforeQuit() async {
        await withCheckedContinuation { continuation in
            enqueue {
                self.pulseTicker?.cancel()
                self.fadeTicker?.cancel()
                for request in KeyColorsPlan.requests(setting: self.ownColorsOfShownKeys) {
                    _ = await self.monitor.request(request)
                }
                if let saved = self.saved, self.applied != nil || self.roomBrightness != nil {
                    await self.write(saved, over: LightingPlan.shown(saved: saved, applied: self.applied,
                                                                     brightness: self.roomBrightness))
                    if self.roomBrightness.map({ $0 != saved.brightness }) == true {
                        await self.correctSavedBrightness()
                    }
                }
                continuation.resume()
            }
        }
    }

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        enqueue {
            self.syncQueued = false
            await self.syncLayerLighting()
            await self.syncRoomBrightness()
            await self.syncKeyColors()
        }
    }

    // MARK: - Per-layer lighting

    private func syncLayerLighting() async {
        guard monitor.isConnected, let layer = monitor.layer else { return }
        let lightsOff = displaysAsleep && settings.lightsOffWhileDisplaysSleep
        let indicator = settings.micIndicator
        let (target, fill) = LightingPlan.layerTarget(
            layerLighting: settings.layerLightingEnabled ? settings.lighting(for: layer) : nil,
            lightsOff: lightsOff,
            indicatorShows: indicator.enabled && microphone.inUse && maps.ledMap?.led(at: indicator.key) != nil,
            applied: applied, saved: saved)
        if fill != keyFill {
            log.notice("layer \(layer) lighting: \(fill == nil ? "as usual" : "drawn key by key for the mic indicator", privacy: .public)")
            keyFill = fill
        }
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
            guard await write(LightingPlan.shown(saved: saved, applied: target, brightness: roomBrightness),
                              over: LightingPlan.shown(saved: saved, applied: applied, brightness: roomBrightness))
            else { return }
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
        let restore = LightingPlan.restore(saved: saved, applied: applied, brightness: roomBrightness, keyboardShows: now)
        guard await write(LightingPlan.shown(saved: restore.lighting, applied: nil, brightness: roomBrightness),
                          over: restore.current) else { return }
        self.saved = restore.lighting
        if restore.needsSave { await save() }
        self.applied = nil
        lightsOffShown = false
    }

    // MARK: - Room light

    /// Fades the brightness toward the room's, one step per sync, or back to the saved one.
    private func syncRoomBrightness() async {
        guard monitor.isConnected, let saved else { return updateFade(false) }
        let shown = LightingPlan.shown(saved: saved, applied: applied, brightness: roomBrightness)
        // Brightness sent while the lights are off is ignored; the fade goes on once they're on.
        guard shown.effect != LightingEffect.off else { return updateFade(false) }
        if roomBrightnessStale {
            roomBrightnessStale = false
            if let roomBrightness, roomBrightness != saved.brightness {
                _ = await monitor.request(.setBrightness(roomBrightness))
            }
        }

        let room = settings.roomBrightness
        let target = room.enabled ? roomLight.lux.map(room.brightness) : nil
        let to = target ?? saved.brightness
        let from = roomBrightness ?? saved.brightness
        guard from != to else {
            roomBrightness = target
            return updateFade(false)
        }
        let next = RoomLightPlan.step(from: from, to: to)
        if fadeTicker == nil {
            let why = target == nil ? "saved" : "room \(Int(roomLight.lux ?? 0)) lux"
            log.notice("brightness \(from) → \(to) (\(why, privacy: .public))")
        }
        guard await write(LightingPlan.shown(saved: saved, applied: applied, brightness: next), over: shown) else {
            return updateFade(false)
        }
        roomBrightness = target == nil && next == saved.brightness ? nil : next
        if roomBrightness == nil { await correctSavedBrightness() }
        updateFade(next != to)
    }

    /// After the saved brightness is sent back over the room's: it may read one step lower
    /// (see `LightingPlan.brightnessCorrection`).
    private func correctSavedBrightness() async {
        guard let saved, let now = await get(.brightness),
              let correction = LightingPlan.brightnessCorrection(wrote: saved.brightness, reads: now[0]) else { return }
        log.notice("brightness \(saved.brightness) reads \(now[0]): sent one more")
        _ = await monitor.request(correction)
    }

    /// While the brightness fades, it changes about 30 times a second.
    private func updateFade(_ fading: Bool) {
        if fading, fadeTicker == nil {
            fadeTicker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33))
                    scheduleSync()
                }
            }
        } else if !fading {
            fadeTicker?.cancel()
            fadeTicker = nil
        }
    }

    // MARK: - Key colours

    /// Carries out `KeyColorsPlan`'s steps until there's nothing left to do, or the keyboard
    /// doesn't answer (the next sync tries again).
    private func syncKeyColors() async {
        guard monitor.isConnected else { return }
        let indicator = settings.micIndicator
        let isOn = indicator.enabled && microphone.inUse
        if !isOn {
            indicatorSince = nil
        } else if indicatorSince == nil {
            indicatorSince = .now
        }
        let overlay = KeyColorsPlan.overlay(
            indicator: indicator, micInUse: microphone.inUse,
            shownEffect: saved.map { LightingPlan.shown(saved: $0, applied: applied).effect },
            fill: keyFill, ledMap: maps.ledMap,
            elapsed: indicatorSince.map { (ContinuousClock.now - $0) / .seconds(1) } ?? 0)

        steps: while true {
            switch KeyColorsPlan.step(keyColors, overlay: overlay, ledCount: maps.ledMap?.ledCount ?? 0,
                                      stale: keyColorsStale) {
            case .nothing:
                break steps
            case .read(let requests):
                for request in requests {
                    guard case .getKeyColors(let first, let count) = request,
                          let reply = await monitor.request(request),
                          let colors = KeyboardReply.keyColors(reply, count: count) else { break steps }
                    for (offset, color) in colors.enumerated() {
                        keyColors.own[first + UInt8(offset)] = color
                    }
                }
            case .write(let requests, let result):
                for request in requests {
                    guard await monitor.request(request) != nil else { break steps }
                }
                if result.shown.count != keyColors.shown.count {
                    log.notice("key colours: \(result.shown.count) keys shown in another colour (mic indicator \(isOn ? "on" : "off", privacy: .public))")
                }
                keyColors = result
                keyColorsStale = false
            }
        }
        updatePulse(isOn && indicator.style == .pulse && !keyColors.shown.isEmpty)
    }

    /// While the indicator pulses, its colour changes about 30 times a second.
    private func updatePulse(_ pulsing: Bool) {
        if pulsing, pulseTicker == nil {
            pulseTicker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33))
                    scheduleSync()
                }
            }
        } else if !pulsing {
            pulseTicker?.cancel()
            pulseTicker = nil
        }
    }

    /// The own colours of the keys shown in another colour.
    private var ownColorsOfShownKeys: [UInt8: KeyColor] {
        keyColors.shown.keys.reduce(into: [:]) { own, led in own[led] = keyColors.own[led] }
    }

    // MARK: - Keyboard requests

    private func scheduleRefresh() {
        guard applied == nil, pendingChanges == 0, monitor.isConnected else { return }
        enqueue { await self.refreshSaved() }
    }

    private func refreshSaved() async {
        guard applied == nil, pendingChanges == 0, let read = await read() else { return }
        let lighting = LightingPlan.saved(keyboardShows: read, saved: saved, brightness: roomBrightness)
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

    /// Saves `saved`, which the keyboard shows (at the room's brightness, if it follows the room).
    private func save() async {
        // In case saving also stores the key colours, the keys shown get their own back meanwhile.
        for request in KeyColorsPlan.requests(setting: ownColorsOfShownKeys) {
            _ = await monitor.request(request)
        }
        // Saving stores the brightness shown, so the saved one shows meanwhile.
        let roomBrightness = roomBrightness.flatMap { $0 == saved?.brightness ? nil : $0 }
        if roomBrightness != nil, let saved {
            _ = await monitor.request(.setBrightness(saved.brightness))
            await correctSavedBrightness()
        }
        _ = await monitor.request(.saveLighting)
        if let roomBrightness {
            _ = await monitor.request(.setBrightness(roomBrightness))
        }
        for request in KeyColorsPlan.requests(setting: keyColors.shown) {
            _ = await monitor.request(request)
        }
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
