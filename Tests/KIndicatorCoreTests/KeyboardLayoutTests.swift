import Testing
@testable import KIndicatorCore

struct KeyboardLayoutTests {
    @Test(arguments: [
        (KeyboardLayout.v6Ultra8KANSI, 109),
        (KeyboardLayout.v6Ultra8KISO, 110),
        (KeyboardLayout.v6Ultra8KJIS, 113),
    ])
    func bundledLayoutsAreWhole(layout: KeyboardLayout, keys: Int) {
        #expect(layout.keys.count == keys)
        #expect(Set(layout.keys.map(\.position)).count == keys)
        #expect(layout.keys.filter(\.isKnob).map(\.position) == [KeyPosition(row: 0, col: 13)])
        for key in layout.keys {
            let bounds = key.bounds
            #expect(bounds.x >= 0 && bounds.maxX <= layout.width, "\(key.position) sticks out sideways")
            #expect(bounds.y >= 0 && bounds.maxY <= layout.height, "\(key.position) sticks out vertically")
            #expect(key.position.row < layout.rows && key.position.col < layout.cols)
        }
    }

    @Test func isoEnterIsLShaped() throws {
        let enter = try #require(KeyboardLayout.v6Ultra8KISO.key(at: KeyPosition(row: 2, col: 13)))
        #expect(enter.secondRect == KeyRect(x: 13.5, y: 2.25, width: 1.5, height: 1))
        #expect(enter.bounds == KeyRect(x: 13.5, y: 2.25, width: 1.5, height: 2))
    }

    @Test func layoutByProductID() {
        #expect(KeyboardLayout.forProduct(0x0C60)?.name == "Keychron V6 Ultra 8K ANSI")
        #expect(KeyboardLayout.forProduct(0x0C61)?.name == "Keychron V6 Ultra 8K ISO")
        #expect(KeyboardLayout.forProduct(0x1234) == nil)
    }
}
