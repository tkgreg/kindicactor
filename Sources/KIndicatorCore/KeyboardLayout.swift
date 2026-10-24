import Foundation

/// A key's place in the keyboard's switch matrix: how the firmware names it.
package struct KeyPosition: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    package var row: Int
    package var col: Int

    package init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    package static func < (a: KeyPosition, b: KeyPosition) -> Bool {
        (a.row, a.col) < (b.row, b.col)
    }

    package var description: String { "r\(row)c\(col)" }
}

/// A rectangle in key units: 1 is the width of a letter key.
package struct KeyRect: Equatable, Sendable {
    package var x: Double
    package var y: Double
    package var width: Double
    package var height: Double

    package init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package var maxX: Double { x + width }
    package var maxY: Double { y + height }
}

/// One key of a layout, as drawn: where it is, how big, and which matrix position it reads.
package struct LayoutKey: Equatable, Sendable, Identifiable {
    /// Keycap colour class in Keychron's definitions.
    package enum Kind: Sendable {
        case alpha, modifier, accent
    }

    package var position: KeyPosition
    package var rect: KeyRect
    /// The second part of an L-shaped key (ISO Enter), in layout coordinates like `rect`.
    package var secondRect: KeyRect?
    package var kind: Kind
    /// The rotary knob: a matrix position with a press but no LED.
    package var isKnob: Bool

    package init(position: KeyPosition, rect: KeyRect, secondRect: KeyRect? = nil, kind: Kind, isKnob: Bool = false) {
        self.position = position
        self.rect = rect
        self.secondRect = secondRect
        self.kind = kind
        self.isKnob = isKnob
    }

    package var id: KeyPosition { position }

    /// The smallest rectangle around the whole key.
    package var bounds: KeyRect {
        guard let second = secondRect else { return rect }
        let x = min(rect.x, second.x)
        let y = min(rect.y, second.y)
        return KeyRect(x: x, y: y, width: max(rect.maxX, second.maxX) - x, height: max(rect.maxY, second.maxY) - y)
    }
}

/// A keyboard's physical layout: its keys, the size they cover, and its matrix.
package struct KeyboardLayout: Equatable, Sendable {
    package var name: String
    package var width: Double
    package var height: Double
    package var rows: Int
    package var cols: Int
    package var keys: [LayoutKey]
    /// Short names of the keyboard's own keycodes (Keychron's `QK_KB` range), in order.
    package var customKeycodeNames: [String]

    package init(name: String, width: Double, height: Double, rows: Int, cols: Int,
                 keys: [LayoutKey], customKeycodeNames: [String]) {
        self.name = name
        self.width = width
        self.height = height
        self.rows = rows
        self.cols = cols
        self.keys = keys
        self.customKeycodeNames = customKeycodeNames
    }

    package func key(at position: KeyPosition) -> LayoutKey? {
        keys.first { $0.position == position }
    }

    /// The bundled layout for a USB product ID, if there is one.
    package static func forProduct(_ productID: Int) -> KeyboardLayout? {
        bundled[productID]
    }
}
