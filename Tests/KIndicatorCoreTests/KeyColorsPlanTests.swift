import Foundation
import Testing
@testable import KIndicatorCore

struct KeyColorsPlanTests {
    let ledMap = LEDMap(leds: [KeyPosition(row: 0, col: 0): 0, KeyPosition(row: 0, col: 15): 14])
    let steady = MicIndicator(enabled: true, key: KeyPosition(row: 0, col: 15), hue: 0, saturation: 255, style: .steady)
    let cyan = KeyColor(hue: 132, saturation: 211, value: 255)
    let red = KeyColor(hue: 0, saturation: 255, value: 255)
    let green = KeyColor(hue: 85, saturation: 255, value: 255)

    // MARK: Overlay

    @Test func overlayNeedsIndicatorMicPerKeyAndLED() {
        let shown = KeyColorsPlan.overlay(indicator: steady, micInUse: true, shownEffect: 23, fill: green,
                                          ledMap: ledMap, elapsed: 0)
        #expect(shown == KeyOverlay(fill: green, keys: [14: red]))
        var off = steady
        off.enabled = false
        let empty = KeyOverlay()
        #expect(KeyColorsPlan.overlay(indicator: off, micInUse: true, shownEffect: 23, fill: nil, ledMap: ledMap, elapsed: 0) == empty)
        #expect(KeyColorsPlan.overlay(indicator: steady, micInUse: false, shownEffect: 23, fill: nil, ledMap: ledMap, elapsed: 0) == empty)
        #expect(KeyColorsPlan.overlay(indicator: steady, micInUse: true, shownEffect: 1, fill: nil, ledMap: ledMap, elapsed: 0) == empty)
        #expect(KeyColorsPlan.overlay(indicator: steady, micInUse: true, shownEffect: 23, fill: nil, ledMap: nil, elapsed: 0) == empty)
    }

    @Test func pulseGoesFromFullColourToPaleAndBack() {
        var pulse = steady
        pulse.style = .pulse
        let period = KeyColorsPlan.pulsePeriod
        #expect(KeyColorsPlan.indicatorColor(pulse, elapsed: 0) == red)
        #expect(KeyColorsPlan.indicatorColor(pulse, elapsed: period / 2).saturation == 38)
        #expect(KeyColorsPlan.indicatorColor(pulse, elapsed: period) == red)
        #expect(KeyColorsPlan.indicatorColor(steady, elapsed: period / 2) == red)
        let pale = KeyColorsPlan.indicatorColor(pulse, elapsed: period / 2)
        #expect(pale.hue == 0 && pale.value == 255)
    }

    // MARK: Steps

