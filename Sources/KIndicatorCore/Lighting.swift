import Foundation

/// The keyboard's RGB matrix state, in the units of the Launcher protocol (0...255).
package struct Lighting: Equatable, Sendable {
    package var effect: UInt8
    package var brightness: UInt8
    package var speed: UInt8
    package var hue: UInt8
    package var saturation: UInt8

    package init(effect: UInt8, brightness: UInt8, speed: UInt8, hue: UInt8, saturation: UInt8) {
        self.effect = effect
        self.brightness = brightness
        self.speed = speed
        self.hue = hue
        self.saturation = saturation
    }

    package var summary: String {
        "\(LightingEffect.name(effect)) brightness \(brightness) speed \(speed) hue \(hue)/\(saturation)"
    }
}

/// Lighting a layer switches to while it's active. Brightness and speed stay as saved.
package struct LayerLighting: Codable, Equatable, Sendable {
    package var effect: UInt8
    package var hue: UInt8
    package var saturation: UInt8

    package init(effect: UInt8, hue: UInt8, saturation: UInt8) {
        self.effect = effect
        self.hue = hue
        self.saturation = saturation
    }
}

/// One key's colour in Per-key RGB mode. Unlike the effect's colour it has its own value
/// (brightness), which the keyboard's brightness setting then scales.
package struct KeyColor: Equatable, Sendable {
    package var hue: UInt8
    package var saturation: UInt8
    package var value: UInt8

    package init(hue: UInt8, saturation: UInt8, value: UInt8) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
    }
}

/// A key that lights up while an app records from a microphone. It shows only while the
/// effect is Per-key RGB, the one mode with a colour for each key.
package struct MicIndicator: Codable, Equatable, Sendable {
    package var enabled = false
    package var key = KeyPosition(row: 0, col: 0)
    package var hue: UInt8 = 0
    package var saturation: UInt8 = 255

    package init(enabled: Bool = false, key: KeyPosition = KeyPosition(row: 0, col: 0),
                 hue: UInt8 = 0, saturation: UInt8 = 255) {
        self.enabled = enabled
        self.key = key
        self.hue = hue
        self.saturation = saturation
    }

    /// For keyboards without a known layout: Esc and F1...F12, the start of the top row
    /// on Keychron boards.
    package static let fallbackKeys: [(key: KeyPosition, name: String)] =
        [(KeyPosition(row: 0, col: 0), "Esc")] + (1...12).map { (KeyPosition(row: 0, col: $0), "F\($0)") }

    private enum CodingKeys: String, CodingKey {
        case enabled, key, hue, saturation
        /// The first version stored an LED number; 0...12 were Esc and F1...F12.
        case led
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        hue = try container.decodeIfPresent(UInt8.self, forKey: .hue) ?? 0
        saturation = try container.decodeIfPresent(UInt8.self, forKey: .saturation) ?? 255
        if let key = try container.decodeIfPresent(KeyPosition.self, forKey: .key) {
            self.key = key
        } else if let led = try container.decodeIfPresent(Int.self, forKey: .led) {
            key = KeyPosition(row: 0, col: led)
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(key, forKey: .key)
        try container.encode(hue, forKey: .hue)
        try container.encode(saturation, forKey: .saturation)
    }
}

package enum LightingEffect {
    package static let off: UInt8 = 0
    package static let perKeyRGB: UInt8 = 23

    /// Effect IDs of the V6 Ultra 8K firmware (`enum rgb_effects` in Keychron's ZMK);
    /// 0 turns the lights off.
    package static let names = [
        "Off", "Solid Color", "Breathing", "Band Spiral Val", "Cycle All", "Cycle Left Right",
        "Cycle Up Down", "Rainbow Moving Chevron", "Cycle Out In", "Cycle Out In Dual",
        "Cycle Pinwheel", "Cycle Spiral", "Dual Beacon", "Rainbow Beacon", "Jellybean Raindrops",
        "Pixel Rain", "Typing Heatmap", "Digital Rain", "Reactive Simple", "Reactive Multiwide",
        "Reactive Multinexus", "Splash", "Solid Splash", "Per-key RGB", "Mixed RGB",
    ]

    package static var ids: Range<UInt8> { 0..<UInt8(names.count) }

    package static func name(_ id: UInt8) -> String {
        Int(id) < names.count ? names[Int(id)] : "Effect \(id)"
    }
}
