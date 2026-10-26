import Foundation

/// The keyboard's brightness following the room's light, as the Mac's ambient light sensor
/// measures it: `dark` in a dark room, `bright` in a bright one. Shown without saving it on
/// the keyboard, like a layer's lighting.
package struct RoomBrightness: Codable, Equatable, Sendable {
    package var enabled = false
    /// Brightness (0...255) at `darkLux` and below.
    package var dark: UInt8 = 38
    /// Brightness at `brightLux` and above.
    package var bright: UInt8 = 255

    /// A dark room as a MacBook's sensor sees it: an evening lamp reads 2–6 lux.
    package static let darkLux = 5.0
    /// A bright room: an office, or daylight.
    package static let brightLux = 400.0

    package init(enabled: Bool = false, dark: UInt8 = 38, bright: UInt8 = 255) {
        self.enabled = enabled
        self.dark = dark
        self.bright = bright
    }

    /// The brightness at `lux`: between the two ends on a log scale, the way eyes see light.
    package func brightness(lux: Double) -> UInt8 {
        let lux = RoomLightPlan.clamped(lux)
        let share = log(lux / Self.darkLux) / log(Self.brightLux / Self.darkLux)
        return UInt8((Double(dark) + (Double(bright) - Double(dark)) * share).rounded())
    }
}

/// Decisions about following the room's light, as pure functions: which light the
/// brightness follows, and how it fades there.
package enum RoomLightPlan {
    /// Sensor readings (one a second) the light is judged by. Their median ignores a hand
    /// or a shadow passing by.
    package static let readings = 5
    /// The light has to change by this factor before the brightness follows, so the
    /// keyboard doesn't flicker as the light wobbles.
    package static let minChange = 1.5
    /// The most the brightness changes in one step of a fade.
    package static let fadeStep = 12

    /// Light below a dark room or above a bright one changes nothing.
    package static func clamped(_ lux: Double) -> Double {
        min(max(lux, RoomBrightness.darkLux), RoomBrightness.brightLux)
    }

    /// The room's light: the median of the latest readings.
    package static func median(_ readings: [Double]) -> Double? {
        guard !readings.isEmpty else { return nil }
        return readings.sorted()[readings.count / 2]
    }

    /// The light the brightness follows next: `lux`, unless it's within `minChange` of
    /// `current`. A dark or a bright room is always reached, though.
    package static func light(_ lux: Double, current: Double?) -> Double {
        let lux = clamped(lux)
        guard let current, lux != current else { return lux }
        let ends = [RoomBrightness.darkLux, RoomBrightness.brightLux]
        return ends.contains(lux) || max(lux, current) / min(lux, current) >= minChange ? lux : current
    }

    /// The next brightness of a fade from `shown` to `target`.
    package static func step(from shown: UInt8, to target: UInt8) -> UInt8 {
        UInt8(Int(shown) + max(-fadeStep, min(fadeStep, Int(target) - Int(shown))))
    }
}
