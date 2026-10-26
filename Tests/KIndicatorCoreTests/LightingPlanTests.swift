import Testing
@testable import KIndicatorCore

struct LightingPlanTests {
    /// The user's saved lighting in the logs: Per-key RGB, brightness 80, speed 63.
    let perKey = Lighting(effect: 23, brightness: 80, speed: 63, hue: 21, saturation: 255)
    let greenSolid = LayerLighting(effect: 1, hue: 85, saturation: 255)

    @Test func layerLightingSendsColourThenEffect() {
        // Logged as "write Solid Color … over Per-key RGB …: 0455ff 0201".
        let target = LightingPlan.overlay(greenSolid, on: perKey)
        #expect(LightingPlan.requests(from: perKey, to: target, keptEffect: 23)
            == [.setColor(hue: 85, saturation: 255), .setEffect(1)])
        // And back: "0415ff 0217".
        #expect(LightingPlan.requests(from: target, to: perKey, keptEffect: 23)
            == [.setColor(hue: 21, saturation: 255), .setEffect(23)])
    }

    @Test func nothingToSendWhenEqual() {
        #expect(LightingPlan.requests(from: perKey, to: perKey, keptEffect: 23).isEmpty)
    }

    @Test func turningLightsOnSendsEffectFirst() {
        var off = perKey
        off.effect = 0
        off.hue = 0
        let requests = LightingPlan.requests(from: off, to: perKey, keptEffect: 23)
        #expect(requests == [.setEffect(23), .setColor(hue: 21, saturation: 255)])
    }

    @Test func turningLightsOffPutsKeptEffectBack() {
        // Off from a layer's Solid Color: the light key should bring back Per-key RGB.
        let solid = LightingPlan.overlay(greenSolid, on: perKey)
        var off = solid
        off.effect = 0
        #expect(LightingPlan.requests(from: solid, to: off, keptEffect: 23) == [.setEffect(23), .setEffect(0)])
        // Off from the kept effect itself: just off ("0200" in the logs).
        var perKeyOff = perKey
        perKeyOff.effect = 0
        #expect(LightingPlan.requests(from: perKey, to: perKeyOff, keptEffect: 23) == [.setEffect(0)])
    }

    @Test func lightsOffKeepsShownColour() {
        #expect(LightingPlan.lightsOff(applied: greenSolid, saved: perKey) == LayerLighting(effect: 0, hue: 85, saturation: 255))
        #expect(LightingPlan.lightsOff(applied: nil, saved: perKey) == LayerLighting(effect: 0, hue: 21, saturation: 255))
        #expect(LightingPlan.target(layerLighting: greenSolid, lightsOff: false, applied: nil, saved: perKey) == greenSolid)
        #expect(LightingPlan.target(layerLighting: greenSolid, lightsOff: true, applied: nil, saved: perKey)?.effect == 0)
        #expect(LightingPlan.target(layerLighting: nil, lightsOff: false, applied: greenSolid, saved: perKey) == nil)
    }

    @Test func restoreUndoesTheLayersLighting() {
        let shown = LightingPlan.overlay(greenSolid, on: perKey)
        let restore = LightingPlan.restore(saved: perKey, applied: greenSolid, keyboardShows: shown)
        #expect(restore.lighting == perKey)
        #expect(restore.current == shown)
        #expect(!restore.needsSave)
    }

    @Test func restoreKeepsChangesMadeOnTheKeyboard() {
        // Fn + light keys while the layer's lighting was on: brighter, and another effect.
        var changed = LightingPlan.overlay(greenSolid, on: perKey)
        changed.brightness = 160
        changed.effect = 2
        let restore = LightingPlan.restore(saved: perKey, applied: greenSolid, keyboardShows: changed)
        #expect(restore.lighting.brightness == 160)
        #expect(restore.lighting.effect == 2)
        #expect(restore.lighting.hue == 21)
        #expect(restore.needsSave)
    }

    @Test func restoreIgnoresBrightnessRounding() {
        var rounded = LightingPlan.overlay(greenSolid, on: perKey)
        rounded.brightness = 78
        #expect(LightingPlan.restore(saved: perKey, applied: greenSolid, keyboardShows: rounded).lighting.brightness == 80)
    }

    @Test func restoreAfterKeyboardRestartedNeedsNoSave() {
        // Off for the displays' sleep, and the keyboard restarted: it shows the saved lighting.
        let off = LightingPlan.lightsOff(applied: nil, saved: perKey)
        let restore = LightingPlan.restore(saved: perKey, applied: off, keyboardShows: perKey)
        #expect(restore.lighting == perKey)
        #expect(!restore.needsSave)
    }

    // MARK: Brightness following the room

    @Test func roomBrightnessIsShownOverEverything() {
        #expect(LightingPlan.shown(saved: perKey, applied: nil, brightness: 200).brightness == 200)
        let layered = LightingPlan.shown(saved: perKey, applied: greenSolid, brightness: 200)
        #expect(layered.brightness == 200)
        #expect(layered.effect == 1)
        // Changing it sends just the brightness.
        #expect(LightingPlan.requests(from: LightingPlan.shown(saved: perKey, applied: greenSolid, brightness: 200),
                                      to: LightingPlan.shown(saved: perKey, applied: greenSolid, brightness: 212),
                                      keptEffect: 23) == [.setBrightness(212)])
    }

    @Test func savedBrightnessIsntReadWhileTheRoomsShows() {
        var shown = perKey
        shown.brightness = 200
        shown.effect = 2
        let saved = LightingPlan.saved(keyboardShows: shown, saved: perKey, brightness: 200)
        #expect(saved.brightness == 80)
        #expect(saved.effect == 2)
        #expect(LightingPlan.saved(keyboardShows: shown, saved: perKey, brightness: nil) == shown)
        #expect(LightingPlan.saved(keyboardShows: shown, saved: nil, brightness: 200) == shown)
    }

    @Test func restoreKeepsTheRoomsBrightness() {
        let shown = LightingPlan.shown(saved: perKey, applied: greenSolid, brightness: 200)
        let restore = LightingPlan.restore(saved: perKey, applied: greenSolid, brightness: 200, keyboardShows: shown)
        #expect(restore.lighting == perKey)
        #expect(!restore.needsSave)
        // Nothing but the layer's lighting is undone.
        #expect(LightingPlan.requests(from: restore.current,
                                      to: LightingPlan.shown(saved: restore.lighting, applied: nil, brightness: 200),
                                      keptEffect: 23) == [.setColor(hue: 21, saturation: 255), .setEffect(23)])
    }

    @Test func restoreUndoesLightKeyBrightnessWhileFollowingTheRoom() {
        // Fn + brightness while the layer's lighting and the room's brightness showed.
        var changed = LightingPlan.shown(saved: perKey, applied: greenSolid, brightness: 200)
        changed.brightness = 120
        let restore = LightingPlan.restore(saved: perKey, applied: greenSolid, brightness: 200, keyboardShows: changed)
        #expect(restore.lighting.brightness == 80)
        #expect(!restore.needsSave)
        #expect(LightingPlan.requests(from: restore.current,
                                      to: LightingPlan.shown(saved: restore.lighting, applied: nil, brightness: 200),
                                      keptEffect: 23).contains(.setBrightness(200)))
    }

    @Test func savedBrightnessGetsItsStepBack() {
        // Seen on the V6 Ultra 8K: 40 written back over the room's brightness read as 39.
        #expect(LightingPlan.brightnessCorrection(wrote: 40, reads: 39) == .setBrightness(41))
        #expect(LightingPlan.brightnessCorrection(wrote: 40, reads: 40) == nil)
        #expect(LightingPlan.brightnessCorrection(wrote: 255, reads: 254) == nil)
    }

    @Test func restoreWithoutReadingTheKeyboard() {
        let restore = LightingPlan.restore(saved: perKey, applied: greenSolid, keyboardShows: nil)
        #expect(restore.lighting == perKey)
        #expect(restore.current == LightingPlan.overlay(greenSolid, on: perKey))
        #expect(!restore.needsSave)
    }
}
