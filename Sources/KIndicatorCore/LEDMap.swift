import Foundation

/// Which LED lights each matrix position, as the keyboard reports it (`0xA8 0x06`).
package struct LEDMap: Equatable, Sendable {
    package var leds: [KeyPosition: UInt8]

    package init(leds: [KeyPosition: UInt8]) {
        self.leds = leds
    }

    /// `rows[row][col]`: one reply's LED numbers per matrix row.
    package init(rows: [[UInt8?]]) {
        var leds: [KeyPosition: UInt8] = [:]
        for (row, columns) in rows.enumerated() {
            for (col, led) in columns.enumerated() {
                if let led { leds[KeyPosition(row: row, col: col)] = led }
            }
        }
        self.leds = leds
    }

    package func led(at position: KeyPosition) -> UInt8? {
        leds[position]
    }

    /// LEDs are numbered from 0, so one more than the highest.
    package var ledCount: Int {
        leds.values.max().map { Int($0) + 1 } ?? 0
    }

    package static func requests(rows: Int) -> [KeyboardRequest] {
        (0..<rows).map { KeyboardRequest.ledNumbers(row: $0) }
    }
}
