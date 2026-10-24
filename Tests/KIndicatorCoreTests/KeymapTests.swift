import Testing
@testable import KIndicatorCore

struct KeymapTests {
    /// Two layers of one row with two keys: Esc, A; then transparent, F1.
    let keymap = Keymap(buffer: [0x00, 0x29, 0x00, 0x04, 0x00, 0x01, 0x00, 0x3A], layerCount: 2, rows: 1, cols: 2)

    @Test func readsKeycodesFromTheBuffer() {
        #expect(keymap.layers == [[0x0029, 0x0004], [0x0001, 0x003A]])
        #expect(keymap.keycode(layer: 1, at: KeyPosition(row: 0, col: 1)) == 0x003A)
        #expect(keymap.keycode(layer: 2, at: KeyPosition(row: 0, col: 0)) == nil)
        #expect(keymap.keycode(layer: 0, at: KeyPosition(row: 0, col: 2)) == nil)
    }

    @Test func transparentKeysFallThrough() {
        #expect(keymap.resolved(layer: 1, at: KeyPosition(row: 0, col: 0))?.keycode == 0x0029)
        #expect(keymap.resolved(layer: 1, at: KeyPosition(row: 0, col: 0))?.layer == 0)
        #expect(keymap.resolved(layer: 1, at: KeyPosition(row: 0, col: 1))?.layer == 1)
    }

    @Test func requestsCoverTheWholeKeymap() {
        // 4 layers × 6 rows × 20 columns × 2 bytes = 960 bytes: 34 full chunks and 8 bytes.
        let requests = Keymap.requests(layerCount: 4, rows: 6, cols: 20)
        #expect(requests.count == 35)
        #expect(requests.first == .keymapBuffer(offset: 0, size: 28))
        #expect(requests.last == .keymapBuffer(offset: 952, size: 8))
    }

    @Test func labels() {
        #expect(Keycode.label(0x0000) == "")
        #expect(Keycode.label(0x0001) == "▽")
        #expect(Keycode.label(0x0029) == "Esc")
        #expect(Keycode.label(0x0004) == "A")
        #expect(Keycode.label(0x0027) == "0")
        #expect(Keycode.label(0x003A) == "F1")
        #expect(Keycode.label(0x0068) == "F13")
        #expect(Keycode.label(0x0062) == "0")
        #expect(Keycode.label(0x00E3) == "⌘")
        #expect(Keycode.label(0x00BE) == "Bri−")
        #expect(Keycode.label(0x5221) == "MO1")
        #expect(Keycode.label(0x5261) == "TG1")
        #expect(Keycode.label(0x7700) == "M0")
        #expect(Keycode.label(0x7828) == "Lit−")
        #expect(Keycode.label(0x6000) == "6000")
    }

    @Test func labelsShortcutsAndCustomKeys() {
        // From the user's keymap: F4 sends ⌃⌥⌘E; the bottom row has Keychron's Mac keys.
        #expect(Keycode.label(0x0D08) == "⌃⌥⌘E")
        let names = KeyboardLayout.v6Ultra8KANSI.customKeycodeNames
        #expect(Keycode.label(0x7E07, customNames: names) == "⌥")
        #expect(Keycode.label(0x7E09, customNames: names) == "⌘")
        #expect(Keycode.label(0x7E0D, customNames: names) == "Emoji")
        #expect(Keycode.label(0x7E3F, customNames: names) == "KB63")
    }

    @Test func ledMap() {
        let map = LEDMap(rows: [[0, 1, nil], [19, nil, 2]])
        #expect(map.led(at: KeyPosition(row: 0, col: 1)) == 1)
        #expect(map.led(at: KeyPosition(row: 0, col: 2)) == nil)
        #expect(map.led(at: KeyPosition(row: 1, col: 0)) == 19)
        #expect(LEDMap.requests(rows: 2) == [.ledNumbers(row: 0), .ledNumbers(row: 1)])
    }
}
