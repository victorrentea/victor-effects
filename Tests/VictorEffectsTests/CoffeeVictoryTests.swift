import XCTest
@testable import VictorEffects

final class CoffeeVictoryTests: XCTestCase {
    func testOffUntilTheWatchIsWon() {
        var v = CoffeeVictory()
        v.arrival(at: 100)
        XCTAssertFalse(v.isOn(at: 100), "a ☕ alone is a vote, never a celebration")
    }

    func testOnForLingerAfterTheWin() {
        var v = CoffeeVictory()
        v.won(at: 100)
        XCTAssertTrue(v.isOn(at: 100))
        XCTAssertTrue(v.isOn(at: 110))
        XCTAssertFalse(v.isOn(at: 110.1))
    }

    func testEachArrivalWhileOnStretchesIt() {
        var v = CoffeeVictory()
        v.won(at: 100)
        v.arrival(at: 108)
        XCTAssertTrue(v.isOn(at: 117))
        XCTAssertFalse(v.isOn(at: 118.1))
    }

    func testAnArrivalAfterTheEndDoesNotRevive() {
        var v = CoffeeVictory()
        v.won(at: 100)
        v.arrival(at: 115)
        XCTAssertFalse(v.isOn(at: 115), "after the celebration a ☕ votes again")
    }
}
