import Foundation

package enum ScrollAxis: Sendable {
    case vertical, horizontal
}

/// Smooth scrolling's motion: wheel notches in, whole pixels per frame out.
///
/// Each axis follows the distance the notches ask for through two lags in a row: a long one
/// that gives the glide its gentle tail, and a short one (a third as long) that eases each
/// notch in, so the first frame isn't the biggest jump. That's the shape of Mos's glide. Both
/// are solved exactly over each frame's real time, so a glide feels the same at 60 and 120 Hz
/// and through a dropped frame, where Mos's runs twice as fast on a 120 Hz screen. Fractions
/// of a pixel are carried to the next frame, so a glide covers exactly the distance asked.
package struct ScrollMotion: Equatable, Sendable {
    package struct Axis: Equatable, Sendable {
        /// How far each lag is from where the notches send the axis, in pixels (negative
        /// while short of it): `lead` follows the distance, `offset` (what's shown) follows
        /// `lead`.
        var lead = 0.0
        var offset = 0.0
        /// Pixels moved but not sent yet, less than one.
        var carry = 0.0

        var isMoving: Bool { lead != 0 || offset != 0 }
    }

    private struct Notch: Equatable, Sendable {
        var time: Double
        var axis: ScrollAxis
        var direction: Double
    }

    package private(set) var vertical = Axis()
    package private(set) var horizontal = Axis()
    private var last: Notch?
    /// Notches per second lately, while the wheel keeps turning one way.
    package private(set) var rate = 0.0

    /// The ease-in's time constant, as a share of the glide's (Mos: 64 of 188 ms).
    package static let easeShare = 0.34
    /// A glide is 95% done after this many of its time constants, with the ease-in.
    package static let ninetyFivePercent = 3.41
    /// A notch this soon after one the other way, in a fast spin, is the wheel bouncing.
    private static let bounce = 0.05
    /// Notches further apart start a new spin, without acceleration.
    private static let spinGap = 0.3

    package init() {}

    package var isMoving: Bool { vertical.isMoving || horizontal.isMoving }

    /// How far a notch goes while the wheel spins at `rate` notches per second: as far as a
    /// slow one up to 20 a second, a quick scroll, then up by `acceleration` for each 20 more,
    /// up to 1 + 3 × `acceleration` for a flick.
    package static func speedUp(rate: Double, acceleration: Double) -> Double {
        1 + acceleration * min(max((rate - 20) / 20, 0), 3)
    }

    /// Adds a notch of `lines` (±1 for a notched wheel, fractions for a high-resolution one)
    /// on `axis` at `time`, in seconds. `boost` multiplies it, for the faster key. A notch the
    /// other way stops what's left at once. Returns false for a bounce, which is ignored.
    @discardableResult
    package mutating func notch(_ axis: ScrollAxis, lines: Double, at time: Double, distance: Double,
                                acceleration: Double, boost: Double = 1) -> Bool {
        guard lines != 0 else { return true }
        let direction: Double = lines > 0 ? 1 : -1
        let interval = last.map { time - $0.time }
        let sameAxis = last?.axis == axis
        if let interval, sameAxis, last?.direction != direction, interval < Self.bounce, rate > 15 {
            return false
        }

        let whole = abs(lines) >= 1
        if whole {
            if let interval, sameAxis, last?.direction == direction, interval > 0, interval < Self.spinGap {
                rate += 0.5 * (1 / interval - rate)
            } else {
                rate = 0
            }
            last = Notch(time: time, axis: axis, direction: direction)
        }
        let speedUp = whole ? Self.speedUp(rate: rate, acceleration: acceleration) : 1
        let pixels = direction * distance * (whole ? 1 : abs(lines)) * speedUp * boost

        update(axis) { state in
            // Heading the other way: what's left of the glide stops at once.
            let heading = state.lead != state.offset ? state.lead - state.offset : -state.offset
            if heading * direction < 0 {
                state = Axis()
            }
            state.lead -= pixels
            state.offset -= pixels
        }
        return true
    }

    /// Moves `seconds` on, for a glide of `glide` seconds to 95%; the whole pixels to scroll.
    package mutating func advance(by seconds: Double, glide: Double) -> (horizontal: Int, vertical: Int) {
        let tail = max(glide, 0.01) / Self.ninetyFivePercent
        let dt = max(seconds, 0)
        var pixels = (horizontal: 0, vertical: 0)
        update(.horizontal) { pixels.horizontal = Self.advance(&$0, by: dt, tail: tail) }
        update(.vertical) { pixels.vertical = Self.advance(&$0, by: dt, tail: tail) }
        return pixels
    }

    /// Drops what's left, e.g. on a click or a trackpad touch.
    package mutating func stop() {
        vertical = Axis()
        horizontal = Axis()
        rate = 0
        last = nil
    }

    /// Everything left at once, e.g. when frames stopped coming.
    package mutating func finish() -> (horizontal: Int, vertical: Int) {
        let pixels = (horizontal: Int((horizontal.carry - horizontal.offset).rounded()),
                      vertical: Int((vertical.carry - vertical.offset).rounded()))
        vertical = Axis()
        horizontal = Axis()
        return pixels
    }

    private mutating func update(_ axis: ScrollAxis, _ change: (inout Axis) -> Void) {
        switch axis {
        case .vertical: change(&vertical)
        case .horizontal: change(&horizontal)
        }
    }

    /// `lead' = -lead / τ₁` and `offset' = (lead - offset) / τ₂`, solved for `dt`.
    private static func advance(_ state: inout Axis, by dt: Double, tail: Double) -> Int {
        guard state.isMoving else { return 0 }
        let ease = tail * easeShare
        let leadDecay = exp(-dt / tail)
        let easeDecay = exp(-dt / ease)
        let share = state.lead * tail / (tail - ease)
        var lead = state.lead * leadDecay
        var offset = (state.offset - share) * easeDecay + share * leadDecay
        // Close enough: arrive, and send the last fraction rounded.
        let settled = abs(offset) < 0.5 && abs(lead) < 0.5
        if settled {
            lead = 0
            offset = 0
        }
        state.carry += offset - state.offset
        state.lead = lead
        state.offset = offset
        let pixels = settled ? state.carry.rounded() : state.carry.rounded(.towardZero)
        state.carry = settled ? 0 : state.carry - pixels
        return Int(pixels)
    }
}
