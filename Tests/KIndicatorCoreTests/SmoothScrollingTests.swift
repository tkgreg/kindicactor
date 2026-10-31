import Foundation
import Testing
@testable import KIndicatorCore

struct SmoothScrollingTests {
    let glide = 0.27

    /// Runs frames at `hz` for `seconds`; the vertical pixels of each frame.
    func frames(_ motion: inout ScrollMotion, hz: Double, seconds: Double) -> [Int] {
        (0..<Int((seconds * hz).rounded())).map { _ in motion.advance(by: 1 / hz, glide: glide).vertical }
    }

    func notched(_ lines: Double = 1, distance: Double = 120) -> ScrollMotion {
        var motion = ScrollMotion()
        motion.notch(.vertical, lines: lines, at: 0, distance: distance, acceleration: 1)
        return motion
    }

    // MARK: Glides

    @Test func aNotchScrollsExactlyItsDistanceAtAnyFrameRate() {
        for hz in [60.0, 120.0, 47.0] {
            var motion = notched()
            #expect(frames(&motion, hz: hz, seconds: 2).reduce(0, +) == 120)
            #expect(!motion.isMoving)
        }
        var down = notched(-1, distance: 37.3)
        #expect(frames(&down, hz: 120, seconds: 2).reduce(0, +) == -37)
    }

    @Test func theGlideTakesTheSameTimeAtAnyFrameRate() {
        var sixty = notched()
        var oneTwenty = notched()
        let at60 = frames(&sixty, hz: 60, seconds: glide).reduce(0, +)
        let at120 = frames(&oneTwenty, hz: 120, seconds: glide).reduce(0, +)
        // 95% of 120 px when the glide time is up, either way.
        #expect(abs(at60 - 114) <= 1)
        #expect(abs(at120 - 114) <= 1)
    }

    @Test func aGlideEasesInAndOut() {
        var motion = notched(distance: 300)
        let moves = frames(&motion, hz: 120, seconds: 1)
        let peak = moves.firstIndex(of: moves.max()!)!
        #expect(peak > 2)
        #expect(moves[0] < moves[peak])
        #expect(moves.allSatisfy { $0 >= 0 })
        #expect(moves.last == 0)
    }

    @Test func aDroppedFrameDoesntChangeTheWay() {
        var steady = notched()
        var dropped = notched()
        _ = frames(&steady, hz: 60, seconds: 0.1)
        _ = dropped.advance(by: 0.05, glide: glide)
        _ = dropped.advance(by: 0.05, glide: glide)
        #expect(abs(steady.vertical.offset - dropped.vertical.offset) < 0.01)
    }

    // MARK: Notches

    @Test func turningTheOtherWayStopsAtOnce() {
        var motion = notched(distance: 300)
        _ = frames(&motion, hz: 120, seconds: 0.05)
        motion.notch(.vertical, lines: -1, at: 0.5, distance: 120, acceleration: 1)
        let moves = frames(&motion, hz: 120, seconds: 2)
        #expect(moves.allSatisfy { $0 <= 0 })
        #expect(moves.reduce(0, +) == -120)
    }

    @Test func aBounceInAFastSpinIsIgnored() {
        var motion = ScrollMotion()
        for tick in 0..<5 {
            motion.notch(.vertical, lines: 1, at: Double(tick) * 0.02, distance: 100, acceleration: 0)
        }
        let bounce = motion.notch(.vertical, lines: -1, at: 0.09, distance: 100, acceleration: 0)
        #expect(!bounce)
        #expect(frames(&motion, hz: 120, seconds: 2).reduce(0, +) == 500)
        // A deliberate turn back, slower, counts.
        let back = motion.notch(.vertical, lines: -1, at: 3, distance: 100, acceleration: 0)
        #expect(back)
    }

    @Test func fastSpinsGoFarther() {
        func travel(every interval: Double, acceleration: Double) -> Int {
            var motion = ScrollMotion()
            for tick in 0..<10 {
                motion.notch(.vertical, lines: 1, at: Double(tick) * interval, distance: 100, acceleration: acceleration)
            }
            return frames(&motion, hz: 120, seconds: 3).reduce(0, +)
        }
        #expect(travel(every: 0.4, acceleration: 1) == 1000)
        // A quick scroll, 14 notches a second, isn't sped up; a flick is.
        #expect(travel(every: 0.07, acceleration: 1) == 1000)
        #expect(travel(every: 0.0125, acceleration: 0) == 1000)
        #expect(travel(every: 0.0125, acceleration: 1) > 2000)
        #expect(ScrollMotion.speedUp(rate: 20, acceleration: 1) == 1)
        #expect(ScrollMotion.speedUp(rate: 40, acceleration: 1) == 2)
        #expect(ScrollMotion.speedUp(rate: 200, acceleration: 2) == 7)
    }

    @Test func highResolutionWheelsScrollTheirFraction() {
        var motion = ScrollMotion()
        for tick in 0..<8 {
            motion.notch(.vertical, lines: 0.25, at: Double(tick) * 0.005, distance: 100, acceleration: 2)
        }
        #expect(frames(&motion, hz: 120, seconds: 2).reduce(0, +) == 200)
    }

    @Test func theFasterKeyMultiplies() {
        var motion = ScrollMotion()
        motion.notch(.horizontal, lines: -1, at: 0, distance: 100, acceleration: 1, boost: 5)
        var sideways = 0
        for _ in 0..<240 { sideways += motion.advance(by: 1 / 120, glide: glide).horizontal }
        #expect(sideways == -500)
    }

    @Test func stopDropsTheRestAndFinishSendsIt() {
        var stopped = notched()
        _ = frames(&stopped, hz: 120, seconds: 0.05)
        stopped.stop()
        #expect(!stopped.isMoving)
        #expect(frames(&stopped, hz: 120, seconds: 1).reduce(0, +) == 0)

        var finished = notched()
        let sent = frames(&finished, hz: 120, seconds: 0.05).reduce(0, +)
        let rest = finished.finish().vertical
        #expect(sent + rest == 120)
        #expect(!finished.isMoving)
    }

    // MARK: Settings

    @Test func settingsSurviveEncodingAndKeepNone() throws {
        var settings = SmoothScrolling()
        settings.enabled = true
        settings.plainKey = nil
        settings.excludedApps = [AppRef(bundleID: "com.apple.Preview", name: "Preview")]
        let decoded = try JSONDecoder().decode(SmoothScrolling.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.plainKey == nil)
        #expect(decoded.excludes("com.apple.Preview"))
        let old = try JSONDecoder().decode(SmoothScrolling.self, from: Data(#"{"enabled":true}"#.utf8))
        #expect(old.enabled && old.fasterKey == .option && old.distance == 144 && old.glide == 0.64)
    }
}
