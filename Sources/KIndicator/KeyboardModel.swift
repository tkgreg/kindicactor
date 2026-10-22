import Foundation

/// Names keyboards by USB product ID. Through the dongle only the paired keyboard's IDs
/// are known, so names seen over the cable or Bluetooth are remembered for 2.4 GHz.
enum KeyboardModel {
    /// Layout variants of the V6 Ultra 8K (`CONFIG_USB_DEVICE_PID` in Keychron's ZMK shields).
    private static let known: [Int: String] = [
        0x0C60: "Keychron V6 Ultra 8K ANSI",
        0x0C61: "Keychron V6 Ultra 8K ISO",
        0x0C62: "Keychron V6 Ultra 8K JIS",
    ]

    private static let learnedKey = "learnedKeyboardNames"

    static func name(productID: Int, productName: String? = nil) -> String {
        known[productID]
            ?? productName
            ?? learnedNames[String(productID)]
            ?? String(format: "Keychron keyboard (PID %04X)", productID)
    }

    /// Remembers the name a keyboard reports over the cable or Bluetooth.
    static func learn(_ productName: String, productID: Int) {
        var names = learnedNames
        guard names[String(productID)] != productName else { return }
        names[String(productID)] = productName
        UserDefaults.standard.set(names, forKey: learnedKey)
    }

    private static var learnedNames: [String: String] {
        UserDefaults.standard.dictionary(forKey: learnedKey) as? [String: String] ?? [:]
    }
}
