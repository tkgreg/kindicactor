import Foundation
import Testing
@testable import KIndicatorCore

struct KnobControlTests {
    /// As read from a V6 Ultra 8K: Mac layer Volume −, Volume +, Play/Pause; Fn layer lighting.
    let mac = KnobKeys(turnLeft: 0x00AA, turnRight: 0x00A9, press: 0x00AE)
    let fn = KnobKeys(turnLeft: 0x7828, turnRight: 0x7827, press: 0x7820)
    let ours = KnobControl.keys
    let knob = KnobLocation(press: KeyPosition(row: 0, col: 13))

    // MARK: Actions

    @Test func appActionsFallBackToAllApps() {
        let zoomIn = KeyAction.shortcut(Hotkey(keyCode: 0x18, modifiers: Hotkey.command, keyName: "="))
        let figma = KnobAppMapping(bundleID: "com.figma.Desktop", name: "Figma",
                                   mapping: KnobMapping(turnRight: zoomIn, press: .nothing))
        let control = KnobControl(enabled: true, apps: [figma])
        #expect(control.action(for: .turnRight, app: "com.figma.Desktop") == zoomIn)
        #expect(control.action(for: .press, app: "com.figma.Desktop") == .nothing)
        #expect(control.action(for: .turnLeft, app: "com.figma.Desktop") == .media(.volumeDown))
        #expect(control.action(for: .turnRight, app: "com.apple.Safari") == .media(.volumeUp))
        #expect(control.action(for: .press, app: nil) == .media(.mute))
        var empty = control
        empty.allApps = KnobMapping()
        #expect(empty.action(for: .turnLeft, app: nil) == .nothing)
    }

    @Test func titles() {
        #expect(KeyAction.media(.preciseVolumeUp).title == "Precise Volume +")
        #expect(KnobPreset.undo.mapping.turnRight?.title == "⇧⌘Z")
        #expect(KnobPreset.tabs.mapping.turnLeft?.title == "⌃⇧⇥")
        #expect(Hotkey(keyCode: 14, modifiers: Hotkey.command | Hotkey.option | Hotkey.control, keyName: "E").display == "⌃⌥⌘E")
    }

    @Test func keysPressedAsARealKeyboardSendsThem() {
        // Mission Control is stored as ⌃Fn↑ (com.apple.symbolichotkeys 32: 126, 0x840000).
        #expect(KeyAction.Shortcuts.missionControl.sendsFn && KeyAction.Shortcuts.missionControl.isArrow)
        #expect(KeyAction.Shortcuts.appWindows.sendsFn)
        #expect(Hotkey(keyCode: 105, keyName: "F13").sendsFn)
        #expect(!Hotkey(keyCode: 105, keyName: "F13").isArrow)
        #expect(!KeyAction.Shortcuts.back.sendsFn)
        #expect(!Hotkey(keyCode: 0x30, modifiers: Hotkey.control, keyName: "⇥").sendsFn)
    }

    @Test func preciseVolumeSpeedsUpWithTheKnob() {
        #expect(VolumeAcceleration.step(after: nil) == 0.01)
        #expect(VolumeAcceleration.step(after: 0.03) == 0.08)
        #expect(VolumeAcceleration.step(after: 0.04) == 0.04)
        #expect(VolumeAcceleration.step(after: 0.099) == 0.04)
        #expect(VolumeAcceleration.step(after: 0.15) == 0.02)
        #expect(VolumeAcceleration.step(after: 0.2) == 0.01)
        #expect([0.01, 0.02, 0.04, 0.08].map(VolumeAcceleration.quarterSteps) == [1, 1, 3, 5])
        #expect(KeyAction.media(.preciseVolumeUp).presses(after: 0.02) == 5)
        #expect(KeyAction.media(.preciseVolumeDown).presses(after: 0.05) == 3)
        #expect(KeyAction.media(.preciseVolumeUp).presses(after: nil) == 1)
        // Other actions press once per click, however fast.
        #expect(KeyAction.media(.volumeUp).presses(after: 0.02) == 1)
        #expect(KnobPreset.zoom.mapping.turnRight?.presses(after: 0.02) == 1)
    }

    @Test func settingsSurviveEncoding() throws {
        let control = KnobControl(enabled: true, layers: [0, 2], allApps: KnobPreset.zoom.mapping,
                                  apps: [KnobAppMapping(bundleID: "a.b", name: "B", mapping: KnobPreset.tracks.mapping)])
        let decoded = try JSONDecoder().decode(KnobControl.self, from: JSONEncoder().encode(control))
        #expect(decoded == control)
    }

