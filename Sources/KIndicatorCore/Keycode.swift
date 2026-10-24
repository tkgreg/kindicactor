import Foundation

/// Short labels for keycodes in QMK's numbering since 0.19, which keyboards speaking VIA
/// protocol 12 use. Labels fit a key 1 unit wide: modifiers are ⌃⌥⇧⌘, as on a Mac.
package enum Keycode {
    package static let none: UInt16 = 0x0000
    package static let transparent: UInt16 = 0x0001

    /// The label for `keycode`; `customNames` are the keyboard's own keycodes from 0x7E00.
    package static func label(_ keycode: UInt16, customNames: [String] = []) -> String {
        switch keycode {
        case none: return ""
        case transparent: return "▽"
        case 0x0002...0x00FF: return basic[UInt8(keycode)] ?? hex(keycode)
        case 0x0100...0x1FFF:
            // Modifiers held with a key, e.g. ⌃⌥⌘E.
            return modifiers(UInt8(keycode >> 8 & 0x1F)) + label(keycode & 0xFF, customNames: customNames)
        case 0x2000...0x3FFF:
            // Mod-tap: the key when tapped, modifiers when held.
            return label(keycode & 0xFF, customNames: customNames)
        case 0x4000...0x4FFF:
            // Layer-tap: the key when tapped, a layer when held.
            return label(keycode & 0xFF, customNames: customNames)
        case 0x5000...0x51FF: return "LM\(keycode >> 5 & 0xF)"
        case 0x5200...0x521F: return "TO\(keycode & 0x1F)"
        case 0x5220...0x523F: return "MO\(keycode & 0x1F)"
        case 0x5240...0x525F: return "DF\(keycode & 0x1F)"
        case 0x5260...0x527F: return "TG\(keycode & 0x1F)"
        case 0x5280...0x529F: return "OSL\(keycode & 0x1F)"
        case 0x52A0...0x52BF: return "OSM"
        case 0x52C0...0x52DF: return "TT\(keycode & 0x1F)"
        case 0x5700...0x57FF: return "TD\(keycode & 0xFF)"
        case 0x7700...0x777F: return "M\(keycode & 0x7F)"
        case 0x7800...0x78FF: return lighting[keycode] ?? "Light"
        case 0x7C00: return "Boot"
        case 0x7E00...0x7E3F:
            let index = Int(keycode - 0x7E00)
            return index < customNames.count ? custom(customNames[index]) : "KB\(index)"
        default: return hex(keycode)
        }
    }

    /// ⌃⌥⇧⌘ for QMK's 5-bit modifier set; bit 4 means right-hand, which looks the same.
    package static func modifiers(_ bits: UInt8) -> String {
        (bits & 0x01 != 0 ? "⌃" : "") + (bits & 0x04 != 0 ? "⌥" : "") + (bits & 0x02 != 0 ? "⇧" : "")
            + (bits & 0x08 != 0 ? "⌘" : "")
    }

    /// Keychron's short names, with Mac modifier names as symbols and the "-m"/"-w"
    /// (Mac/Windows) suffixes dropped.
    private static func custom(_ name: String) -> String {
        switch name {
        case "Opt": "⌥"
        case "Cmd": "⌘"
        default: name.hasSuffix("-m") || name.hasSuffix("-w") ? String(name.dropLast(2)) : name
        }
    }

    private static func hex(_ keycode: UInt16) -> String {
        String(format: "%04X", keycode)
    }

    private static let basic: [UInt8: String] = {
        var labels: [UInt8: String] = [:]
        for (offset, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            labels[0x04 + UInt8(offset)] = String(letter)
        }
        for (offset, digit) in "1234567890".enumerated() {
            labels[0x1E + UInt8(offset)] = String(digit)
        }
        for number in 1...12 { labels[0x39 + UInt8(number)] = "F\(number)" }
        for number in 13...24 { labels[0x5B + UInt8(number)] = "F\(number)" }
        for (offset, digit) in "1234567890".enumerated() {
            labels[0x59 + UInt8(offset)] = String(digit)
        }
        let named: [UInt8: String] = [
            0x28: "↩", 0x29: "Esc", 0x2A: "⌫", 0x2B: "⇥", 0x2C: "Space", 0x2D: "-", 0x2E: "=",
            0x2F: "[", 0x30: "]", 0x31: "\\", 0x32: "#", 0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",",
            0x37: ".", 0x38: "/", 0x39: "⇪",
            0x46: "PrtSc", 0x47: "ScrLk", 0x48: "Pause", 0x49: "Ins", 0x4A: "Home", 0x4B: "PgUp",
            0x4C: "⌦", 0x4D: "End", 0x4E: "PgDn", 0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑",
            0x53: "Num", 0x54: "/", 0x55: "*", 0x56: "-", 0x57: "+", 0x58: "↩", 0x63: ".",
            0x64: "\\", 0x65: "Menu", 0x66: "Power", 0x67: "=",
            0x85: ",", 0x87: "ろ", 0x88: "かな", 0x89: "¥", 0x8A: "変換", 0x8B: "無変換",
            0x90: "かな", 0x91: "英数",
            0xA5: "Power", 0xA6: "Sleep", 0xA7: "Wake", 0xA8: "Mute", 0xA9: "Vol+", 0xAA: "Vol−",
            0xAB: "Next", 0xAC: "Prev", 0xAD: "Stop", 0xAE: "Play", 0xAF: "Media", 0xB0: "Eject",
            0xB1: "Mail", 0xB2: "Calc", 0xB3: "Files", 0xB4: "Search", 0xB5: "Home", 0xB6: "Back",
            0xB7: "Fwd", 0xB8: "Stop", 0xB9: "Reload", 0xBA: "Fav", 0xBB: "FFwd", 0xBC: "Rew",
            0xBD: "Bri+", 0xBE: "Bri−", 0xBF: "Ctrl Pnl", 0xC0: "Siri", 0xC1: "MCtl", 0xC2: "LPad",
            0xE0: "⌃", 0xE1: "⇧", 0xE2: "⌥", 0xE3: "⌘", 0xE4: "⌃", 0xE5: "⇧", 0xE6: "⌥", 0xE7: "⌘",
        ]
        labels.merge(named) { _, new in new }
        for code in UInt8(0xCD)...UInt8(0xDF) where labels[code] == nil { labels[code] = "Mouse" }
        return labels
    }()

    /// QMK's backlight and RGB keys; "Lit" is the keyboard's brightness, "Bri" the screen's.
    private static let lighting: [UInt16: String] = [
        0x7800: "BL", 0x7820: "Light", 0x7821: "Mode+", 0x7822: "Mode−", 0x7823: "Hue+", 0x7824: "Hue−",
        0x7825: "Sat+", 0x7826: "Sat−", 0x7827: "Lit+", 0x7828: "Lit−", 0x7829: "Spd+", 0x782A: "Spd−",
    ]
}
