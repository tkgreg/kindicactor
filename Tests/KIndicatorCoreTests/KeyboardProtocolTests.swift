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
    }

    @Test func replyHeaders() {
        #expect(KeyboardRequest.activeLayer.replyHeader == [0xA3])
        #expect(KeyboardRequest.getLighting(.color).replyHeader == [0x08, 0x03, 0x04])
        #expect(KeyboardRequest.keymapBuffer(offset: 28, size: 28).replyHeader == [0x12, 0x00, 28])
        #expect(KeyboardRequest.saveLighting.replyHeader == [0x09, 0x03])
        #expect(KeyboardRequest.setKeyColors(first: 0, []).replyHeader == [0xA8, 0x0A])
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
