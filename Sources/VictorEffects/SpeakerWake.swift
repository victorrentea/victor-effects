import Foundation

/// 🔊 Whether a Bluetooth speaker still needs waking. The wake-up delay
/// (`docs/sound-routing.md`) is there for the FIRST sound: a speaker that played
/// a moment ago is already up, and making the next sound wait a second for it
/// only makes a tile answer late (Victor, 2026-11-05).
///
/// The answer is "how long until it is awake", not "awake or not", and that one
/// number serves every caller. Two tiles pressed 0.3 s apart: the second waits
/// the 0.75 s left of the first's wake, not nothing (it would play over the tone,
/// clipped, ahead of the first) and not the whole delay. A visual that reads it
/// just after starting its clip gets the same wait the clip got, whichever order
/// the two calls come in.
///
/// Times are plain seconds on one clock, so a test can pass its own.
struct SpeakerWake {
    /// How long after the last sound ended the speaker counts as awake:
    /// `speakerHotMs` in sound-timing.json, measured on the JBL Go 4
    /// (`docs/sound-routing.md`).
    var staysAwake: TimeInterval = 2

    private var awakeAt: TimeInterval = -.infinity
    private var silentAt: TimeInterval = -.infinity

    /// How long a sound started `now` must wait. `full` is the whole wake delay.
    func delay(full: TimeInterval, now: TimeInterval) -> TimeInterval {
        guard now < silentAt + staysAwake else { return full }
        return max(0, awakeAt - now)
    }

    /// A sound was started, and will be over in `endsIn` seconds. It wakes the
    /// speaker even if it did not wait for it: a click played on a sleeping
    /// speaker starts the same wake-up.
    mutating func soundStarted(endsIn: TimeInterval, full: TimeInterval, now: TimeInterval) {
        awakeAt = now + delay(full: full, now: now)
        silentAt = max(silentAt, now + endsIn)
    }

    /// Everything was cut short: the hot window counts from here, not from where the
    /// clip would have ended.
    mutating func silenced(now: TimeInterval) {
        silentAt = min(silentAt, now)
    }
}
