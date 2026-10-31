import XCTest
@testable import VictorEffects

final class CantTouchThisTests: XCTestCase {

    /// Lit on the beat, dark on the off-beat, for as long as it lives: a
    /// discrete on/off one beat long, repeating.
    func testTheBlinkIsLitOnTheBeatAndRepeats() {
        let blink = CantTouchThisSession.beatAnimation(beginTime: 42)
        XCTAssertEqual(blink.values as? [Float], [1, 0])
        XCTAssertEqual(blink.calculationMode, .discrete)
        XCTAssertEqual(blink.keyTimes?.count, 3, "discrete: one more key time than values")
        XCTAssertEqual(blink.duration, CantTouchThisSession.beatPeriod, accuracy: 1e-9)
        XCTAssertEqual(blink.repeatCount, .infinity)
        XCTAssertEqual(blink.beginTime, 42)
    }

    /// The epoch is a beat of the clip's grid, never in the future, so the
    /// blink starts at once and lands on the beats the room will hear.
    func testTheEpochIsABeatOfTheHeardClipAtOrBeforeNow() {
        let p = CantTouchThisSession.beatPeriod, b = CantTouchThisSession.firstBeat
        for heardIn in [0.0, 0.3, 0.8, 1.35, 2.0] {
            let now = 1_000.0
            let epoch = CantTouchThisSession.beatEpoch(clipHeardAt: now + heardIn, now: now)
            XCTAssertLessThanOrEqual(epoch, now)
            XCTAssertGreaterThan(epoch, now - p)
            let beatsFromFirst = (epoch - (now + heardIn + b)) / p
            XCTAssertEqual(beatsFromFirst, beatsFromFirst.rounded(), accuracy: 1e-9)
        }
    }

    /// A stamp blinks half as fast: lit one beat, dark the next.
    func testAStampBlinksOncePerTwoBeats() {
        let blink = CantTouchThisSession.beatAnimation(beginTime: 42,
                                                       beats: CantTouchThisSession.stampBeatsPerBlink)
        XCTAssertEqual(CantTouchThisSession.stampBeatsPerBlink, 2)
        XCTAssertEqual(blink.duration, 2 * CantTouchThisSession.beatPeriod, accuracy: 1e-9)
        XCTAssertEqual(blink.keyTimes?[1].doubleValue, 0.5, "lit for exactly one beat")
    }

    /// The stamps' epoch is a HEAVY beat (odd: 1, 3, 5 …), never in the future.
    func testTheStampEpochIsAHeavyBeat() {
        let p = CantTouchThisSession.beatPeriod, b = CantTouchThisSession.firstBeat
        let period = p * Double(CantTouchThisSession.stampBeatsPerBlink)
        for heardIn in [0.0, 0.3, 0.8, 1.35, 2.0] {
            let now = 1_000.0
            let epoch = CantTouchThisSession.beatEpoch(clipHeardAt: now + heardIn, now: now,
                                                       firstBeat: CantTouchThisSession.stampFirstBeat,
                                                       period: period)
            XCTAssertLessThanOrEqual(epoch, now)
            XCTAssertGreaterThan(epoch, now - period)
            let beat = ((epoch - (now + heardIn + b)) / p).rounded()
            XCTAssertEqual((epoch - (now + heardIn + b)) / p, beat, accuracy: 1e-9)
            XCTAssertEqual(abs(Int(beat)) % 2, 1, "heardIn \(heardIn): lit on an even (light) beat")
        }
    }

    /// 133 BPM is the song; a grid far off it means someone typed a wrong number.
    func testTheGridIsHammersTempo() {
        XCTAssertEqual(60 / CantTouchThisSession.beatPeriod, 133, accuracy: 1)
    }

    func testTheStopHandShipsWithTheApp() {
        XCTAssertNotNil(EffectsResources.url("stop-hand", "png"))
    }

    func testTile35FiresItAndItsStopPutsItAway() {
        XCTAssertEqual(SoundEffectMap.onPress["35_cant_touch_this.mp3"], "cant-touch-this")
        XCTAssertEqual(SoundEffectMap.onStop["35_cant_touch_this.mp3"], "cant-touch-this/stop")
    }
}
