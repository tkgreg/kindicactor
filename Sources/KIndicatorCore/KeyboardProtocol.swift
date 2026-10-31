import Foundation

/// A request on the raw HID channel Keychron Launcher uses (usage page 0xFF60, usage 0x61,
/// 32-byte reports). The reply starts with `replyHeader`, an echo of the request's start.
///
/// The VIA commands (0x01-0x15) and Keychron's own (0xA1-0xB2) come from Keychron's ZMK;
/// 0x07-0x09 on channel 3 are VIA's RGB matrix values; 0xA8 is Keychron's per-key RGB group,
/// sent the way Keychron Launcher sends it. Save for the per-key colours (0xA8 0x02) is
/// deliberately missing: KIndicator's key colours stay in the keyboard's memory. Keymap
/// changes (0x05, 0x15) are saved by the keyboard itself.
package enum KeyboardRequest: Equatable, Sendable {
    case viaProtocolVersion
    case layerCount
    /// What a key sends on a layer.
    case getKeycode(layer: Int, KeyPosition)
    case setKeycode(layer: Int, KeyPosition, UInt16)
    /// What turning a knob sends on a layer; clockwise is to the right.
    case getEncoder(layer: Int, encoder: UInt8, clockwise: Bool)
    case setEncoder(layer: Int, encoder: UInt8, clockwise: Bool, UInt16)
    /// Up to 28 bytes of the keymap: big-endian keycodes, layer by layer, row by row.
    case keymapBuffer(offset: Int, size: Int)
    case firmwareVersion
    /// The highest active layer, so momentary layers count too.
    case activeLayer
    /// Answered by the 2.4 GHz dongle: up to 3 paired devices.
    case receiverState

    case getLighting(LightingValue)
    case setEffect(UInt8)
    case setBrightness(UInt8)
    case setSpeed(UInt8)
    case setColor(hue: UInt8, saturation: UInt8)
    /// Stores the RGB matrix values on the keyboard.
    case saveLighting

    /// The LED of each column of a matrix row.
    case ledNumbers(row: Int)
    /// Up to 9 LEDs from `first`.
    case getKeyColors(first: UInt8, count: Int)
    /// Up to 9 LEDs from `first`.
    case setKeyColors(first: UInt8, [KeyColor])

    package enum LightingValue: UInt8, Sendable {
        case brightness = 1, effect = 2, speed = 3, color = 4
    }

    private static let rgbMatrixChannel: UInt8 = 0x03
    private static let perKeyRGB: UInt8 = 0xA8
    /// Bytes of a 32-byte report after a keymap request's 4-byte header.
    package static let maxKeymapChunk = 28
    package static let maxKeyColors = 9

    package var bytes: [UInt8] {
        switch self {
        case .viaProtocolVersion: [0x01]
        case .layerCount: [0x11]
        case .getKeycode(let layer, let key): [0x04, UInt8(layer), UInt8(key.row), UInt8(key.col)]
        case .setKeycode(let layer, let key, let keycode):
            [0x05, UInt8(layer), UInt8(key.row), UInt8(key.col)] + Self.bigEndian(keycode)
        case .getEncoder(let layer, let encoder, let clockwise): [0x14, UInt8(layer), encoder, clockwise ? 1 : 0]
        case .setEncoder(let layer, let encoder, let clockwise, let keycode):
            [0x15, UInt8(layer), encoder, clockwise ? 1 : 0] + Self.bigEndian(keycode)
        case .keymapBuffer(let offset, let size): [0x12, UInt8(offset >> 8), UInt8(offset & 0xFF), UInt8(size)]
        case .firmwareVersion: [0xA1]
        case .activeLayer: [0xA3]
        case .receiverState: [0xB2]
        case .getLighting(let value): [0x08, Self.rgbMatrixChannel, value.rawValue]
        case .setEffect(let effect): Self.set(.effect, [effect])
        case .setBrightness(let brightness): Self.set(.brightness, [brightness])
        case .setSpeed(let speed): Self.set(.speed, [speed])
        case .setColor(let hue, let saturation): Self.set(.color, [hue, saturation])
        case .saveLighting: [0x09, Self.rgbMatrixChannel]
        case .ledNumbers(let row): [Self.perKeyRGB, 0x06, UInt8(row), 0xFF, 0xFF, 0xFF]
        case .getKeyColors(let first, let count): [Self.perKeyRGB, 0x09, first, UInt8(count)]
        case .setKeyColors(let first, let colors):
            [Self.perKeyRGB, 0x0A, first, UInt8(colors.count)] + colors.flatMap { [$0.hue, $0.saturation, $0.value] }
        }
    }

    /// How a reply to this request starts.
    package var replyHeader: [UInt8] {
        switch self {
        case .viaProtocolVersion, .layerCount, .firmwareVersion, .activeLayer, .receiverState: Array(bytes.prefix(1))
        case .getKeycode, .setKeycode, .getEncoder, .setEncoder: Array(bytes.prefix(4))
        case .keymapBuffer, .getLighting, .setEffect, .setBrightness, .setSpeed, .setColor: Array(bytes.prefix(3))
        case .saveLighting, .ledNumbers, .getKeyColors, .setKeyColors: Array(bytes.prefix(2))
        }
    }

    private static func set(_ value: LightingValue, _ data: [UInt8]) -> [UInt8] {
        [0x07, rgbMatrixChannel, value.rawValue] + data
    }

    private static func bigEndian(_ keycode: UInt16) -> [UInt8] {
        [UInt8(keycode >> 8), UInt8(keycode & 0xFF)]
    }
}

