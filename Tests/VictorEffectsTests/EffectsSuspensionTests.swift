import XCTest
@testable import VictorEffects

final class EffectsSuspensionTests: XCTestCase {

    func testSuspendHoldsThenExpiresByItself() {
        var s = EffectsSuspension()
        XCTAssertFalse(s.isSuspended(at: 100))
        s.suspend(for: 5, at: 100)
        XCTAssertTrue(s.isSuspended(at: 104.9))
        XCTAssertFalse(s.isSuspended(at: 105))
        XCTAssertFalse(s.isSuspended(at: 100_000))
    }

    func testTheHoldExpiresEvenIfNobodyEverResumes() {
        // The point of the whole design: the process that suspends lives in
        // another app and can be killed between the suspend and the resume.
        var s = EffectsSuspension()
        s.suspend(for: EffectsSuspension.maxSeconds, at: 0)
        XCTAssertFalse(s.isSuspended(at: EffectsSuspension.maxSeconds + 0.001))
    }

    func testAskingForTooLongIsCapped() {
        var s = EffectsSuspension()
        XCTAssertEqual(s.suspend(for: 10_000, at: 0), EffectsSuspension.maxSeconds)
        XCTAssertFalse(s.isSuspended(at: EffectsSuspension.maxSeconds))
    }

    func testANegativeOrZeroRequestSuspendsNothing() {
        var s = EffectsSuspension()
        XCTAssertEqual(s.suspend(for: -5, at: 100), 0)
        XCTAssertFalse(s.isSuspended(at: 100))
    }

    func testASecondSuspendExtendsButNeverShortens() {
        // Two crops overlapping: the second one's shorter hold must not cut the
        // first one's short, and a longer one must win.
        var s = EffectsSuspension()
        s.suspend(for: 20, at: 0)
        s.suspend(for: 1, at: 0)
        XCTAssertTrue(s.isSuspended(at: 19))
        s.suspend(for: 30, at: 0)
        XCTAssertTrue(s.isSuspended(at: 29))
    }

    func testResumeEndsItAtOnce() {
        var s = EffectsSuspension()
        s.suspend(for: 30, at: 0)
        s.resume()
        XCTAssertFalse(s.isSuspended(at: 0))
        XCTAssertEqual(s.remaining(at: 0), 0)
    }

    func testRemainingCountsDown() {
        var s = EffectsSuspension()
        s.suspend(for: 10, at: 100)
        XCTAssertEqual(s.remaining(at: 103), 7, accuracy: 0.001)
        XCTAssertEqual(s.remaining(at: 200), 0)
    }

    // MARK: - What the gate lets through while held

    func testStopsAreAlwaysHeardThroughTheHold() {
        // A stop never draws; a hold that ate one could only leave something
        // up — the `/sound/stopped` of an effect that got in just before the
        // suspend would otherwise be lost to the very gate meant to keep the
        // screen clear.
        XCTAssertTrue(EffectsEngine.isStopWord("stop-all"))
        XCTAssertTrue(EffectsEngine.isStopWord("star-wars/stop"))
        XCTAssertTrue(EffectsEngine.isStopWord("progress-bar/stop"))
        XCTAssertFalse(EffectsEngine.isStopWord("star-wars"))
        XCTAssertFalse(EffectsEngine.isStopWord("stop"))
        XCTAssertFalse(EffectsEngine.isStopWord("coffee/storm"))
    }

    // MARK: - A fire delayed by Bluetooth compensation vs a stop in the gap

    func testADeferredFireIsOutvotedByAStopThatLandsWhileItWaits() {
        // Tablet: stop-all, /sound/play (arms 0.8 s of compensation),
        // /sound/pressed → the visual is queued. The next tile's stop-all —
        // or a crop's suspend — lands 0.3 s later. The queued visual must
        // then draw nothing: its stop is already spent.
        var fires = DeferredFires()
        let queuedAt = fires.generation
        XCTAssertTrue(fires.stillWanted(queuedAt))
        fires.stopped()
        XCTAssertFalse(fires.stillWanted(queuedAt))
    }

    func testAFireQueuedAfterTheStopStillDraws() {
        // The next tile's own visual is queued AFTER its pre-press stop-all,
        // so the stop that killed the previous fire must not kill this one.
        var fires = DeferredFires()
        fires.stopped()
        XCTAssertTrue(fires.stillWanted(fires.generation))
    }
}
