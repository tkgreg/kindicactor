import Foundation

/// Decisions about the keyboard's RGB lighting, as pure functions: given what the keyboard
/// shows and what it should show, which requests get it there.
///
/// The saved lighting stays on the keyboard; a layer's lighting, or Off while the Mac's
/// displays sleep, is put on top without saving (`applied`).
///
/// While its lights are off the keyboard reports the effect as Off, ignores colour and
/// brightness, and keeps the effect its light key turns back on (`keptEffect`).
package enum LightingPlan {
    /// What the keyboard shows: the saved lighting, or `applied` on top of it.
    package static func shown(saved: Lighting, applied: LayerLighting?) -> Lighting {
        applied.map { overlay($0, on: saved) } ?? saved
    }

    /// A layer's lighting on top of the saved one; brightness and speed stay as saved.
    package static func overlay(_ layer: LayerLighting, on saved: Lighting) -> Lighting {
        Lighting(effect: layer.effect, brightness: saved.brightness, speed: saved.speed,
                 hue: layer.hue, saturation: layer.saturation)
    }

    /// What goes on top of the saved lighting: Off while `lightsOff`, else the layer's own
    /// lighting, if it has one.
    package static func target(layerLighting: LayerLighting?, lightsOff: Bool,
                               applied: LayerLighting?, saved: Lighting?) -> LayerLighting? {
        lightsOff ? self.lightsOff(applied: applied, saved: saved) : layerLighting
    }

    /// Off, in the colour the keyboard shows, so only the effect changes.
    package static func lightsOff(applied: LayerLighting?, saved: Lighting?) -> LayerLighting {
        let color = applied.map { ($0.hue, $0.saturation) } ?? saved.map { ($0.hue, $0.saturation) } ?? (0, 255)
        return LayerLighting(effect: LightingEffect.off, hue: color.0, saturation: color.1)
    }

    /// The requests that take the keyboard from `current` to `target`. Only values that
    /// differ are sent: setting the effect is slow (60–100 ms) and resending brightness
    /// loses a step to rounding each time. The effect goes last so the new effect starts
    /// in the new colour, except when the lights are off.
    package static func requests(from current: Lighting, to target: Lighting, keptEffect: UInt8?) -> [KeyboardRequest] {
        var requests: [KeyboardRequest] = []
        var effect = current.effect
        if effect == LightingEffect.off, target.effect != LightingEffect.off {
            // Colour and brightness sent while off are ignored.
            requests.append(.setEffect(target.effect))
            effect = target.effect
        } else if target.effect == LightingEffect.off, effect != LightingEffect.off, let keptEffect, keptEffect != effect {
            // Otherwise the light key would turn back on with the layer's effect.
            requests.append(.setEffect(keptEffect))
            effect = keptEffect
        }
        if (target.hue, target.saturation) != (current.hue, current.saturation) {
            requests.append(.setColor(hue: target.hue, saturation: target.saturation))
        }
        if target.brightness != current.brightness {
            requests.append(.setBrightness(target.brightness))
        }
        if target.speed != current.speed {
            requests.append(.setSpeed(target.speed))
        }
        if target.effect != effect {
            requests.append(.setEffect(target.effect))
        }
        return requests
    }

    /// Going back from `applied` to the saved lighting.
    package struct Restore: Equatable, Sendable {
        /// The saved lighting to show, with changes made on the keyboard meanwhile.
        package var lighting: Lighting
        /// What the keyboard shows now, to write `lighting` over.
        package var current: Lighting
        /// Changes made on the keyboard are kept by saving them.
        package var needsSave: Bool
    }

    /// Light keys pressed while `applied` was shown (Fn + light keys) changed the keyboard;
    /// those changes are kept and saved instead of undone. `keyboardShows` is nil when the
    /// keyboard couldn't be read. A keyboard that restarted shows the saved lighting again,
    /// so there's nothing new to save.
    package static func restore(saved: Lighting, applied: LayerLighting, keyboardShows now: Lighting?) -> Restore {
        guard let now else {
            return Restore(lighting: saved, current: overlay(applied, on: saved), needsSave: false)
        }
        var lighting = saved
        if abs(Int(now.brightness) - Int(saved.brightness)) > 2 {
            lighting.brightness = now.brightness
        }
        lighting.speed = now.speed
        if now.effect != applied.effect {
            lighting.effect = now.effect
        }
        if (now.hue, now.saturation) != (applied.hue, applied.saturation) {
            lighting.hue = now.hue
            lighting.saturation = now.saturation
        }
        let current = Lighting(effect: now.effect, brightness: lighting.brightness, speed: lighting.speed,
                               hue: now.hue, saturation: now.saturation)
        return Restore(lighting: lighting, current: current, needsSave: lighting != saved)
    }
}
