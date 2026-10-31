import Foundation
import Testing
@testable import KIndicatorCore

struct MouseControlTests {
    var clicks = DoubleClick(interval: 0.3)
    let none = ButtonActions()
    let clickOnly = ButtonActions(click: true)
    let doubleOnly = ButtonActions(doubleClick: true)
    let both = ButtonActions(click: true, doubleClick: true)
    /// What the special button of the user's mouse sends (kVK_F13).
    let f13 = Hotkey(keyCode: 105, keyName: "F13")

    // MARK: Actions

    @Test func buttonNumbers() {
        #expect(MouseButton(buttonNumber: 2) == .middle)
        #expect(MouseButton(buttonNumber: 3) == .back)
        #expect(MouseButton(buttonNumber: 4) == .forward)
        #expect(MouseButton(buttonNumber: 1) == nil)
        #expect(MouseButton.buttons.map(\.buttonNumber) == [2, 3, 4])
        #expect(MouseButton.key(f13).buttonNumber == nil)
        #expect(MouseButton.key(f13).title == "F13")
    }

    @Test func mouseKeysGetActionsAndAreStoredByName() throws {
        let control = MouseControl(enabled: true, keys: [f13],
                                   allApps: MouseMapping(clicks: [.key(f13): .shortcut(KeyAction.Shortcuts.missionControl)]))
        #expect(control.allButtons == [.middle, .back, .forward, .key(f13)])
        #expect(control.actions(for: .key(f13), app: nil) == clickOnly)
        let data = try JSONEncoder().encode(control)
        #expect(String(decoding: data, as: UTF8.self).contains(#""key 105 0 F13":"#))
        #expect(try JSONDecoder().decode(MouseControl.self, from: data) == control)
    }

    @Test func removingAKeyForgetsItsActions() {
        var control = MouseControl(keys: [f13], allApps: MouseMapping(clicks: [.key(f13): .media(.mute), .back: .media(.mute)]),
                                   apps: [AppActions(bundleID: "a.b", name: "B", mapping: MouseMapping(doubleClicks: [.key(f13): .nothing]))])
        control.removeKey(f13)
        #expect(control.keys.isEmpty)
        #expect(control.allApps == MouseMapping(clicks: [.back: .media(.mute)]))
        #expect(control.apps.first?.mapping == MouseMapping())
    }

    @Test func appActionsFallBackToAllApps() {
        let closeTab = KeyAction.shortcut(KeyAction.Shortcuts.closeWindow)
        let safari = AppActions(bundleID: "com.apple.Safari", name: "Safari",
                                mapping: MouseMapping(doubleClicks: [.back: closeTab]))
        let control = MouseControl(enabled: true, allApps: .navigation, apps: [safari])
        #expect(control.action(for: .doubleClick(.back), app: "com.apple.Safari") == closeTab)
        #expect(control.action(for: .click(.back), app: "com.apple.Safari") == .shortcut(KeyAction.Shortcuts.back))
        #expect(control.action(for: .click(.middle), app: "com.apple.Safari") == .nothing)
        #expect(control.actions(for: .back, app: "com.apple.Safari") == both)
        #expect(control.actions(for: .back, app: "com.apple.finder") == clickOnly)
        #expect(control.actions(for: .middle, app: nil) == none)
    }

    @Test func doubleClickSettingsFromBeforeClicksStillLoad() throws {
        // Saved before clicks had actions: Brave's Back double-click goes to the previous tab.
        let saved = #"{"enabled":true,"doubleClickInterval":0.2,"allApps":{},"apps":[{"bundleID":"com.brave.Browser","name":"Brave Browser","mapping":{"back":{"shortcut":{"_0":{"keyCode":48,"keyName":"⇥","modifiers":393216}}}}}]}"#
        let control = try JSONDecoder().decode(MouseControl.self, from: Data(saved.utf8))
        let previousTab = KeyAction.shortcut(Hotkey(keyCode: 48, modifiers: Hotkey.control | Hotkey.shift, keyName: "⇥"))
        #expect(control.action(for: .doubleClick(.back), app: "com.brave.Browser") == previousTab)
        #expect(control.action(for: .click(.back), app: "com.brave.Browser") == .nothing)
        #expect(control.doubleClickInterval == 0.2)
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
        let control = MouseControl(enabled: true, doubleClickInterval: 0.25, allApps: .navigation,
                                   apps: [AppActions(bundleID: "a.b", name: "B",
                                                     mapping: MouseMapping(clicks: [.middle: .nothing],
                                                                           doubleClicks: [.forward: .media(.mute)]))])
        let data = try JSONEncoder().encode(control)
        #expect(try JSONDecoder().decode(MouseControl.self, from: data) == control)
        // Buttons are keys, so more can be added later.
        #expect(String(decoding: data, as: UTF8.self).contains(#""clicks":{"#))
    }

