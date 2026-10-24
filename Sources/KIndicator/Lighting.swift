import Foundation

/// The keyboard's RGB matrix state, in the units of the Launcher protocol (0...255).
struct Lighting: Equatable {
    var effect: UInt8
    var brightness: UInt8
    var speed: UInt8
    var hue: UInt8
    var saturation: UInt8

    var summary: String {
        "\(LightingEffect.name(effect)) brightness \(brightness) speed \(speed) hue \(hue)/\(saturation)"
    }
}

/// Lighting a layer switches to while it's active. Brightness and speed stay as saved.
struct LayerLighting: Codable, Equatable {
    var effect: UInt8
    var hue: UInt8
    var saturation: UInt8
}

/// A key that lights up while an app records from a microphone. It shows only while the
/// effect is Per-key RGB, the one mode with a colour for each key.
struct MicIndicator: Codable, Equatable {
    var enabled = false
    /// LED number: 0 is Esc and 1...12 are F1...F12 (on the V6 their LEDs come first).
    var led: UInt8 = 0
    var hue: UInt8 = 0
    var saturation: UInt8 = 255

    static let keys: [(led: UInt8, name: String)] = [(0, "Esc")] + (1...12).map { (UInt8($0), "F\($0)") }
}

/// One key's colour in Per-key RGB mode. Unlike the effect's colour it has its own value
/// (brightness), which the keyboard's brightness setting then scales.
struct KeyColor: Equatable {
    var hue: UInt8
    var saturation: UInt8
    var value: UInt8
}

enum LightingEffect {
    static let perKeyRGB: UInt8 = 23

    /// Effect IDs of the V6 Ultra 8K firmware (`enum rgb_effects` in Keychron's ZMK);
    /// 0 turns the lights off.
    static let names = [
        "Off", "Solid Color", "Breathing", "Band Spiral Val", "Cycle All", "Cycle Left Right",
        "Cycle Up Down", "Rainbow Moving Chevron", "Cycle Out In", "Cycle Out In Dual",
        "Cycle Pinwheel", "Cycle Spiral", "Dual Beacon", "Rainbow Beacon", "Jellybean Raindrops",
        "Pixel Rain", "Typing Heatmap", "Digital Rain", "Reactive Simple", "Reactive Multiwide",
        "Reactive Multinexus", "Splash", "Solid Splash", "Per-key RGB", "Mixed RGB",
    ]

    static var ids: Range<UInt8> { 0..<UInt8(names.count) }

    static func name(_ id: UInt8) -> String {
        Int(id) < names.count ? names[Int(id)] : "Effect \(id)"
    }
}

/// Launcher protocol for the RGB matrix: `[command, channel 3, value id, data...]`.
enum LightingCommand {
    static let setValue: UInt8 = 0x07
    static let getValue: UInt8 = 0x08
    static let save: UInt8 = 0x09
    static let rgbMatrixChannel: UInt8 = 0x03

    static let brightness: UInt8 = 1
    static let effect: UInt8 = 2
    static let speed: UInt8 = 3
    static let color: UInt8 = 4
}

/// Keychron's per-key RGB commands, as Keychron Launcher sends them: `[0xA8, command, data...]`.
/// Replies echo the first two bytes and carry data from byte 3. Launcher saves after each
/// change (`0xA8 0x02`); KIndicator never does, so its key colours stay in the keyboard's memory.
enum PerKeyCommand {
    static let group: UInt8 = 0xA8
    /// `[first LED, count]`, replied with count × (hue, saturation, value); up to 9 LEDs.
    static let getColors: UInt8 = 0x09
    /// `[first LED, count, hue, saturation, value, ...]`; up to 9 LEDs.
    static let setColors: UInt8 = 0x0A
}