/// Reads the data out of replies. Each returns nil for a reply that doesn't fit.
package enum KeyboardReply {
    package static func viaProtocolVersion(_ reply: [UInt8]) -> Int? {
        guard reply.count >= 3, reply[0] == 0x01 else { return nil }
        return Int(reply[1]) << 8 | Int(reply[2])
    }

    package static func layerCount(_ reply: [UInt8]) -> Int? {
        guard reply.count >= 2, reply[0] == 0x11, (1...32).contains(reply[1]) else { return nil }
        return Int(reply[1])
    }

    package static func activeLayer(_ reply: [UInt8]) -> Int? {
        guard reply.count >= 2, reply[0] == 0xA3, reply[1] < 32 else { return nil }
        return Int(reply[1])
    }

    /// "1.0.2": the text up to the first zero byte.
    package static func firmwareVersion(_ reply: [UInt8]) -> String? {
        guard reply.first == 0xA1 else { return nil }
        return String(decoding: reply.dropFirst().prefix { $0 != 0 }, as: UTF8.self)
    }

    /// The paired devices marked active: three slots of 5 bytes from offset 2, holding the
    /// vendor ID and product ID (little-endian) and an active flag.
    package static func pairedDevices(_ reply: [UInt8]) -> [(vendorID: Int, productID: Int)] {
        guard reply.first == 0xB2, reply.count >= 17 else { return [] }
        return stride(from: 2, to: 17, by: 5).compactMap { offset in
            guard reply[offset + 4] != 0 else { return nil }
            return (Int(reply[offset]) | Int(reply[offset + 1]) << 8, Int(reply[offset + 2]) | Int(reply[offset + 3]) << 8)
        }
    }

    /// The bytes of a lighting value: one for effect, brightness and speed; hue and
    /// saturation for colour.
    package static func lightingValue(_ reply: [UInt8]) -> [UInt8]? {
        guard reply.count >= 5, reply[0] == 0x08 else { return nil }
        return Array(reply[3...])
    }

    /// The keycode in a reply to `getKeycode` or `getEncoder`, after the 4-byte echo.
    package static func keycode(_ reply: [UInt8]) -> UInt16? {
        guard reply.count >= 6, reply[0] == 0x04 || reply[0] == 0x14 else { return nil }
        return UInt16(reply[4]) << 8 | UInt16(reply[5])
    }

    package static func keymapChunk(_ reply: [UInt8], size: Int) -> [UInt8]? {
        guard reply.first == 0x12, reply.count >= 4 + size else { return nil }
        return Array(reply[4..<4 + size])
    }

    /// The LED of each of the first `cols` columns; nil where there's none (255).
    package static func ledNumbers(_ reply: [UInt8], cols: Int) -> [UInt8?]? {
        guard reply.count >= 3 + cols, reply[0] == 0xA8, reply[1] == 0x06 else { return nil }
        return reply[3..<3 + cols].map { $0 == 0xFF ? nil : $0 }
    }

    package static func keyColors(_ reply: [UInt8], count: Int) -> [KeyColor]? {
        guard reply.count >= 3 + 3 * count, reply[0] == 0xA8, reply[1] == 0x09 else { return nil }
        return (0..<count).map { i in
            KeyColor(hue: reply[3 + 3 * i], saturation: reply[4 + 3 * i], value: reply[5 + 3 * i])
        }
    }
}
