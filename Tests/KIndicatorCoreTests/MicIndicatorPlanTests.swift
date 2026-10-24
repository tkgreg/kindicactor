import Foundation
import Testing
@testable import KIndicatorCore

struct MicIndicatorPlanTests {
    let ledMap = LEDMap(leds: [KeyPosition(row: 0, col: 0): 0, KeyPosition(row: 0, col: 5): 5])
    let indicator = MicIndicator(enabled: true, key: KeyPosition(row: 0, col: 5), hue: 0, saturation: 255)
    let purple = KeyColor(hue: 208, saturation: 255, value: 255)
    let red = KeyColor(hue: 0, saturation: 255, value: 255)

    @Test func wantedNeedsEverything() {
        let wanted = WantedIndicator(led: 5, hue: 0, saturation: 255)
        #expect(MicIndicatorPlan.wanted(indicator, micInUse: true, shownEffect: 23, ledMap: ledMap) == wanted)
        var off = indicator
        off.enabled = false
        #expect(MicIndicatorPlan.wanted(off, micInUse: true, shownEffect: 23, ledMap: ledMap) == nil)
        #expect(MicIndicatorPlan.wanted(indicator, micInUse: false, shownEffect: 23, ledMap: ledMap) == nil)
        #expect(MicIndicatorPlan.wanted(indicator, micInUse: true, shownEffect: 1, ledMap: ledMap) == nil)
        #expect(MicIndicatorPlan.wanted(indicator, micInUse: true, shownEffect: nil, ledMap: ledMap) == nil)
        #expect(MicIndicatorPlan.wanted(indicator, micInUse: true, shownEffect: 23, ledMap: nil) == nil)
        var knob = indicator
        knob.key = KeyPosition(row: 0, col: 13)
        #expect(MicIndicatorPlan.wanted(knob, micInUse: true, shownEffect: 23, ledMap: ledMap) == nil)
    }

    @Test func lightsAKeyThenRests() {
        let wanted = WantedIndicator(led: 5, hue: 0, saturation: 255)
        #expect(MicIndicatorPlan.step(shown: nil, wanted: wanted, stale: false) == .light(wanted))
        let shown = ShownIndicator(led: 5, own: purple, shown: MicIndicatorPlan.color(for: wanted, own: purple))
        #expect(MicIndicatorPlan.step(shown: shown, wanted: wanted, stale: false) == .nothing)
    }

    @Test func restoresWhenOffOrMoved() {
        let shown = ShownIndicator(led: 5, own: purple, shown: red)
        #expect(MicIndicatorPlan.step(shown: shown, wanted: nil, stale: false) == .restore(shown))
        let elsewhere = WantedIndicator(led: 0, hue: 0, saturation: 255)
        #expect(MicIndicatorPlan.step(shown: shown, wanted: elsewhere, stale: false) == .restore(shown))
        #expect(MicIndicatorPlan.step(shown: nil, wanted: nil, stale: true) == .nothing)
    }

    @Test func recolorsWhenColourChangesOrStale() {
        let shown = ShownIndicator(led: 5, own: purple, shown: red)
        let green = WantedIndicator(led: 5, hue: 85, saturation: 255)
        #expect(MicIndicatorPlan.step(shown: shown, wanted: green, stale: false)
            == .recolor(shown, KeyColor(hue: 85, saturation: 255, value: 255)))
        let same = WantedIndicator(led: 5, hue: 0, saturation: 255)
        #expect(MicIndicatorPlan.step(shown: shown, wanted: same, stale: true) == .recolor(shown, red))
    }

    @Test func keepsTheKeysBrightness() {
        let wanted = WantedIndicator(led: 5, hue: 0, saturation: 255)
        #expect(MicIndicatorPlan.color(for: wanted, own: KeyColor(hue: 208, saturation: 255, value: 120)).value == 120)
        #expect(MicIndicatorPlan.color(for: wanted, own: KeyColor(hue: 0, saturation: 0, value: 0)).value == 255)
    }

    /// Carrying out the steps the way the app does ends after moving the indicator.
    @Test func stepsEndAfterMoving() {
        var shown: ShownIndicator? = ShownIndicator(led: 0, own: purple, shown: red)
        let wanted = WantedIndicator(led: 5, hue: 0, saturation: 255)
        var steps: [IndicatorStep] = []
        while steps.count < 5 {
            let step = MicIndicatorPlan.step(shown: shown, wanted: wanted, stale: false)
            steps.append(step)
            switch step {
            case .nothing: break
            case .restore: shown = nil
            case .light(let wanted): shown = ShownIndicator(led: wanted.led, own: purple, shown: MicIndicatorPlan.color(for: wanted, own: purple))
            case .recolor(let current, let color): shown = ShownIndicator(led: current.led, own: current.own, shown: color)
            }
            if step == .nothing { break }
        }
        #expect(steps.count == 3)
        #expect(shown?.led == 5)
    }

    @Test func decodesTheFirstSettingsFormat() throws {
        let old = Data(#"{"enabled":true,"led":5,"hue":85,"saturation":255}"#.utf8)
        let indicator = try JSONDecoder().decode(MicIndicator.self, from: old)
        #expect(indicator == MicIndicator(enabled: true, key: KeyPosition(row: 0, col: 5), hue: 85, saturation: 255))
        let again = try JSONDecoder().decode(MicIndicator.self, from: JSONEncoder().encode(indicator))
        #expect(again == indicator)
    }
}
