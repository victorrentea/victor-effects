import XCTest
@testable import VictorEffects

/// ✨ Fable and Tyrael take turns on one key; a missing Tyrael never costs Fable a press.
final class FableTurnTests: XCTestCase {

    func testTheFirstPressShowsTyrael() {
        XCTAssertTrue(FableTurn.isTyrael(stored: nil, tyraelPresent: true))
    }

    func testTheyAlternate() {
        var stored: Bool? = nil
        var seen: [Bool] = []
        for _ in 0..<4 {
            seen.append(FableTurn.isTyrael(stored: stored, tyraelPresent: true))
            stored = FableTurn.next(stored: stored, tyraelPresent: true)
        }
        XCTAssertEqual(seen, [true, false, true, false])
    }

    func testWithoutHisClipEveryPressIsFableAndHisTurnWaits() {
        XCTAssertFalse(FableTurn.isTyrael(stored: true, tyraelPresent: false))
        XCTAssertEqual(FableTurn.next(stored: true, tyraelPresent: false), true)
        XCTAssertEqual(FableTurn.next(stored: nil, tyraelPresent: false), true)
    }
}
