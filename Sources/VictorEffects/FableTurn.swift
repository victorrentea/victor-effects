import Foundation

/// ✨ Fable ⇄ Tyrael (2026-11-24): one key, two clips taking turns — Victor's
/// Gemini figure of light, then the archangel of Diablo II.
///
/// The turn is kept in `UserDefaults`, like the Santa hat's: the app restarts
/// several times an hour, and a turn kept in memory would make "every other
/// press" into "always Tyrael". A press while `tyrael.mov` is missing plays Fable
/// and does not use up Tyrael's turn.
enum FableTurn {
    private static let kTyraelNext = "Fable.tyraelNext"

    /// Whether this press is Tyrael's, given what was stored after the last one.
    /// Nothing stored means yes: the first press after he shipped shows him.
    static func isTyrael(stored: Bool?, tyraelPresent: Bool) -> Bool {
        tyraelPresent && (stored ?? true)
    }

    /// What to store for the next press after this one.
    static func next(stored: Bool?, tyraelPresent: Bool) -> Bool {
        tyraelPresent ? !(stored ?? true) : (stored ?? true)
    }

    /// This press's answer, flipping the stored one for the next.
    static func take(tyraelPresent: Bool) -> Bool {
        let d = UserDefaults.standard
        let stored = d.object(forKey: kTyraelNext) as? Bool
        d.set(next(stored: stored, tyraelPresent: tyraelPresent), forKey: kTyraelNext)
        return isTyrael(stored: stored, tyraelPresent: tyraelPresent)
    }
}
