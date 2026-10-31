import Testing
@testable import KIndicatorCore

/// Requests and replies as seen on a V6 Ultra 8K over the 2.4 GHz dongle.
struct KeyboardProtocolTests {
    @Test func requestBytes() {
        #expect(KeyboardRequest.activeLayer.bytes == [0xA3])
        #expect(KeyboardRequest.getLighting(.effect).bytes == [0x08, 0x03, 0x02])
        #expect(KeyboardRequest.setEffect(23).bytes == [0x07, 0x03, 0x02, 23])
        #expect(KeyboardRequest.setColor(hue: 21, saturation: 255).bytes == [0x07, 0x03, 0x04, 21, 255])
        #expect(KeyboardRequest.saveLighting.bytes == [0x09, 0x03])
        #expect(KeyboardRequest.keymapBuffer(offset: 280, size: 28).bytes == [0x12, 0x01, 0x18, 28])
        #expect(KeyboardRequest.ledNumbers(row: 3).bytes == [0xA8, 0x06, 3, 0xFF, 0xFF, 0xFF])
        #expect(KeyboardRequest.getKeyColors(first: 5, count: 9).bytes == [0xA8, 0x09, 5, 9])
        let red = KeyColor(hue: 0, saturation: 255, value: 255)
        #expect(KeyboardRequest.setKeyColors(first: 0, [red]).bytes == [0xA8, 0x0A, 0, 1, 0, 255, 255])
        let knob = KeyPosition(row: 0, col: 13)
        #expect(KeyboardRequest.getKeycode(layer: 1, knob).bytes == [0x04, 1, 0, 13])
        #expect(KeyboardRequest.setKeycode(layer: 0, knob, 0x006F).bytes == [0x05, 0, 0, 13, 0x00, 0x6F])
        #expect(KeyboardRequest.getEncoder(layer: 2, encoder: 0, clockwise: true).bytes == [0x14, 2, 0, 1])
        #expect(KeyboardRequest.setEncoder(layer: 0, encoder: 0, clockwise: false, 0x7828).bytes
            == [0x15, 0, 0, 0, 0x78, 0x28])
    }

    @Test func replyHeaders() {
        #expect(KeyboardRequest.activeLayer.replyHeader == [0xA3])
        #expect(KeyboardRequest.getLighting(.color).replyHeader == [0x08, 0x03, 0x04])
        #expect(KeyboardRequest.keymapBuffer(offset: 28, size: 28).replyHeader == [0x12, 0x00, 28])
        #expect(KeyboardRequest.saveLighting.replyHeader == [0x09, 0x03])
        #expect(KeyboardRequest.setKeyColors(first: 0, []).replyHeader == [0xA8, 0x0A])
        #expect(KeyboardRequest.getEncoder(layer: 1, encoder: 0, clockwise: false).replyHeader == [0x14, 1, 0, 0])
        #expect(KeyboardRequest.setKeycode(layer: 0, KeyPosition(row: 0, col: 13), 0x6F).replyHeader == [0x05, 0, 0, 13])
    }

    @Test func decodesReplies() {
        #expect(KeyboardReply.viaProtocolVersion([0x01, 0x00, 0x0C, 0, 0, 0]) == 12)
        #expect(KeyboardReply.layerCount([0x11, 4]) == 4)
        #expect(KeyboardReply.layerCount([0x11, 0]) == nil)
        #expect(KeyboardReply.activeLayer([0xA3, 1]) == 1)
        #expect(KeyboardReply.activeLayer([0xA3, 40]) == nil)
        #expect(KeyboardReply.firmwareVersion([0xA1] + Array("1.0.2".utf8) + [0, 7]) == "1.0.2")
        #expect(KeyboardReply.lightingValue([0x08, 0x03, 0x02, 23, 0]) == [23, 0])
        #expect(KeyboardReply.lightingValue([0x08, 0x03, 0x02, 23]) == nil)
        #expect(KeyboardReply.keyColors([0xA8, 0x09, 0, 208, 255, 255], count: 1) == [KeyColor(hue: 208, saturation: 255, value: 255)])
        #expect(KeyboardReply.keyColors([0xA8, 0x09, 0, 208], count: 1) == nil)
        #expect(KeyboardReply.keymapChunk([0x12, 0, 0, 2, 0x00, 0x29], size: 2) == [0x00, 0x29])
        // The knob on the Fn layer: turned left dims the lighting, pressed toggles it.
        #expect(KeyboardReply.keycode([0x14, 0x01, 0x00, 0x00, 0x78, 0x28, 0, 0]) == 0x7828)
        #expect(KeyboardReply.keycode([0x04, 0x01, 0x00, 0x0D, 0x78, 0x20, 0, 0]) == 0x7820)
        #expect(KeyboardReply.keycode([0x15, 0x01, 0x00, 0x00, 0x78, 0x28]) == nil)
        #expect(KeyboardReply.keycode([0x14, 0x01, 0x00, 0x00]) == nil)
    }

    @Test func decodesLEDNumbers() {
        // Row 0: Esc, F1-F12, the knob (no LED), six more; then columns past the matrix.
        let reply: [UInt8] = [0xA8, 0x06, 0] + Array(0...12) + [255] + Array(13...18) + [0, 0, 0]
        let leds = KeyboardReply.ledNumbers(reply, cols: 20)
        #expect(leds?.count == 20)
        #expect(leds?[0] == 0)
        #expect(leds?[13] == nil)
        #expect(leds?[19] == 18)
    }

    @Test func decodesPairedDevices() {
        // Slot 1: the V6 Ultra 8K ANSI, active; slots 2 and 3 empty.
        let reply: [UInt8] = [0xB2, 0, 0x34, 0x34, 0x60, 0x0C, 1] + [UInt8](repeating: 0, count: 10)
        let paired = KeyboardReply.pairedDevices(reply)
        #expect(paired.count == 1)
        #expect(paired.first?.vendorID == 0x3434)
        #expect(paired.first?.productID == 0x0C60)
    }
}
