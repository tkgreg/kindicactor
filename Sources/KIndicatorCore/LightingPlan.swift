import Foundation

/// Decisions about the keyboard's RGB lighting, as pure functions: given what the keyboard
/// shows and what it should show, which requests get it there.
///
/// The saved lighting stays on the keyboard; a layer's lighting, or Off while the Mac's
/// displays sleep, is put on top without saving (`applied`), and so is the room's
/// `brightness`.
///
/// While its lights are off the keyboard reports the effect as Off, ignores colour and
/// brightness, and keeps the effect its light key turns back on (`keptEffect`).
package enum LightingPlan {
    /// What the keyboard shows: the saved lighting, or `applied` on top of it, at the room's
    /// `brightness` if it follows the room.
    package static func shown(saved: Lighting, applied: LayerLighting?, brightness: UInt8? = nil) -> Lighting {
        var shown = applied.map { overlay($0, on: saved) } ?? saved
        if let brightness { shown.brightness = brightness }
        return shown
    }

    /// The saved lighting, read from the keyboard while it shows no layer's lighting. While
    /// it shows the room's `brightness`, the saved brightness can't be read and stays as it was.
    package static func saved(keyboardShows now: Lighting, saved: Lighting?, brightness: UInt8?) -> Lighting {
        guard brightness != nil, let saved else { return now }
        var lighting = now
        lighting.brightness = saved.brightness
        return lighting
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

    /// Like `target`, but while the mic indicator shows, a layer's Solid Color is drawn key by
    /// key over the keyboard's own Per-key RGB (`fill`) instead, so the indicator's key shows
    /// on that layer too. Other effects have no colour per key, so they hide the indicator.
    package static func layerTarget(layerLighting: LayerLighting?, lightsOff: Bool, indicatorShows: Bool,
                                    applied: LayerLighting?, saved: Lighting?) -> (overlay: LayerLighting?, fill: KeyColor?) {
        if !lightsOff, indicatorShows, let layerLighting, layerLighting.effect == LightingEffect.solidColor,
           saved?.effect == LightingEffect.perKeyRGB {
            return (nil, KeyColor(hue: layerLighting.hue, saturation: layerLighting.saturation, value: 255))
        }
        return (target(layerLighting: layerLighting, lightsOff: lightsOff, applied: applied, saved: saved), nil)
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

    /// The keyboard keeps brightness in coarser steps than the 0...255 it reports and rounds
    /// down both ways, so the 40 it reported, written back, reads as 39. Writing one more
    /// than it reported gets its step back.
    package static func brightnessCorrection(wrote: UInt8, reads: UInt8) -> KeyboardRequest? {
        reads < wrote && wrote < 255 ? .setBrightness(wrote + 1) : nil
    }

    /// Going back from `applied` to the saved lighting.
    package struct Restore: Equatable, Sendable {
        /// The saved lighting to show (at the room's brightness, if it follows the room),
        /// with changes made on the keyboard meanwhile.
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
    ///
    /// While the brightness follows the room (`brightness`), the light keys' brightness
    /// isn't kept: the room's comes back.
    package static func restore(saved: Lighting, applied: LayerLighting, brightness: UInt8? = nil,
                                keyboardShows now: Lighting?) -> Restore {
        guard let now else {
            return Restore(lighting: saved, current: shown(saved: saved, applied: applied, brightness: brightness),
                           needsSave: false)
        }
        var lighting = saved
        if brightness == nil, abs(Int(now.brightness) - Int(saved.brightness)) > 2 {
            lighting.brightness = now.brightness
        }
        // Resending brightness loses a step to rounding, so a close one counts as sent.
        let shownBrightness = brightness ?? lighting.brightness
        let currentBrightness = abs(Int(now.brightness) - Int(shownBrightness)) > 2 ? now.brightness : shownBrightness
        lighting.speed = now.speed
        if now.effect != applied.effect {
            lighting.effect = now.effect
        }
        if (now.hue, now.saturation) != (applied.hue, applied.saturation) {
            lighting.hue = now.hue
            lighting.saturation = now.saturation
        }
        let current = Lighting(effect: now.effect, brightness: currentBrightness, speed: lighting.speed,
                               hue: now.hue, saturation: now.saturation)
        return Restore(lighting: lighting, current: current, needsSave: lighting != saved)
    }
}
