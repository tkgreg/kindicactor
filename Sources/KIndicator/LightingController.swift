import AppKit
import Combine
import OSLog

private let log = Logger(subsystem: "local.kindicator", category: "lighting")

/// Reads and changes the keyboard's RGB lighting, and switches it per layer.
///
/// `saved` is the lighting stored on the keyboard. A layer's own lighting is put on top
/// without saving, and `saved` comes back on layers set to Keep. While the Mac's displays
/// sleep, Off is put on top the same way.
///
/// Only values that differ from what the keyboard shows are sent: setting the effect is
/// slow (60–100 ms) and resending brightness loses a step to rounding each time.
///
/// While its lights are off the keyboard reports the effect as Off, ignores colour and
/// brightness, and keeps the effect its light key turns back on.
@MainActor
final class LightingController: ObservableObject {
    /// The lighting stored on the keyboard; nil until it has been read.
    @Published private(set) var saved: Lighting? {
        didSet {
            if let effect = saved?.effect, effect != 0, effect != keptEffect { keptEffect = effect }
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

    init(monitor: KeyboardMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
        keptEffect = (UserDefaults.standard.object(forKey: Self.keptEffectKey) as? Int).flatMap(UInt8.init(exactly:))
    }

    func start() {
        // @Published fires before the value changes; the queued work runs after, so it sees it.
        monitor.$status.removeDuplicates()
            .sink { [weak self] _ in self?.scheduleRefresh(); self?.scheduleSync() }
            .store(in: &subscriptions)
        monitor.$layer.removeDuplicates()
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &subscriptions)
        settings.$layerLighting.combineLatest(settings.$layerLightingEnabled, settings.$lightsOffWhileDisplaysSleep)
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
            guard await self.write(lighting, over: self.shown(before)) else {
                log.error("change failed: keyboard didn't confirm")
                return
            }
            await self.save()
            log.notice("saved \(LightingEffect.name(lighting.effect), privacy: .public)")
            if let applied = self.applied {
                await self.write(self.overlay(applied, on: lighting), over: lighting)
            }
        }
    }

    /// Puts the saved lighting back before the app quits, without waiting for replies.
    func restoreBeforeQuit() {
        guard let applied, let saved else { return }
        commands(for: saved, over: overlay(applied, on: saved)).forEach(monitor.sendNow)
    }

