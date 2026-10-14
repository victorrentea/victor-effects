import Foundation

/// 🎆 The ring that reveals a drawn firework burst: where its outer edge (the
/// heads of the lines, flying out) and its inner edge (the tails, catching up)
/// are at each moment, as the four `locations` of a radial gradient mask —
/// clear, white, white, clear.
///
/// Timed like the per-line `strokeEnd`/`strokeStart` it replaces: the heads
/// reach full length at 35 % of the burst, easing out; the tails start at 40 %
/// of that and ease in until they meet the heads at the end.
enum FireworkReveal {
    static let drawFraction = 0.35
    static let tailStart = drawFraction * 0.4
    /// How soft each edge is, as a fraction of the mask's radius: a crisp head,
    /// a tail that thins out rather than being cut.
    static let softHead = 0.015
    static let softTail = 0.06

    /// The heads' distance at `t` (0…1 of the burst), as a fraction of the reach.
    static func head(_ t: Double) -> Double { easeOut(min(max(t / drawFraction, 0), 1)) }

    /// The tails' distance at `t`, as a fraction of the reach.
    static func tail(_ t: Double) -> Double {
        t <= tailStart ? 0 : easeIn(min((t - tailStart) / (1 - tailStart), 1))
    }

    /// The gradient stops at `t`. `reach` is the longest line over the mask's
    /// radius (< 1, so the ring is clear before the picture's edge).
    static func locations(at t: Double, reach: Double) -> [NSNumber] {
        let outer = head(t) * reach
        let inner = min(tail(t) * reach, outer)
        let stops = [max(0, inner - softTail), inner, outer, min(1, outer + softHead)]
        return stops.map { NSNumber(value: $0) }
    }

    // Close to Core Animation's .easeOut / .easeIn curves (0,0,.58,1 / .42,0,1,1).
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 1.9) }
    static func easeIn(_ x: Double) -> Double { pow(x, 1.9) }
}
