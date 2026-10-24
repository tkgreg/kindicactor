import Foundation

/// Per-key colours KIndicator shows over the keyboard's own, never saved: the mic
/// indicator's key, and, while it's on, a layer's Solid Color drawn key by key.
package struct KeyOverlay: Equatable, Sendable {
    /// Every key.
    package var fill: KeyColor?
    /// Single keys by LED, over the fill.
    package var keys: [UInt8: KeyColor]

    package init(fill: KeyColor? = nil, keys: [UInt8: KeyColor] = [:]) {
        self.fill = fill
        self.keys = keys
    }

    package func color(of led: UInt8, own: KeyColor) -> KeyColor {
        keys[led] ?? fill ?? own
    }
}

/// What KIndicator knows of the keyboard's per-key colours.
package struct KeyColors: Equatable, Sendable {
    /// The keyboard's own colours by LED, as far as they've been read.
    package var own: [UInt8: KeyColor]
    /// LEDs showing a colour other than their own, and that colour.
    package var shown: [UInt8: KeyColor]

    package init(own: [UInt8: KeyColor] = [:], shown: [UInt8: KeyColor] = [:]) {
        self.own = own
        self.shown = shown
    }
}

/// The next thing to do to the keyboard's per-key colours.
package enum KeyColorsStep: Equatable, Sendable {
    case nothing
    /// Read these keys' own colours first, to give them back later.
    case read([KeyboardRequest])
    /// Send these; then the keyboard shows the given colours.
    case write([KeyboardRequest], KeyColors)
}

/// Decisions about per-key colours, as pure functions. The app repeats `step` and carries
/// out each step until it says `.nothing`.
package enum KeyColorsPlan {
    /// One pulse, full colour to pale and back, in seconds.
    package static let pulsePeriod = 1.6
    /// The palest point of a pulse, as a share of the colour's saturation.
    package static let pulseLow = 0.15

    /// The overlay while `indicator` is on and an app records: its key, over `fill`. Per-key
    /// colours show only while the keyboard shows Per-key RGB, so otherwise there's none.
    package static func overlay(indicator: MicIndicator, micInUse: Bool, shownEffect: UInt8?, fill: KeyColor?,
                                ledMap: LEDMap?, elapsed: Double) -> KeyOverlay {
        guard indicator.enabled, micInUse, shownEffect == LightingEffect.perKeyRGB,
              let led = ledMap?.led(at: indicator.key) else { return KeyOverlay() }
        return KeyOverlay(fill: fill, keys: [led: indicatorColor(indicator, elapsed: elapsed)])
    }

    /// The indicator's colour `elapsed` seconds after it came on: steady, or pulsing from
    /// full colour to pale (`pulseLow`) and back. The keyboard shows every key at its own
    /// brightness setting, whatever value a key is given, so the pulse fades the saturation.
    package static func indicatorColor(_ indicator: MicIndicator, elapsed: Double) -> KeyColor {
        var color = KeyColor(hue: indicator.hue, saturation: indicator.saturation, value: 255)
        if indicator.style == .pulse {
            let wave = 0.5 + 0.5 * cos(2 * .pi * elapsed / pulsePeriod)
            color.saturation = UInt8((Double(indicator.saturation) * (pulseLow + (1 - pulseLow) * wave)).rounded())
        }
        return color
    }

    /// `stale`: the keyboard may have lost the colours shown (it reconnected, or another app
    /// had it open), so they're sent again. `ledCount` is how many keys a fill covers.
    package static func step(_ colors: KeyColors, overlay: KeyOverlay, ledCount: Int, stale: Bool) -> KeyColorsStep {
        let painted = overlay.fill == nil
            ? Set(overlay.keys.keys)
            : Set((0..<min(ledCount, 256)).map { UInt8($0) }).union(overlay.keys.keys)
        let unknown = painted.filter { colors.own[$0] == nil }
        if !unknown.isEmpty {
            return .read(runs(of: unknown.sorted()).map { .getKeyColors(first: $0.first, count: $0.leds.count) })
        }

        // Every key painted, or still showing a colour from before, gets its overlay colour
        // or its own back.
        var shown: [UInt8: KeyColor] = [:]
        var changes: [UInt8: KeyColor] = [:]
        for led in painted.union(colors.shown.keys) {
            guard let own = colors.own[led] else { continue }
            let target = painted.contains(led) ? overlay.color(of: led, own: own) : own
            if target != own { shown[led] = target }
            if target != colors.shown[led] ?? own || (stale && colors.shown[led] != nil) { changes[led] = target }
        }
        guard !changes.isEmpty else { return .nothing }
        // Once nothing is shown the own colours are forgotten: Keychron Launcher may change them.
        return .write(requests(setting: changes), KeyColors(own: shown.isEmpty ? [:] : colors.own, shown: shown))
    }

    /// Requests that set these colours, up to 9 neighbouring LEDs each.
    package static func requests(setting colors: [UInt8: KeyColor]) -> [KeyboardRequest] {
        runs(of: colors.keys.sorted()).map { run in .setKeyColors(first: run.first, run.leds.compactMap { colors[$0] }) }
    }

    /// Sorted LEDs grouped into runs of neighbours, at most 9 long (one request each).
    package static func runs(of leds: [UInt8]) -> [(first: UInt8, leds: [UInt8])] {
        var runs: [(first: UInt8, leds: [UInt8])] = []
        for led in leds {
            if let last = runs.last, last.leds.count < KeyboardRequest.maxKeyColors, led == last.leds.last! &+ 1 {
                runs[runs.count - 1].leds.append(led)
            } else {
                runs.append((led, [led]))
            }
        }
        return runs
    }
}
