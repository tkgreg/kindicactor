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

enum LightingEffect {
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
