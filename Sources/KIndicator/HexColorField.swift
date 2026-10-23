import AppKit
import SwiftUI

/// "#RRGGBB" for a lighting colour. The keyboard keeps only hue and saturation (its
/// brightness setting supplies the rest), so a typed colour shows at full brightness.
struct HexColorField: View {
    let hue: UInt8
    let saturation: UInt8
    let onCommit: (_ hue: UInt8, _ saturation: UInt8) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Hex", text: $text, prompt: Text("#RRGGBB"))
            .font(.body.monospaced())
            .frame(width: 86)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onAppear(perform: showCurrent)
            .onChange(of: hue) { showCurrent() }
            .onChange(of: saturation) { showCurrent() }
            .help("Hex colour, e.g. #FF8000. Brightness comes from the keyboard's brightness setting.")
    }

    private func commit() {
        guard let (hue, saturation) = Self.parse(text) else { return showCurrent() }
        onCommit(hue, saturation)
        showCurrent()
    }

    private func showCurrent() {
        text = Self.hex(hue: hue, saturation: saturation)
    }

    static func hex(hue: UInt8, saturation: UInt8) -> String {
        let color = NSColor(colorSpace: .sRGB, hue: CGFloat(hue) / 255, saturation: CGFloat(saturation) / 255,
                            brightness: 1, alpha: 1)
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }

    /// Accepts "RGB" or "RRGGBB", with or without "#".
    static func parse(_ text: String) -> (hue: UInt8, saturation: UInt8)? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        let color = NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        // Hue is a circle: 1.0 (255) is red again, which the keyboard calls 0.
        return (UInt8(Int((color.hueComponent * 255).rounded()) % 255), UInt8((color.saturationComponent * 255).rounded()))
    }
}
