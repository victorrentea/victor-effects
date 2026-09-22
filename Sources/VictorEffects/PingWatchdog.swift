import Foundation

/// Should the lost-ping watchdog stop the routed sound that is playing?
///
/// The watchdog exists for one failure: the tablet starts a long sound and then
/// dies (crash, Wi-Fi drop), leaving nothing in the room that can stop it. It
/// used to ask only "is the last `/ping` older than 12 s?" — which is also true
/// whenever the tablet is simply **not connected**, so every sound started from
/// the Mac itself (the right-⌘ panel, `/press/<n>`, a `/test/*` hook) was cut
/// at the next 5 s tick, a few seconds in. A sound nobody pinging ever started
/// has no client to lose.
///
/// The rule is therefore: stop only if a client **was alive when the sound
/// started** (a ping within `timeout` before the start, or any ping after it)
/// **and has gone quiet since** (no ping for `timeout`). `lastPing` only ever
/// moves forward, so "last ping ≥ start − timeout" is exactly "there was a
/// ping in that window, or later".
///
/// Pure: the clock is the caller's, so it tests without a timer or a wait.
enum PingWatchdog {
    static let timeout: TimeInterval = 12

    static func shouldStop(now: Date, lastPing: Date?, soundStartedAt: Date?) -> Bool {
        guard let lastPing, let start = soundStartedAt else { return false }
        let clientWentQuiet = now.timeIntervalSince(lastPing) > timeout
        let clientWasBehindTheSound = lastPing.timeIntervalSince(start) >= -timeout
        return clientWentQuiet && clientWasBehindTheSound
    }
}
