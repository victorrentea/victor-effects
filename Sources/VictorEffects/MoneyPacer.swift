import Foundation

/// 💸 Tile #53's rhythm: every press is heard as one "ching", but never closer
/// than `minGap` to the previous one (Victor, 2026-11-20: hammering the tile
/// sounded clunky, the chings smeared into each other). A press that comes too
/// soon is not dropped: it takes the next free slot, so four quick taps are
/// still four chings, evenly spaced. Only a press that would have to wait
/// longer than `maxWait` is dropped, so a frantic tablet never leaves a tail of
/// chings ringing on after the hand has stopped.
///
/// `minGap` and the duck in `SoundManager.layeredDuck` were measured together
/// on the ching itself (peak −0.27 dBFS): six copies stacked 0.25 s apart at
/// full level peak at **+2.9 dBFS** (clipping, the "doesn't sound right"); with
/// every older copy stepping down to 40% when a newer one strikes they peak at
/// −0.11 dBFS. At 0.15–0.2 s apart even the ducked stack goes over 0 dBFS.
struct MoneyPacer {
    static let minGap: TimeInterval = 0.25
    /// Two chings queued at most behind the one sounding.
    static let maxWait: TimeInterval = 2 * minGap

    private(set) var lastSlot: TimeInterval = -.infinity

    /// The delay (seconds from `now`) at which this press's ching strikes,
    /// or nil when the queue is full and the press is dropped.
    mutating func slot(at now: TimeInterval) -> TimeInterval? {
        let at = max(now, lastSlot + Self.minGap)
        guard at - now <= Self.maxWait + 0.000_1 else { return nil }
        lastSlot = at
        return at - now
    }

    /// How many players a clip of `clip` seconds needs so that, struck every
    /// `minGap`, a copy is never restarted while it still rings.
    static func poolSize(clip: TimeInterval) -> Int {
        max(2, min(12, Int((clip / minGap).rounded(.up)) + 1))
    }
}
