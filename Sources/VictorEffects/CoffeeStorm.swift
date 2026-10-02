import CoreGraphics
import Foundation

/// Decides when a trickle of ☕ has become a **salvo**: strictly more than
/// `threshold` arrivals inside the last `window` seconds. Pure value type, so
/// the decision can be tested with fake clocks and no screen.
///
/// Since 2026-10-02 a salvo arms nothing — only a won break does
/// (`CoffeeVictory`) — and the gauge only says how hard a victory burst goes
/// (`intensity`).
///
/// Once tripped the state **lingers** for `linger` seconds past the last
/// arrival that kept the rate up, and its `intensity` decays over that tail
/// instead of cutting out: a flood is bursty (participants tap in salvos), and
/// a mode that switched off between two salvos half a second apart would
/// explode one cup and fill the next.
struct CoffeeStormGauge {
    /// A salvo is MORE than this many ☕ per `window`.
    var threshold: Int = 3
    var window: TimeInterval = 1.0
    /// How long after the rate drops the salvo is still considered on.
    var linger: TimeInterval = 2.0

    private(set) var arrivals: [TimeInterval] = []
    /// The last instant at which the rate was measured above the threshold.
    private(set) var lastOverThreshold: TimeInterval = -.infinity
    /// ☕ that arrived since this salvo began — the flood's SIZE, not just its
    /// rate, so a long salvo escalates instead of plateauing at the rate.
    private(set) var stormCount = 0
    /// At this many arrivals in one salvo the escalation is maxed out.
    var escalationCount = 24

    /// Record one ☕ arriving at `now`. Answers whether the salvo is on
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

    /// 0 when calm, 1 at twice the threshold rate or beyond — OR once the salvo
    /// has carried `escalationCount` cups, whichever is higher: the flood gets
    /// progressively bigger and more violent the longer it goes on. While the
    /// state is lingering after the rate dropped it fades linearly to 0 across
    /// `linger`, with a floor of 0.3 so the tail still reads as a salvo.
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

/// How big a ☕ goes off when it pays out — Victor, 2026-09-25: "the explosion
/// is small, unless there's a flood of coffee cups". Pure, so the thresholds
/// are tested rather than eyeballed.
///
/// - **a won break** (`armed`, `CoffeeVictory`): the cup shook and bursts
///   big — `stormViolence` by the gauge's intensity, fragments thrown across
///   the screen, 22×22.
/// - **a crowd** — cups stacked up on screen. Each still fills and pops; the
///   pop grows from the quiet dissolve at `quietCups` or fewer to twice as
///   hard at `floodCups` or more.
///
/// One cup, or a few, is a small local pop: `pixelDissolve` at violence 1 —
/// the fragments travel about half the cup's width and fade where they are.
enum CoffeeBurst {
    struct Size: Equatable {
        /// `pixelDissolve`'s violence: 1 is the quiet dissolve.
        var violence: CGFloat
        /// Tiles per side.
        var grid: Int
    }

    /// At or below this many cups on screen a pop is the quiet one.
    static let quietCups = 3
    /// At or above this many (without a salvo) the calm pop is at its biggest.
    static let floodCups = 10
    static let calmViolence: ClosedRange<CGFloat> = 1.0...2.0
    static let calmGrid = 12
    static let stormViolence: ClosedRange<CGFloat> = 3.0...4.5
    static let stormGrid = 22

    /// `cupsOnScreen` counts the cup that is bursting.
    static func size(armed: Bool, intensity: CGFloat, cupsOnScreen: Int) -> Size {
        func lerp(_ r: ClosedRange<CGFloat>, _ k: CGFloat) -> CGFloat {
            r.lowerBound + (r.upperBound - r.lowerBound) * min(max(k, 0), 1)
        }
        if armed {
            return Size(violence: lerp(stormViolence, intensity), grid: stormGrid)
        }
        let crowd = CGFloat(cupsOnScreen - quietCups) / CGFloat(floodCups - quietCups)
        return Size(violence: lerp(calmViolence, crowd), grid: calmGrid)
    }
}

/// 🎆 The break the ☕ won: on from the moment the addons app reports that a
/// −1 took the UNTIL BREAK watch to zero, and kept on by every ☕ that still
/// arrives — each one owes the room its big burst — until `linger` seconds
/// pass with none. A deadline, never a flag: nothing has to remember to clear
/// it. Pure, so it is tested with fake clocks.
///
/// Off, a filled cup is a vote (pops small, pays −1). On, it is a celebration
/// (shakes, bursts big, fireworks, pays nothing).
struct CoffeeVictory {
    /// How long the celebration outlives the win, or the last ☕ after it.
    var linger: TimeInterval = 10
    private(set) var until: TimeInterval = -.infinity

    mutating func won(at now: TimeInterval) {
        until = max(until, now + linger)
    }

    /// A ☕ arriving while the celebration is on stretches it; one arriving
    /// after it ended is a fresh vote and changes nothing.
    mutating func arrival(at now: TimeInterval) {
        guard isOn(at: now) else { return }
        until = max(until, now + linger)
    }

    func isOn(at now: TimeInterval) -> Bool { now <= until }
}
