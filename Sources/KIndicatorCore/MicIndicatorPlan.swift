import Foundation

/// The key showing the mic indicator: its LED, its own colour and the colour it shows.
package struct ShownIndicator: Equatable, Sendable {
    package var led: UInt8
    package var own: KeyColor
    package var shown: KeyColor

    package init(led: UInt8, own: KeyColor, shown: KeyColor) {
        self.led = led
        self.own = own
        self.shown = shown
    }
}

/// The key that should show the indicator, and in which colour.
package struct WantedIndicator: Equatable, Sendable {
    package var led: UInt8
    package var hue: UInt8
    package var saturation: UInt8

    package init(led: UInt8, hue: UInt8, saturation: UInt8) {
        self.led = led
        self.hue = hue
        self.saturation = saturation
    }
}

/// The next thing to do to the keyboard for the mic indicator.
package enum IndicatorStep: Equatable, Sendable {
    case nothing
    /// Give the key its own colour back.
    case restore(ShownIndicator)
    /// Read the key's own colour, then show `MicIndicatorPlan.color(for:own:)`.
    case light(WantedIndicator)
    /// Show `KeyColor` on the key that's already lit.
    case recolor(ShownIndicator, KeyColor)
}

/// Decisions about the mic indicator, as pure functions. The app repeats `step` and carries
/// out each step until it says `.nothing`.
package enum MicIndicatorPlan {
    /// The indicator shows while it's on, an app records and the keyboard shows Per-key RGB,
    /// the one effect with a colour for each key; and once the key's LED is known.
    package static func wanted(_ indicator: MicIndicator, micInUse: Bool, shownEffect: UInt8?,
                               ledMap: LEDMap?) -> WantedIndicator? {
        guard indicator.enabled, micInUse, shownEffect == LightingEffect.perKeyRGB,
              let led = ledMap?.led(at: indicator.key) else { return nil }
        return WantedIndicator(led: led, hue: indicator.hue, saturation: indicator.saturation)
    }

    /// `stale`: the keyboard may have lost the colour (it reconnected, or another app had it
    /// open), so it's sent again.
    package static func step(shown: ShownIndicator?, wanted: WantedIndicator?, stale: Bool) -> IndicatorStep {
        if let shown, wanted?.led != shown.led {
            return .restore(shown)
        }
        guard let wanted else { return .nothing }
        guard let shown else { return .light(wanted) }
        let color = KeyColor(hue: wanted.hue, saturation: wanted.saturation, value: shown.shown.value)
        return color != shown.shown || stale ? .recolor(shown, color) : .nothing
    }

    /// The indicator's colour at the key's own brightness, or full for a key that's dark.
    package static func color(for wanted: WantedIndicator, own: KeyColor) -> KeyColor {
        KeyColor(hue: wanted.hue, saturation: wanted.saturation, value: own.value == 0 ? 255 : own.value)
    }
}
