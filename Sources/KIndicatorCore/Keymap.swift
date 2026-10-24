import Foundation

/// The keycode of every key on every layer, as the keyboard reports it (VIA's keymap buffer).
package struct Keymap: Equatable, Sendable {
    package var rows: Int
    package var cols: Int
    /// `layers[layer][row * cols + col]`.
    package var layers: [[UInt16]]

    package init(rows: Int, cols: Int, layers: [[UInt16]]) {
        self.rows = rows
        self.cols = cols
        self.layers = layers
    }

    /// The buffer holds big-endian keycodes, layer after layer, row by row.
    package init(buffer: [UInt8], layerCount: Int, rows: Int, cols: Int) {
        let perLayer = rows * cols
        let codes = stride(from: 0, to: buffer.count - 1, by: 2).map { UInt16(buffer[$0]) << 8 | UInt16(buffer[$0 + 1]) }
        self.init(rows: rows, cols: cols, layers: (0..<layerCount).map { layer in
            Array(codes.dropFirst(layer * perLayer).prefix(perLayer))
        })
    }

    package func keycode(layer: Int, at position: KeyPosition) -> UInt16? {
        let index = position.row * cols + position.col
        guard layers.indices.contains(layer), (0..<cols).contains(position.col),
              layers[layer].indices.contains(index) else { return nil }
        return layers[layer][index]
    }

    /// What a key does on `layer`: a transparent key falls through to the layers below,
    /// so its keycode comes from the first lower layer that sets one.
    package func resolved(layer: Int, at position: KeyPosition) -> (keycode: UInt16, layer: Int)? {
        for candidate in stride(from: min(layer, layers.count - 1), through: 0, by: -1) {
            guard let keycode = keycode(layer: candidate, at: position) else { return nil }
            if keycode != Keycode.transparent { return (keycode, candidate) }
        }
        return nil
    }

    /// The requests that read the whole keymap, 28 bytes each.
    package static func requests(layerCount: Int, rows: Int, cols: Int) -> [KeyboardRequest] {
        let size = layerCount * rows * cols * 2
        return stride(from: 0, to: size, by: KeyboardRequest.maxKeymapChunk).map { offset in
            .keymapBuffer(offset: offset, size: min(KeyboardRequest.maxKeymapChunk, size - offset))
        }
    }
}