    // MARK: Clicks

    @Test mutating func aButtonWithoutActionsClicksAsUsual() {
        #expect(clicks.handle(.back, isDown: true, at: 0, actions: none) == (true, []))
        #expect(clicks.handle(.back, isDown: false, at: 0.1, actions: none) == (true, []))
        #expect(clicks.phase == .idle)
    }

    @Test mutating func aClickActionRunsOnThePressAndTheClickStaysOut() {
        #expect(clicks.handle(.middle, isDown: true, at: 0, actions: clickOnly) == (false, [.click(.middle)]))
        #expect(clicks.deadline == nil)
        #expect(clicks.handle(.middle, isDown: false, at: 0.1, actions: clickOnly) == (false, []))
        #expect(clicks.swallowing.isEmpty)
    }

    // MARK: Double clicks

    @Test mutating func aSingleClickIsSentOnOnceTheIntervalRunsOut() {
        #expect(clicks.handle(.back, isDown: true, at: 0, actions: doubleOnly) == (false, []))
        #expect(clicks.handle(.back, isDown: false, at: 0.08, actions: doubleOnly) == (false, []))
        #expect(clicks.deadline == 0.3)
        #expect(clicks.timeout(at: 0.2).isEmpty)
        #expect(clicks.timeout(at: 0.3) == [.replay(.back, released: true)])
        #expect(clicks.phase == .idle)
        #expect(clicks.deadline == nil)
    }

    @Test mutating func aSingleClickRunsItsActionOnceTheIntervalRunsOut() {
        _ = clicks.handle(.back, isDown: true, at: 0, actions: both)
        _ = clicks.handle(.back, isDown: false, at: 0.08, actions: both)
        #expect(clicks.timeout(at: 0.3) == [.click(.back)])
        #expect(clicks.swallowing.isEmpty)
    }

    @Test mutating func aDoubleClickRunsItsActionAndSendsNothing() {
        _ = clicks.handle(.forward, isDown: true, at: 0, actions: both)
        _ = clicks.handle(.forward, isDown: false, at: 0.08, actions: both)
        #expect(clicks.handle(.forward, isDown: true, at: 0.2, actions: both) == (false, [.doubleClick(.forward)]))
        #expect(clicks.deadline == nil)
        #expect(clicks.handle(.forward, isDown: false, at: 0.27, actions: both) == (false, []))
        #expect(clicks.phase == .idle)
        #expect(clicks.swallowing.isEmpty)
    }

    @Test mutating func aButtonHeldDownIsPressedOnceTheIntervalRunsOut() {
        _ = clicks.handle(.back, isDown: true, at: 0, actions: doubleOnly)
        #expect(clicks.timeout(at: 0.3) == [.replay(.back, released: false)])
        #expect(clicks.handle(.back, isDown: false, at: 1, actions: doubleOnly) == (true, []))
    }

    @Test mutating func aButtonHeldDownRunsItsClickActionAndHoldsTheRelease() {
        _ = clicks.handle(.back, isDown: true, at: 0, actions: both)
        #expect(clicks.timeout(at: 0.3) == [.click(.back)])
        #expect(clicks.handle(.back, isDown: false, at: 1, actions: both) == (false, []))
    }

    @Test mutating func anotherButtonSettlesTheHeldClickFirst() {
        _ = clicks.handle(.back, isDown: true, at: 0, actions: doubleOnly)
        _ = clicks.handle(.back, isDown: false, at: 0.05, actions: doubleOnly)
        #expect(clicks.handle(.forward, isDown: true, at: 0.1, actions: doubleOnly)
            == (false, [.replay(.back, released: true)]))
        #expect(clicks.phase == .pressed(.forward, since: 0.1, clickRuns: false))
    }

    @Test mutating func aLateSecondClickIsAClickOfItsOwn() {
        // The timer came late: the first click goes out, the second starts a new wait.
        _ = clicks.handle(.back, isDown: true, at: 0, actions: doubleOnly)
        _ = clicks.handle(.back, isDown: false, at: 0.05, actions: doubleOnly)
        #expect(clicks.handle(.back, isDown: true, at: 0.35, actions: doubleOnly)
            == (false, [.replay(.back, released: true)]))
        #expect(clicks.phase == .pressed(.back, since: 0.35, clickRuns: false))
    }

    @Test mutating func flushSettlesWhatIsHeld() {
        _ = clicks.handle(.forward, isDown: true, at: 0, actions: doubleOnly)
        #expect(clicks.flush() == [.replay(.forward, released: false)])
        #expect(clicks.flush().isEmpty)
    }
}