    // MARK: - Per-layer lighting

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        enqueue {
            self.syncQueued = false
            await self.sync()
        }
    }

    private func sync() async {
        guard monitor.isConnected, let layer = monitor.layer else { return }
        let lightsOff = displaysAsleep && settings.lightsOffWhileDisplaysSleep
        let target = lightsOff ? lightsOffLighting : settings.layerLightingEnabled ? settings.lighting(for: layer) : nil
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
            guard await write(overlay(target, on: saved), over: shown(saved)) else { return }
            applied = target
            lightsOffShown = lightsOff
            log.notice("layer \(layer) lighting: \(lightsOff ? "off while displays sleep" : LightingEffect.name(target.effect), privacy: .public)")
        } else {
            await restoreSaved()
            log.notice("layer \(layer) lighting: saved")
        }
    }

    /// Off, in the colour the keyboard shows, so only the effect changes.
    private var lightsOffLighting: LayerLighting {
        let color = applied.map { ($0.hue, $0.saturation) } ?? saved.map { ($0.hue, $0.saturation) } ?? (0, 255)
        return LayerLighting(effect: 0, hue: color.0, saturation: color.1)
    }

    private func restoreSaved() async {
        guard let applied, let before = saved else {
            self.applied = nil
            lightsOffShown = false
            return
        }
        var lighting = before
        var current = overlay(applied, on: lighting)
        // Light keys pressed while the layer's lighting was on (Fn + light keys) changed the
        // keyboard; keep those changes and save them instead of undoing them.
        if let now = await read() {
            log.notice("keyboard shows \(now.summary, privacy: .public)")
            if abs(Int(now.brightness) - Int(lighting.brightness)) > 2 {
                lighting.brightness = now.brightness
            }
            if now.speed != lighting.speed {
                lighting.speed = now.speed
            }
            if now.effect != applied.effect {
                lighting.effect = now.effect
            }
            if (now.hue, now.saturation) != (applied.hue, applied.saturation) {
                lighting.hue = now.hue
                lighting.saturation = now.saturation
            }
            current = Lighting(effect: now.effect, brightness: lighting.brightness, speed: lighting.speed,
                               hue: now.hue, saturation: now.saturation)
        }
        guard await write(lighting, over: current) else { return }
        // A keyboard that restarted shows the saved lighting again: nothing new to save.
        if lighting != before { await save() }
        saved = lighting
        self.applied = nil
        lightsOffShown = false
    }

    /// What the keyboard shows: the saved lighting, or a layer's lighting on top of it.
    private func shown(_ saved: Lighting) -> Lighting {
        applied.map { overlay($0, on: saved) } ?? saved
    }

    private func overlay(_ layer: LayerLighting, on saved: Lighting) -> Lighting {
        Lighting(effect: layer.effect, brightness: saved.brightness, speed: saved.speed,
                 hue: layer.hue, saturation: layer.saturation)
    }

    // MARK: - Protocol

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
        guard let effect = await get(LightingCommand.effect),
              let brightness = await get(LightingCommand.brightness),
              let speed = await get(LightingCommand.speed),
              let color = await get(LightingCommand.color)
        else { return nil }
        return Lighting(effect: effect[0], brightness: brightness[0], speed: speed[0],
                        hue: color[0], saturation: color[1])
    }

    /// Sends the values of `target` that differ from `current`, stopping at the first
    /// one the keyboard doesn't answer.
    @discardableResult
    private func write(_ target: Lighting, over current: Lighting) async -> Bool {
        let commands = commands(for: target, over: current)
        // "0217 0415ff": value id and data of each set command, in order.
        let sent = commands.map { $0.dropFirst(2).map { String(format: "%02x", $0) }.joined() }
        log.notice("write \(target.summary, privacy: .public) over \(current.summary, privacy: .public): \(sent.joined(separator: " "), privacy: .public)")
        for command in commands {
            guard await monitor.request(command) != nil else { return false }
        }
        return true
    }

    /// The set commands that take the keyboard from `current` to `target`. The effect goes
    /// last so the new effect starts in the new colour, except when the lights are off.
    private func commands(for target: Lighting, over current: Lighting) -> [[UInt8]] {
        var commands: [[UInt8]] = []
        var effect = current.effect
        if effect == 0, target.effect != 0 {
            // Colour and brightness sent while off are ignored.
            commands.append(Self.setCommand(LightingCommand.effect, [target.effect]))
            effect = target.effect
        } else if target.effect == 0, effect != 0, let keptEffect, keptEffect != effect {
            // Otherwise the light key would turn back on with the layer's effect.
            commands.append(Self.setCommand(LightingCommand.effect, [keptEffect]))
            effect = keptEffect
        }
        if (target.hue, target.saturation) != (current.hue, current.saturation) {
            commands.append(Self.setCommand(LightingCommand.color, [target.hue, target.saturation]))
        }
        if target.brightness != current.brightness {
            commands.append(Self.setCommand(LightingCommand.brightness, [target.brightness]))
        }
        if target.speed != current.speed {
            commands.append(Self.setCommand(LightingCommand.speed, [target.speed]))
        }
        if target.effect != effect {
            commands.append(Self.setCommand(LightingCommand.effect, [target.effect]))
        }
        return commands
    }

    private func get(_ value: UInt8) async -> [UInt8]? {
        let request = [LightingCommand.getValue, LightingCommand.rgbMatrixChannel, value]
        guard let reply = await monitor.request(request), reply.count >= 5 else { return nil }
        return Array(reply[3...])
    }

    private func save() async {
        _ = await monitor.request([LightingCommand.save, LightingCommand.rgbMatrixChannel], headerLength: 2)
    }

    private static func setCommand(_ value: UInt8, _ data: [UInt8]) -> [UInt8] {
        [LightingCommand.setValue, LightingCommand.rgbMatrixChannel, value] + data
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
