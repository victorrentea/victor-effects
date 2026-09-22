import CoreGraphics
import Foundation

/// Where a ☕ goes — pure geometry, no layers, so the two flights a cup can take
/// can be reasoned about (and tested) without a screen.
///
/// Two flights, and the gauge in `CoffeeStormGauge` picks between them:
///
/// - **calm** (`approach`): every cup rides the *same lane* — up its spawn column,
///   then bending over to **wherever the cursor is**. They used to leave the
///   bottom-left each on its own random sideways drift, which made catching one
///   for the hold-charge a matter of guessing where it would wander; a cup that
///   comes to the hand is a gesture, a cup that scatters is a lottery. Sharing one
///   lane also means a trickle of cups queues along a single readable line instead
///   of fanning out over the projector.
/// - **storm** (`sweep` + `blastPoint`): past the threshold the cups stop coming
///   to the cursor — they would all ripen under it at once and take the break
///   apart a minute at a time — and sweep toward the **middle of the screen** on a
///   wave, detonating at scattered points around it.
enum CoffeeFlight {

    // MARK: - Calm: one lane, ending at the cursor

    /// The shared approach lane: a quadratic bézier whose control point sits
    /// directly **above the spawn point, at the target's height**. That one choice
    /// is what makes the shape the same for every cup no matter where the cursor
    /// is — it always climbs its own column first and only then leans across —
    /// while still landing exactly on the cursor.
    static func approach(from start: CGPoint, to target: CGPoint, steps: Int = 32) -> [CGPoint] {
        let control = CGPoint(x: start.x, y: target.y)
        return (0...max(steps, 1)).map { i in
            let t = CGFloat(i) / CGFloat(max(steps, 1))
            let u: CGFloat = 1 - t
            let a: CGFloat = u * u
            let b: CGFloat = 2 * u * t
            let c: CGFloat = t * t
            let x: CGFloat = a * start.x + b * control.x + c * target.x
            let y: CGFloat = a * start.y + b * control.y + c * target.y
            return CGPoint(x: x, y: y)
        }
    }

    /// How long the approach takes. Constant *speed*, not constant duration: a cup
    /// crossing the whole projector at the same pace as one born under the cursor
    /// is what keeps "the same trajectory" reading as one lane rather than as a
    /// dozen unrelated speeds. Clamped so neither extreme becomes silly.
    static func approachDuration(from start: CGPoint, to target: CGPoint,
                                 pointsPerSecond: CGFloat = 340,
                                 range: ClosedRange<Double> = 1.5...4.0) -> Double {
        let d = hypot(target.x - start.x, target.y - start.y)
        return min(max(Double(d / max(pointsPerSecond, 1)), range.lowerBound), range.upperBound)
    }

    // MARK: - Storm: a wave to the middle

    /// The storm sweep: the straight run from `start` to `target` with a sine
    /// riding **perpendicular** to it, so the wave is the same shape whichever way
    /// the cup is heading. The amplitude is tapered by `sin(πt)` — zero at both
    /// ends — so the cup leaves cleanly and arrives on its mark instead of being
    /// flung sideways at the instant it blows up.
    static func sweep(from start: CGPoint, to target: CGPoint,
                      amplitude: CGFloat, swings: CGFloat, phase: CGFloat = 0,
                      steps: Int = 48) -> [CGPoint] {
        let dx = target.x - start.x, dy = target.y - start.y
        let len = max(hypot(dx, dy), 1)
        let nx = -dy / len, ny = dx / len          // unit normal to the run
        return (0...max(steps, 1)).map { i in
            let t = CGFloat(i) / CGFloat(max(steps, 1))
            let wave = amplitude * sin(.pi * t) * sin(t * 2 * .pi * swings + phase)
            return CGPoint(x: start.x + dx * t + nx * wave,
                           y: start.y + dy * t + ny * wave)
        }
    }

    /// Where one storm cup detonates: a scattered point around the screen's middle.
    /// `angle` and `unitRadius` (0…1) are the caller's randomness, kept out of here
    /// so the geometry stays deterministic. The spread is elliptical — screens are
    /// wider than they are tall, and a circular scatter reads as a bullseye.
    static func blastPoint(center: CGPoint, spread: CGSize,
                           angle: CGFloat, unitRadius: CGFloat) -> CGPoint {
        let r = sqrt(min(max(unitRadius, 0), 1))   // sqrt → evenly filled, not centre-heavy
        return CGPoint(x: center.x + cos(angle) * spread.width * r,
                       y: center.y + sin(angle) * spread.height * r)
    }

    /// Keep a point inside `bounds` with a margin, so neither flight can park a cup
    /// half off the projector.
    static func clamp(_ p: CGPoint, in bounds: CGRect, margin: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX + margin), bounds.maxX - margin),
                y: min(max(p.y, bounds.minY + margin), bounds.maxY - margin))
    }
}
