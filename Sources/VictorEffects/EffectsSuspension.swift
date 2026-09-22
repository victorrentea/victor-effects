import Foundation

/// A hold on every visual this app draws, for a short while.
///
/// Walkie Talkie drags a crop box out of the screen with the wheel held down,
/// and whatever is floating over the desktop at that moment — a rising ☕, a
/// storm, confetti — lands in the picture. The crop is the one capture in the
/// rig that takes seconds rather than a millisecond (he frames it while still
/// talking), so "it will be gone by the time the shutter fires" is not true
/// here: the room keeps tapping while he frames.
///
/// **A deadline, never a flag.** The caller that suspends is a *different
/// process*; it can be killed, redeployed or crash between the suspend and the
/// resume, and a boolean would leave this app silently deaf for the rest of the
/// day with nothing on screen to say why. The hold therefore expires by itself,
/// and `resume()` is only an optimisation that ends it sooner. `maxSeconds`
/// caps what a caller can ask for, for the same reason.
///
/// Pure value type: the clock is the caller's, so the whole thing tests without
/// a screen or a wait.
struct EffectsSuspension {
    /// The longest hold anyone may ask for. A crop drag is a couple of seconds;
    /// a minute is already an emergency.
    static let maxSeconds: TimeInterval = 60
    /// What `/effect/suspend` with no number means — comfortably longer than a
    /// crop drag, since the resume is what normally ends it.
    static let defaultSeconds: TimeInterval = 15

    private(set) var until: TimeInterval = -.infinity

    /// Hold every visual until `now + seconds` (clamped to `maxSeconds`).
    /// Extends an existing hold but never shortens one — two overlapping crops
    /// must not have the first one's resume cut the second one short.
    /// Returns the seconds actually granted.
    @discardableResult
    mutating func suspend(for seconds: TimeInterval, at now: TimeInterval) -> TimeInterval {
        let granted = min(max(seconds, 0), Self.maxSeconds)
        until = max(until, now + granted)
        return granted
    }

    /// End the hold now.
    mutating func resume() { until = -.infinity }

    func isSuspended(at now: TimeInterval) -> Bool { now < until }

    /// How much of the hold is left, 0 when it is over.
    func remaining(at now: TimeInterval) -> TimeInterval { max(0, until - now) }
}
