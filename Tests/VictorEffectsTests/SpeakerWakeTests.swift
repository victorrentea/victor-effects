import XCTest
@testable import VictorEffects

/// Only the first sound on a Bluetooth speaker waits for it to wake
/// (`docs/sound-routing.md`).
final class SpeakerWakeTests: XCTestCase {
    private let full = 1.05

    func testASleepingSpeakerGetsTheWholeDelay() {
        XCTAssertEqual(SpeakerWake().delay(full: full, now: 100), full)
    }

    func testASoundFiveSecondsAfterTheLastOneEndedWaitsNoLonger() {
        var wake = SpeakerWake()
        wake.soundStarted(endsIn: full + 3, full: full, now: 100)
        XCTAssertEqual(wake.delay(full: full, now: 100 + full + 3 + 4.9), 0)
    }

    func testPastFiveSecondsTheSpeakerIsAsleepAgain() {
        var wake = SpeakerWake()
        wake.soundStarted(endsIn: full + 3, full: full, now: 100)
        XCTAssertEqual(wake.delay(full: full, now: 100 + full + 3 + 5.1), full)
    }

    func testASecondPressDuringTheWakeWaitsOnlyForWhatIsLeft() {
        var wake = SpeakerWake()
        wake.soundStarted(endsIn: full + 3, full: full, now: 100)
        XCTAssertEqual(wake.delay(full: full, now: 100.3), 0.75, accuracy: 0.001)
    }

    func testReadJustAfterItsOwnStartAClipStillSeesItsOwnWait() {
        var wake = SpeakerWake()
        let delay = wake.delay(full: full, now: 100)
        wake.soundStarted(endsIn: delay + 3, full: full, now: 100)
        XCTAssertEqual(wake.delay(full: full, now: 100), delay, accuracy: 0.001)
    }

    func testAClickOnASleepingSpeakerDoesNotMakeItAwakeOnTheSpot() {
        var wake = SpeakerWake()
        wake.soundStarted(endsIn: 0.05, full: full, now: 100)
        XCTAssertEqual(wake.delay(full: full, now: 100.1), full - 0.1, accuracy: 0.001)
    }

    func testAStopCountsFromTheStopNotFromWhereTheClipWouldHaveEnded() {
        var wake = SpeakerWake()
        wake.soundStarted(endsIn: 60, full: full, now: 100)
        wake.silenced(now: 102)
        XCTAssertEqual(wake.delay(full: full, now: 106), 0)
        XCTAssertEqual(wake.delay(full: full, now: 108), full)
    }

    func testALoopStaysAwakeUntilStopped() {
        var wake = SpeakerWake()
        wake.soundStarted(endsIn: .infinity, full: full, now: 100)
        XCTAssertEqual(wake.delay(full: full, now: 10_000), 0)
        wake.silenced(now: 10_000)
        XCTAssertEqual(wake.delay(full: full, now: 10_006), full)
    }

    func testAShortClipDoesNotShortenTheLongOneStillPlaying() {
        var wake = SpeakerWake()
        wake.soundStarted(endsIn: 60, full: full, now: 100)
        wake.soundStarted(endsIn: 1, full: full, now: 110)
        XCTAssertEqual(wake.delay(full: full, now: 150), 0)
    }
}
