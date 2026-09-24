import CoreGraphics
import Foundation

/// Where a ☕ goes — pure geometry, no layers, so the flight can be reasoned
/// about (and tested) without a screen.
///
/// There is exactly ONE flight, and every cup rides it: straight **up** from
/// where it spawned, like smoke off a chimney, swaying gently side to side, and
/// fading as it nears the top edge. Nothing steers it — not the cursor (cups
/// used to bend over to the hand), not a flood (they used to sweep to the
/// middle of the screen), not being filled, not being mid-explosion. The mouse
/// decides what happens TO a cup, never where it goes.
enum CoffeeFlight {

    /// The chimney: `start` to the same x at `toY`, with a sine riding sideways.
    /// The sway ramps in over the first quarter of the climb (a cup leaves its
    /// spawn point cleanly) and then stays — it is smoke, not a pendulum coming
    /// to rest. `amplitude` is the half-width of the sway, `swings` how many
    /// full periods fit in the climb, `phase` the caller's randomness.
    static func chimney(from start: CGPoint, toY top: CGFloat,
                        amplitude: CGFloat, swings: CGFloat, phase: CGFloat = 0,
                        steps: Int = 48) -> [CGPoint] {
        let n = max(steps, 1)
        let dy = top - start.y
        return (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n)
            let rampIn = min(1, t * 4)
            let sway = amplitude * rampIn * sin(t * 2 * .pi * swings + phase)
            return CGPoint(x: start.x + sway, y: start.y + dy * t)
        }
    }

    /// How long the climb takes: constant *speed*, so a cup on a tall screen and
    /// one on a short screen read as the same smoke; clamped so neither extreme
    /// becomes silly. Slow on purpose — the pot needs time to reach a cup and
    /// pour, and a cup that shot past the hand would be the old lottery again.
    static func riseDuration(from y: CGFloat, toY top: CGFloat,
                             pointsPerSecond: CGFloat = 190,
                             range: ClosedRange<Double> = 3.5...7.0) -> Double {
        let d = abs(top - y)
        return min(max(Double(d / max(pointsPerSecond, 1)), range.lowerBound), range.upperBound)
    }

    /// The fraction of the climb after which a cup starts fading — "as it
    /// approaches the top edge", not from the moment it appears.
    static let fadeStartFraction: Double = 0.68

    /// Keep a point inside `bounds` with a margin.
    static func clamp(_ p: CGPoint, in bounds: CGRect, margin: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX + margin), bounds.maxX - margin),
                y: min(max(p.y, bounds.minY + margin), bounds.maxY - margin))
    }
}
