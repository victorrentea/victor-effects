import XCTest
@testable import VictorEffects

final class PingWatchdogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testATabletThatDiesMidSoundGetsItsSoundStopped() {
        // pinging every few seconds, starts a sound at 100, last ping at 103, dead
        XCTAssertFalse(PingWatchdog.shouldStop(now: at(110), lastPing: at(103), soundStartedAt: at(100)))
        XCTAssertTrue(PingWatchdog.shouldStop(now: at(116), lastPing: at(103), soundStartedAt: at(100)))
    }

    func testAPanelPressWithNoTabletConnectedIsNeverCut() {
        // The bug: the last ping is hours old, the sound was started on the Mac.
        XCTAssertFalse(PingWatchdog.shouldStop(now: at(10_005), lastPing: at(100), soundStartedAt: at(10_000)))
        XCTAssertFalse(PingWatchdog.shouldStop(now: at(10_030), lastPing: at(100), soundStartedAt: at(10_000)))
    }

    func testNoPingEverMeansNothingToLose() {
        XCTAssertFalse(PingWatchdog.shouldStop(now: at(50), lastPing: nil, soundStartedAt: at(10)))
    }

    func testALiveTabletNeverStopsAPanelSound() {
        XCTAssertFalse(PingWatchdog.shouldStop(now: at(130), lastPing: at(128), soundStartedAt: at(100)))
    }

    func testAPingJustInsideTheWindowBeforeTheStartCounts() {
        // ping at 88, sound at 100: the client was alive 12 s before the start
        XCTAssertTrue(PingWatchdog.shouldStop(now: at(101), lastPing: at(88), soundStartedAt: at(100)))
        // ping at 87.9: already stale when the sound started — not its client
        XCTAssertFalse(PingWatchdog.shouldStop(now: at(101), lastPing: at(87.9), soundStartedAt: at(100)))
    }

    func testNoSoundStartKnownMeansNoStop() {
        XCTAssertFalse(PingWatchdog.shouldStop(now: at(100), lastPing: at(10), soundStartedAt: nil))
    }
}
