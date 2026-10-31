import Foundation

/// The keycodes the knob sends on one layer.
package struct KnobKeys: Codable, Equatable, Sendable {
    package var turnLeft: UInt16
    package var turnRight: UInt16
    package var press: UInt16

    package init(turnLeft: UInt16, turnRight: UInt16, press: UInt16) {
        self.turnLeft = turnLeft
        self.turnRight = turnRight
        self.press = press
    }

    package subscript(input: KnobInput) -> UInt16 {
        get {
            switch input {
            case .turnLeft: turnLeft
            case .turnRight: turnRight
            case .press: press
            }
        }
        set {
            switch input {
            case .turnLeft: turnLeft = newValue
            case .turnRight: turnRight = newValue
            case .press: press = newValue
            }
        }
    }
}

/// Where the knob is in the keymap: turning it is an encoder, pressing it a key of the matrix.
package struct KnobLocation: Equatable, Sendable {
    package var encoder: UInt8
    package var press: KeyPosition

    package init(encoder: UInt8 = 0, press: KeyPosition) {
        self.encoder = encoder
        self.press = press
    }

    /// The knob of a layout. Keychron's boards have one, encoder 0.
    package init?(layout: KeyboardLayout) {
        guard let knob = layout.keys.first(where: \.isKnob) else { return nil }
        self.init(press: knob.position)
    }

    /// The requests that read what the knob sends on `layer`: left, right, press.
    package func readRequests(layer: Int) -> [KeyboardRequest] {
        [.getEncoder(layer: layer, encoder: encoder, clockwise: false),
         .getEncoder(layer: layer, encoder: encoder, clockwise: true),
         .getKeycode(layer: layer, press)]
    }

    package func request(_ write: KnobWrite) -> KeyboardRequest {
        switch write.input {
        case .turnLeft: .setEncoder(layer: write.layer, encoder: encoder, clockwise: false, write.keycode)
        case .turnRight: .setEncoder(layer: write.layer, encoder: encoder, clockwise: true, write.keycode)
        case .press: .setKeycode(layer: write.layer, press, write.keycode)
        }
    }
}

/// One keycode to put on the knob; the keyboard saves it, as when set in Keychron Launcher.
package struct KnobWrite: Equatable, Sendable {
    package var layer: Int
    package var input: KnobInput
    package var keycode: UInt16

    package init(layer: Int, input: KnobInput, keycode: UInt16) {
        self.layer = layer
        self.input = input
        self.keycode = keycode
    }
}

package struct KnobTakeoverPlan: Equatable, Sendable {
    package var writes: [KnobWrite]
    /// The knob's own keys to remember before writing: every layer where it may send F18-F20.
    package var originals: [Int: KnobKeys]
    /// The ones to remember once every write went through.
    package var originalsAfterwards: [Int: KnobKeys]
}

/// Decisions about putting F18-F20 on the knob and giving it its own keys back, as pure
/// functions. The keys it had are remembered by layer, since the keyboard keeps only one set.
package enum KnobTakeover {
    /// The V6 Ultra 8K's own knob keys on the Mac layer (Volume −, Volume +, Mute): what a
    /// layer gets back when its own keys are unknown.
    package static let stockKeys = KnobKeys(turnLeft: 0x00AA, turnRight: 0x00A9, press: 0x00A8)

    /// Layers to read: the ones to take and the ones to give back.
    package static func layersToRead(_ control: KnobControl, originals: [Int: KnobKeys], layerCount: Int) -> [Int] {
        let wanted = control.enabled ? control.layers : []
        return wanted.union(originals.keys).filter { (0..<layerCount).contains($0) }.sorted()
    }

    /// What to write so the knob sends F18-F20 on `layers` and its own keys on the others, given
    /// what it sends `now` on each layer read. A key changed in Keychron Launcher meanwhile
    /// becomes the knob's own; one already F18-F20 keeps the own key remembered for it.
    package static func plan(now: [Int: KnobKeys], layers: Set<Int>, originals: [Int: KnobKeys]) -> KnobTakeoverPlan {
        let ours = KnobControl.keys
        var writes: [KnobWrite] = []
        var kept = originals
        var afterwards = originals
        for (layer, keys) in now.sorted(by: { $0.key < $1.key }) {
            if layers.contains(layer) {
                var own = originals[layer] ?? stockKeys
                for input in KnobInput.allCases where keys[input] != ours[input] {
                    own[input] = keys[input]
                    writes.append(KnobWrite(layer: layer, input: input, keycode: ours[input]))
                }
                kept[layer] = own
                afterwards[layer] = own
            } else if let own = originals[layer] {
                // Keys set to something else in Keychron Launcher meanwhile stay.
                for input in KnobInput.allCases where keys[input] == ours[input] {
                    writes.append(KnobWrite(layer: layer, input: input, keycode: own[input]))
                }
                afterwards[layer] = nil
            }
        }
        return KnobTakeoverPlan(writes: writes, originals: kept, originalsAfterwards: afterwards)
    }
}
