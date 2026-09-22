import CoreGraphics
import Foundation

/// Decides when a trickle of ☕ has become a **storm**: strictly more than
/// `threshold` arrivals inside the last `window` seconds. Pure value type, so
/// the decision can be tested with fake clocks and no screen.
///
/// Once tripped the storm **lingers** for `linger` seconds past the last
/// arrival that kept the rate up, and its `intensity` decays over that tail
/// instead of cutting out: a flood is bursty (participants tap in salvos), and
/// a screen that stops shaking between two salvos half a second apart would
/// read as a glitch, not as a lull.
struct CoffeeStormGauge {
    /// A storm is MORE than this many ☕ per `window`.
    var threshold: Int = 4
    var window: TimeInterval = 1.0
    /// How long after the rate drops the storm is still considered on.
    var linger: TimeInterval = 2.0

    private(set) var arrivals: [TimeInterval] = []
    /// The last instant at which the rate was measured above the threshold.
    private(set) var lastOverThreshold: TimeInterval = -.infinity
    /// ☕ that arrived since this storm began — the flood's SIZE, not just its
    /// rate, so a long salvo escalates instead of plateauing at the rate.
    private(set) var stormCount = 0
    /// At this many arrivals in one storm the escalation is maxed out.
    var escalationCount = 24

    /// Record one ☕ arriving at `now`. Answers whether the storm is on
    /// afterwards.
    @discardableResult
    mutating func record(at now: TimeInterval) -> Bool {
        let wasStorm = isStorm(at: now)
        arrivals.append(now)
        prune(at: now)
        if arrivals.count > threshold { lastOverThreshold = now }
        let storm = isStorm(at: now)
        if storm { stormCount = wasStorm ? stormCount + 1 : arrivals.count }
        return storm
    }

    /// ☕ per second over the trailing window, as of `now`.
    func rate(at now: TimeInterval) -> Double {
        let recent = arrivals.filter { now - $0 <= window }.count
        return Double(recent) / window
    }

    func isStorm(at now: TimeInterval) -> Bool {
        now - lastOverThreshold <= linger
    }

    /// 0 when calm, 1 at twice the threshold rate or beyond — OR once the storm
    /// has carried `escalationCount` cups, whichever is higher: the flood gets
    /// progressively bigger and more violent the longer it goes on. While the
    /// storm is lingering after the rate dropped it fades linearly to 0 across
    /// `linger`, with a floor of 0.3 so the tail still reads as a storm.
    func intensity(at now: TimeInterval) -> CGFloat {
        guard isStorm(at: now) else { return 0 }
        let over = rate(at: now) / Double(threshold) - 1          // 0 at threshold, 1 at 2×
        let escalation = Double(stormCount) / Double(escalationCount)
        let live = CGFloat(min(max(max(over, escalation), 0), 1))
        let tail = CGFloat(1 - min(max((now - lastOverThreshold) / linger, 0), 1))
        return max(live, 0.3 * tail)
    }

    private mutating func prune(at now: TimeInterval) {
        arrivals.removeAll { now - $0 > window }
        if !isStorm(at: now) { stormCount = 0 }
    }
}
