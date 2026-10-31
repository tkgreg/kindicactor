import Foundation
import Testing
@testable import KIndicatorCore

struct MouseControlTests {
    var clicks = DoubleClick(interval: 0.3)

    // MARK: Actions

    @Test func buttonNumbers() {
        #expect(MouseButton(buttonNumber: 3) == .back)
        #expect(MouseButton(buttonNumber: 4) == .forward)
        #expect(MouseButton(buttonNumber: 2) == nil)
        #expect(MouseButton.allCases.map(\.buttonNumber) == [3, 4])
    }

    @Test func appActionsFallBackToAllApps() {
        let closeTab = KeyAction.shortcut(Hotkey(keyCode: 0x0D, modifiers: Hotkey.command, keyName: "W"))
        let safari = AppActions(bundleID: "com.apple.Safari", name: "Safari", mapping: MouseMapping(back: closeTab))
        let control = MouseControl(enabled: true, allApps: MouseMapping(forward: .media(.playPause)), apps: [safari])
        #expect(control.action(for: .back, app: "com.apple.Safari") == closeTab)
        #expect(control.action(for: .forward, app: "com.apple.Safari") == .media(.playPause))
        #expect(control.action(for: .back, app: "com.apple.finder") == .nothing)
        #expect(control.action(for: .back, app: nil) == .nothing)
    }

    @Test func knobSettingsKeepTheirFormat() throws {
        // Saved by 1.2: apps as {bundleID, name, path, mapping}, actions as before the rename.
        let saved = #"{"enabled":true,"layers":[0],"allApps":{"turnLeft":{"media":{"_0":"volumeDown"}}},"apps":[{"bundleID":"a.b","name":"B","mapping":{"press":{"nothing":{}}}}]}"#
        let control = try JSONDecoder().decode(KnobControl.self, from: Data(saved.utf8))
        #expect(control.allApps.turnLeft == .media(.volumeDown))
        #expect(control.apps.first?.mapping.press == .nothing)
        #expect(control.action(for: .press, app: "a.b") == .nothing)
    }

    @Test func settingsSurviveEncoding() throws {
        let control = MouseControl(enabled: true, doubleClickInterval: 0.25, allApps: MouseMapping(back: .media(.mute)),
                                   apps: [AppActions(bundleID: "a.b", name: "B", mapping: MouseMapping(forward: .nothing))])
        let decoded = try JSONDecoder().decode(MouseControl.self, from: JSONEncoder().encode(control))
        #expect(decoded == control)
    }

    // MARK: Double clicks

    @Test mutating func aSingleClickIsSentOnOnceTheIntervalRunsOut() {
        #expect(clicks.handle(.back, isDown: true, at: 0, wanted: true) == (false, []))
        #expect(clicks.handle(.back, isDown: false, at: 0.08, wanted: false) == (false, []))
        #expect(clicks.deadline == 0.3)
        #expect(clicks.timeout(at: 0.2).isEmpty)
        #expect(clicks.timeout(at: 0.3) == [.replay(.back, released: true)])
        #expect(clicks.phase == .idle)
        #expect(clicks.deadline == nil)
    }

    @Test mutating func aDoubleClickRunsTheActionAndSendsNothing() {
        _ = clicks.handle(.forward, isDown: true, at: 0, wanted: true)
        _ = clicks.handle(.forward, isDown: false, at: 0.08, wanted: false)
        #expect(clicks.handle(.forward, isDown: true, at: 0.2, wanted: true) == (false, [.run(.forward)]))
        #expect(clicks.deadline == nil)
        #expect(clicks.handle(.forward, isDown: false, at: 0.27, wanted: false) == (false, []))
        #expect(clicks.phase == .idle)
    }

    @Test mutating func aButtonWithoutAnActionClicksAtOnce() {
        #expect(clicks.handle(.back, isDown: true, at: 0, wanted: false) == (true, []))
        #expect(clicks.handle(.back, isDown: false, at: 0.1, wanted: false) == (true, []))
        #expect(clicks.phase == .idle)
    }

    @Test mutating func aButtonHeldDownIsPressedOnceTheIntervalRunsOut() {
        _ = clicks.handle(.back, isDown: true, at: 0, wanted: true)
        #expect(clicks.timeout(at: 0.3) == [.replay(.back, released: false)])
        #expect(clicks.handle(.back, isDown: false, at: 1, wanted: false) == (true, []))
    }

    @Test mutating func anotherButtonSendsTheHeldClickFirst() {
        _ = clicks.handle(.back, isDown: true, at: 0, wanted: true)
        _ = clicks.handle(.back, isDown: false, at: 0.05, wanted: false)
        #expect(clicks.handle(.forward, isDown: true, at: 0.1, wanted: true) == (false, [.replay(.back, released: true)]))
        #expect(clicks.phase == .pressed(.forward, since: 0.1))
    }

    @Test mutating func aLateSecondClickIsAClickOfItsOwn() {
        // The timer came late: the first click goes out, the second starts a new wait.
        _ = clicks.handle(.back, isDown: true, at: 0, wanted: true)
        _ = clicks.handle(.back, isDown: false, at: 0.05, wanted: false)
        #expect(clicks.handle(.back, isDown: true, at: 0.35, wanted: true) == (false, [.replay(.back, released: true)]))
        #expect(clicks.phase == .pressed(.back, since: 0.35))
    }

    @Test mutating func flushSendsWhatIsHeld() {
        _ = clicks.handle(.forward, isDown: true, at: 0, wanted: true)
        #expect(clicks.flush() == [.replay(.forward, released: false)])
        #expect(clicks.flush().isEmpty)
    }
}
