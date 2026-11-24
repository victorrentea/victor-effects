import Foundation

/// ✨ Fable ⇄ 😇 Inarius (2026-11-24): one key, two clips taking turns — Victor's
/// Gemini figure of light coming down, then his Gemini angel slowing to a stop,
/// wings open.
///
/// The turn is kept in `UserDefaults`, like the Santa hat's: the app restarts
/// several times an hour, and a turn kept in memory would make "every other
/// press" into "always the same one". A press while `inarius.mov` is missing
/// plays Fable and does not use up Inarius's turn.
enum FableTurn {
    private static let kOtherNext = "Fable.inariusNext"

    /// Whether this press is the other clip's, given what was stored after the
    /// last one. Nothing stored means yes: the first press after he shipped shows him.
    static func isOther(stored: Bool?, otherPresent: Bool) -> Bool {
        otherPresent && (stored ?? true)
    }

    /// What to store for the next press after this one.
    static func next(stored: Bool?, otherPresent: Bool) -> Bool {
        otherPresent ? !(stored ?? true) : (stored ?? true)
    }

    /// This press's answer, flipping the stored one for the next.
    static func take(otherPresent: Bool) -> Bool {
        let d = UserDefaults.standard
        let stored = d.object(forKey: kOtherNext) as? Bool
        d.set(next(stored: stored, otherPresent: otherPresent), forKey: kOtherNext)
        return isOther(stored: stored, otherPresent: otherPresent)
    }
}