    // MARK: Taking the knob

    @Test func takingTheKnobRemembersItsOwnKeys() {
        let plan = KnobTakeover.plan(now: [0: mac], layers: [0], originals: [:])
        #expect(plan.writes == [
            KnobWrite(layer: 0, input: .turnLeft, keycode: 0x6D),
            KnobWrite(layer: 0, input: .turnRight, keycode: 0x6E),
            KnobWrite(layer: 0, input: .press, keycode: 0x6F),
        ])
        #expect(plan.originals == [0: mac])
        #expect(plan.originalsAfterwards == [0: mac])
    }

    @Test func aTakenKnobNeedsNothing() {
        let plan = KnobTakeover.plan(now: [0: ours], layers: [0], originals: [0: mac])
        #expect(plan.writes.isEmpty)
        #expect(plan.originalsAfterwards == [0: mac])
    }

    @Test func aKeyChangedInLauncherBecomesTheKnobsOwn() {
        var changed = ours
        changed.press = 0x00A8
        let plan = KnobTakeover.plan(now: [0: changed], layers: [0], originals: [0: mac])
        #expect(plan.writes == [KnobWrite(layer: 0, input: .press, keycode: 0x6F)])
        var own = mac
        own.press = 0x00A8
        #expect(plan.originals == [0: own])
    }

    @Test func unknownOwnKeysAreTheStockOnes() {
        var half = ours
        half.turnLeft = 0x00AA
        let plan = KnobTakeover.plan(now: [0: half], layers: [0], originals: [:])
        #expect(plan.writes == [KnobWrite(layer: 0, input: .turnLeft, keycode: 0x6D)])
        #expect(plan.originals == [0: KnobTakeover.stockKeys])
    }

    // MARK: Giving it back

    @Test func turningOffGivesTheKnobItsKeysBack() {
        let plan = KnobTakeover.plan(now: [0: ours], layers: [], originals: [0: mac])
        #expect(plan.writes == [
            KnobWrite(layer: 0, input: .turnLeft, keycode: 0x00AA),
            KnobWrite(layer: 0, input: .turnRight, keycode: 0x00A9),
            KnobWrite(layer: 0, input: .press, keycode: 0x00AE),
        ])
        // Remembered until the writes went through.
        #expect(plan.originals == [0: mac])
        #expect(plan.originalsAfterwards.isEmpty)
    }

    @Test func givingBackKeepsKeysChangedInLauncher() {
        var changed = ours
        changed.turnRight = 0x00AB
        let plan = KnobTakeover.plan(now: [0: changed], layers: [], originals: [0: mac])
        #expect(plan.writes.map(\.input) == [.turnLeft, .press])
    }

    @Test func movingToAnotherLayer() {
        let plan = KnobTakeover.plan(now: [0: ours, 1: fn], layers: [1], originals: [0: mac])
        #expect(plan.writes.map(\.layer) == [0, 0, 0, 1, 1, 1])
        #expect(plan.originals == [0: mac, 1: fn])
        #expect(plan.originalsAfterwards == [1: fn])
    }

    @Test func layersToRead() {
        let on = KnobControl(enabled: true, layers: [0, 5])
        #expect(KnobTakeover.layersToRead(on, originals: [1: fn], layerCount: 4) == [0, 1])
        var off = on
        off.enabled = false
        #expect(KnobTakeover.layersToRead(off, originals: [1: fn], layerCount: 4) == [1])
        #expect(KnobTakeover.layersToRead(off, originals: [:], layerCount: 4) == [])
    }

    // MARK: Requests

    @Test func knobRequests() {
        #expect(knob.readRequests(layer: 1) == [
            .getEncoder(layer: 1, encoder: 0, clockwise: false),
            .getEncoder(layer: 1, encoder: 0, clockwise: true),
            .getKeycode(layer: 1, KeyPosition(row: 0, col: 13)),
        ])
        #expect(knob.request(KnobWrite(layer: 0, input: .turnRight, keycode: 0x6E))
            == .setEncoder(layer: 0, encoder: 0, clockwise: true, 0x6E))
        #expect(knob.request(KnobWrite(layer: 0, input: .press, keycode: 0x6F))
            == .setKeycode(layer: 0, KeyPosition(row: 0, col: 13), 0x6F))
        #expect(KnobLocation(layout: KeyboardLayout.v6Ultra8KANSI) == knob)
    }
}