    @Test func indicatorReadsTheKeyThenLightsIt() {
        let overlay = KeyOverlay(keys: [14: red])
        #expect(KeyColorsPlan.step(KeyColors(), overlay: overlay, ledCount: 108, stale: false)
            == .read([.getKeyColors(first: 14, count: 1)]))
        let known = KeyColors(own: [14: cyan])
        let lit = KeyColors(own: [14: cyan], shown: [14: red])
        #expect(KeyColorsPlan.step(known, overlay: overlay, ledCount: 108, stale: false)
            == .write([.setKeyColors(first: 14, [red])], lit))
        #expect(KeyColorsPlan.step(lit, overlay: overlay, ledCount: 108, stale: false) == .nothing)
    }

    @Test func indicatorOffGivesTheKeyBackAndForgetsIt() {
        let lit = KeyColors(own: [14: cyan], shown: [14: red])
        #expect(KeyColorsPlan.step(lit, overlay: KeyOverlay(), ledCount: 108, stale: false)
            == .write([.setKeyColors(first: 14, [cyan])], KeyColors()))
        #expect(KeyColorsPlan.step(KeyColors(), overlay: KeyOverlay(), ledCount: 108, stale: true) == .nothing)
    }

    @Test func staleColoursAreSentAgain() {
        let lit = KeyColors(own: [14: cyan], shown: [14: red])
        #expect(KeyColorsPlan.step(lit, overlay: KeyOverlay(keys: [14: red]), ledCount: 108, stale: true)
            == .write([.setKeyColors(first: 14, [red])], lit))
    }

    @Test func pulseSendsOnlyTheNewShade() {
        let dim = KeyColor(hue: 0, saturation: 128, value: 255)
        // Only key 14 changes; the rest of the fill is already shown.
        let all = KeyColors(own: Dictionary(uniqueKeysWithValues: (0..<15).map { (UInt8($0), cyan) }),
                            shown: Dictionary(uniqueKeysWithValues: (0..<15).map { (UInt8($0), $0 == 14 ? red : green) }))
        guard case .write(let requests, let result) = KeyColorsPlan.step(
            all, overlay: KeyOverlay(fill: green, keys: [14: dim]), ledCount: 15, stale: false) else {
            Issue.record("expected a write")
            return
        }
        #expect(requests == [.setKeyColors(first: 14, [dim])])
        #expect(result.shown[14] == dim)
        #expect(result.shown[0] == green)
    }

    @Test func fillReadsAndPaintsEveryKey() {
        let overlay = KeyOverlay(fill: green, keys: [14: red])
        #expect(KeyColorsPlan.step(KeyColors(), overlay: overlay, ledCount: 20, stale: false) == .read([
            .getKeyColors(first: 0, count: 9), .getKeyColors(first: 9, count: 9), .getKeyColors(first: 18, count: 2),
        ]))
        // Key 3 is green already, so it needs nothing.
        var own = Dictionary(uniqueKeysWithValues: (0..<20).map { (UInt8($0), cyan) })
        own[3] = green
        guard case .write(let requests, let result) = KeyColorsPlan.step(
            KeyColors(own: own), overlay: overlay, ledCount: 20, stale: false) else {
            Issue.record("expected a write")
            return
        }
        // Keys 0-2, 4-12 and 13-19: key 3 splits the first run.
        #expect(requests.map(\.bytes.count) == [4 + 3 * 3, 4 + 9 * 3, 4 + 7 * 3])
        #expect(requests.first == .setKeyColors(first: 0, [green, green, green]))
        #expect(result.shown.count == 19)
        #expect(result.shown[3] == nil)
        #expect(result.shown[14] == red)
        #expect(result.shown[0] == green)
    }

    @Test func runsOfNeighbours() {
        let runs = KeyColorsPlan.runs(of: [0, 1, 2, 5, 6, 20])
        #expect(runs.map(\.first) == [0, 5, 20])
        #expect(runs.map(\.leds.count) == [3, 2, 1])
        #expect(KeyColorsPlan.runs(of: (0..<10).map { UInt8($0) }).map(\.leds.count) == [9, 1])
    }

    // MARK: Layers drawn key by key

    let perKey = Lighting(effect: 23, brightness: 80, speed: 63, hue: 21, saturation: 255)
    let greenSolid = LayerLighting(effect: 1, hue: 85, saturation: 255)

    @Test func solidColorLayerIsDrawnKeyByKeyWhileTheIndicatorShows() {
        let drawn = LightingPlan.layerTarget(layerLighting: greenSolid, lightsOff: false, indicatorShows: true,
                                             applied: nil, saved: perKey)
        #expect(drawn.overlay == nil)
        #expect(drawn.fill == green)
        let usual = LightingPlan.layerTarget(layerLighting: greenSolid, lightsOff: false, indicatorShows: false,
                                             applied: nil, saved: perKey)
        #expect(usual.overlay == greenSolid)
        #expect(usual.fill == nil)
    }

    @Test func otherLayersKeepTheirEffect() {
        let breathing = LayerLighting(effect: 2, hue: 85, saturation: 255)
        #expect(LightingPlan.layerTarget(layerLighting: breathing, lightsOff: false, indicatorShows: true,
                                         applied: nil, saved: perKey).overlay == breathing)
        var solidSaved = perKey
        solidSaved.effect = 1
        #expect(LightingPlan.layerTarget(layerLighting: greenSolid, lightsOff: false, indicatorShows: true,
                                         applied: nil, saved: solidSaved).fill == nil)
        let asleep = LightingPlan.layerTarget(layerLighting: greenSolid, lightsOff: true, indicatorShows: true,
                                              applied: nil, saved: perKey)
        #expect(asleep.overlay?.effect == 0)
        #expect(asleep.fill == nil)
    }

    // MARK: Settings

    @Test func decodesTheFirstSettingsFormat() throws {
        let old = Data(#"{"enabled":true,"led":5,"hue":85,"saturation":255}"#.utf8)
        let indicator = try JSONDecoder().decode(MicIndicator.self, from: old)
        #expect(indicator == MicIndicator(enabled: true, key: KeyPosition(row: 0, col: 5), hue: 85, saturation: 255,
                                          style: .pulse))
        let again = try JSONDecoder().decode(MicIndicator.self, from: JSONEncoder().encode(steady))
        #expect(again == steady)
    }
}
