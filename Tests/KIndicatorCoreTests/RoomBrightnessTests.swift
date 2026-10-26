import Foundation
import Testing
@testable import KIndicatorCore

struct RoomBrightnessTests {
    let room = RoomBrightness(enabled: true, dark: 64, bright: 255)

    @Test func endsOfTheRange() {
        #expect(room.brightness(lux: 0) == 64)
        #expect(room.brightness(lux: RoomBrightness.darkLux) == 64)
        #expect(room.brightness(lux: RoomBrightness.brightLux) == 255)
        #expect(room.brightness(lux: 50_000) == 255)
    }

    @Test func inBetweenOnALogScale() {
        // Halfway in log terms is the geometric mean of the ends.
        let middle = (RoomBrightness.darkLux * RoomBrightness.brightLux).squareRoot()
        #expect(room.brightness(lux: middle) == 160)
        #expect(room.brightness(lux: 20) < room.brightness(lux: 100))
    }

    @Test func brighterInTheDarkWorksToo() {
        let reversed = RoomBrightness(enabled: true, dark: 200, bright: 0)
        #expect(reversed.brightness(lux: 1) == 200)
        #expect(reversed.brightness(lux: 1000) == 0)
    }

    @Test func medianIgnoresAPassingShadow() {
        #expect(RoomLightPlan.median([]) == nil)
        #expect(RoomLightPlan.median([40]) == 40)
        // A hand over the sensor for two seconds.
        #expect(RoomLightPlan.median([40, 41, 0, 0, 39]) == 39)
        // A lamp turned on stays on.
        #expect(RoomLightPlan.median([4, 4, 300, 300, 300]) == 300)
    }

    @Test func smallChangesOfLightAreIgnored() {
        #expect(RoomLightPlan.light(40, current: nil) == 40)
        #expect(RoomLightPlan.light(50, current: 40) == 40)
        #expect(RoomLightPlan.light(30, current: 40) == 40)
        #expect(RoomLightPlan.light(60, current: 40) == 60)
        #expect(RoomLightPlan.light(20, current: 40) == 20)
    }

    @Test func darkAndBrightRoomsAreAlwaysReached() {
        // An evening lamp reads 2–6 lux: all of it is a dark room.
        #expect(RoomLightPlan.light(2, current: nil) == RoomBrightness.darkLux)
        #expect(RoomLightPlan.light(6, current: RoomBrightness.darkLux) == RoomBrightness.darkLux)
        #expect(RoomLightPlan.light(3, current: 7) == RoomBrightness.darkLux)
        #expect(RoomLightPlan.light(1000, current: 300) == RoomBrightness.brightLux)
    }

    @Test func fadesInSteps() {
        var shown: UInt8 = 64
        var steps = 0
        while shown != 255 {
            shown = RoomLightPlan.step(from: shown, to: 255)
            steps += 1
        }
        #expect(steps == 16)
        #expect(RoomLightPlan.step(from: 100, to: 95) == 95)
        #expect(RoomLightPlan.step(from: 255, to: 0) == 243)
    }

    @Test func decodesWhatItEncodes() throws {
        let again = try JSONDecoder().decode(RoomBrightness.self, from: JSONEncoder().encode(room))
        #expect(again == room)
    }
}
