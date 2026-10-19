import XCTest
@testable import VictorEffects

final class WhipPleasTests: XCTestCase {

    /// Every phrase comes up once per round, and no word ever follows itself —
    /// not even across the refill between two rounds.
    func testBagVisitsEveryPhraseAndNeverRepeatsBackToBack() {
        var bag = WhipPleas.Bag()
        let n = WhipPleas.phrases.count
        var previous: String?
        for _ in 0..<50 {
            let round = (0..<n).map { _ in bag.next() }
            XCTAssertEqual(Set(round), Set(WhipPleas.phrases))
            for word in round {
                XCTAssertNotEqual(word, previous)
                previous = word
            }
        }
    }

    func testClampKeepsTheWordOnTheGlass() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let offRight = CGRect(x: 1480, y: -20, width: 120, height: 40)
        let r = WhipPleas.clamp(offRight, into: screen)
        XCTAssertTrue(screen.contains(r))
        XCTAssertEqual(r.size, offRight.size)
        let inside = CGRect(x: 100, y: 100, width: 120, height: 40)
        XCTAssertEqual(WhipPleas.clamp(inside, into: screen), inside)
    }
}
