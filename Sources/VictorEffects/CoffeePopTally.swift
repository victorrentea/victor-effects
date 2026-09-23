import CoreGraphics
import Foundation

/// Counts the ☕ that have actually **popped** (a completed hold-charge) and
/// answers two questions about them. Pure value type, fake clocks in the tests.
///
/// - **Critical mass** (`isCritical`): once `criticalCount` pops have landed
///   inside `criticalWindow`, the break is already settled — the first pop starts
///   the 10-min "UNTIL BREAK" watch and every later one takes a minute off it, so
///   by the seventh there is nothing left to decide. Past that point a caught cup
///   no longer charges: it turns into a **rocket** at the cursor and flies off to
///   burst somewhere around the middle of the screen, a firework instead of one
///   more minute. The window is a sliding one, so the state wears off on its own
///   ten minutes after the pops stop — no flag to forget to clear.
/// - **Escalation** (`violence`): more than `burstThreshold` explosions inside
///   one `burstWindow` and every NEXT one goes off bigger than the last. Rocket
///   bursts feed this too (`recordBurst`), but never the critical count — a
///   firework is not a minute.
struct CoffeePopTally {
    var criticalCount = 7
    var criticalWindow: TimeInterval = 600
    var burstThreshold = 3
    var burstWindow: TimeInterval = 1.0
    /// Violence added per explosion past the burst threshold, and its ceiling.
    var escalationStep: CGFloat = 0.6
    var maxViolence: CGFloat = 4.5

    private(set) var pops: [TimeInterval] = []
    private(set) var bursts: [TimeInterval] = []

    /// A hold-charge completed: counts toward critical mass AND the burst rate.
    mutating func recordPop(at now: TimeInterval) {
        pops.append(now)
        pops.removeAll { now - $0 > criticalWindow }
        recordBurst(at: now)
    }

    /// Any explosion (a pop or a rocket's burst): feeds only the burst rate.
    mutating func recordBurst(at now: TimeInterval) {
        bursts.append(now)
        bursts.removeAll { now - $0 > burstWindow }
    }

    func isCritical(at now: TimeInterval) -> Bool {
        pops.filter { now - $0 <= criticalWindow }.count >= criticalCount
    }

    /// How hard the explosion about to happen at `now` should go off, given
    /// `base` (1 for a calm pop). Counts the one about to happen: the fourth
    /// inside a second is the first to grow, the fifth grows more, and so on.
    func violence(at now: TimeInterval, base: CGFloat = 1) -> CGFloat {
        let recent = bursts.filter { now - $0 <= burstWindow }.count + 1
        let over = max(0, recent - burstThreshold)
        return min(maxViolence, base + escalationStep * CGFloat(over))
    }
}
