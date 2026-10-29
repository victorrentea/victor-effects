import XCTest
@testable import VictorEffects

final class CantTouchThisTests: XCTestCase {

    /// Three blinks, each a clean dark-then-lit, ending lit: a sign that ends
    /// its blink dark would vanish from the desktop it was stamped on.
    func testTheBlinkIsThreeDarkFlashesEndingLit() {
        let blink = CantTouchThisSession.blinkAnimation()
        let values = blink.values as? [Float]
        XCTAssertEqual(values, [0, 1, 0, 1, 0, 1])
        XCTAssertEqual(blink.calculationMode, .discrete)
        XCTAssertEqual(blink.keyTimes?.count, values?.count)
        XCTAssertEqual(blink.duration, 6 * CantTouchThisSession.blinkHalfPeriod, accuracy: 1e-9)
        XCTAssertLessThan(blink.duration, 1.0, "three blinks answer a click, they don't hold it up")
    }

    func testTheStopHandShipsWithTheApp() {
        XCTAssertNotNil(EffectsResources.url("stop-hand", "png"))
    }

    func testTile35FiresItAndItsStopPutsItAway() {
        XCTAssertEqual(SoundEffectMap.onPress["35_cant_touch_this.mp3"], "cant-touch-this")
        XCTAssertEqual(SoundEffectMap.onStop["35_cant_touch_this.mp3"], "cant-touch-this/stop")
    }
}
