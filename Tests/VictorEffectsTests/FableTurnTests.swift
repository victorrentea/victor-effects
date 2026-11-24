import XCTest
@testable import VictorEffects

/// ✨ Fable and 😇 Inarius take turns on one key; a missing Inarius never costs Fable a press.
final class FableTurnTests: XCTestCase {

    func testTheFirstPressShowsInarius() {
        XCTAssertTrue(FableTurn.isOther(stored: nil, otherPresent: true))
    }

    func testTheyAlternate() {
        var stored: Bool? = nil
        var seen: [Bool] = []
        for _ in 0..<4 {
            seen.append(FableTurn.isOther(stored: stored, otherPresent: true))
            stored = FableTurn.next(stored: stored, otherPresent: true)
        }
        XCTAssertEqual(seen, [true, false, true, false])
    }

    func testWithoutHisClipEveryPressIsFableAndHisTurnWaits() {
        XCTAssertFalse(FableTurn.isOther(stored: true, otherPresent: false))
        XCTAssertEqual(FableTurn.next(stored: true, otherPresent: false), true)
        XCTAssertEqual(FableTurn.next(stored: nil, otherPresent: false), true)
    }
}
