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

    /// The whip thanks, it never apologises (2026-10-22).
    func testNoPhraseApologises() {
        let apologies = ["sorry", "pardon", "scuze", "entschuldig", "perdón", "scusa", "excuse"]
        for phrase in WhipPleas.phrases {
            for word in apologies {
                XCTAssertFalse(phrase.lowercased().contains(word), "\(phrase) apologises")
            }
        }
    }

    /// Every thank-you opens with its country's flag (2026-10-23), one
    /// glyph of two regional indicators, from a Schengen or euro country.
    func testEveryPhraseOpensWithAnAllowedFlag() {
        for phrase in WhipPleas.phrases {
            let (flag, iso, _) = WhipPleas.flagged(phrase)
            XCTAssertEqual(flag.unicodeScalars.count, 2, "\(phrase) has no flag")
            XCTAssertEqual(iso.count, 2, "\(phrase) has no flag")
            XCTAssertTrue(WhipPleas.allowedCountries.contains(iso), "\(phrase): \(iso) is neither Schengen nor euro")
        }
    }

    /// The ISO code is read off the flag itself — no second table to drift.
    func testFlaggedReadsTheIsoCodeOffTheFlag() {
        let (flag, iso, words) = WhipPleas.flagged("🇫🇷 merci beaucoup 💋")
        XCTAssertEqual(flag, "🇫🇷")
        XCTAssertEqual(iso, "FR")
        XCTAssertEqual(words, " merci beaucoup 💋")
    }

    /// The word lands past the tip, on the far side from the pointer.
    func testLaunchPointIsBeyondTheTipAwayFromTheHandle() {
        let handle = CGPoint(x: 100, y: 300), tip = CGPoint(x: 400, y: 300)
        let p = WhipPleas.launchPoint(handle: handle, tip: tip)
        XCTAssertEqual(p.x, 400 + WhipPleas.throwBeyondTip, accuracy: 0.001)
        XCTAssertEqual(p.y, 300, accuracy: 0.001)
        // Curled onto the handle: straight up (view coords are y-down).
        let curled = WhipPleas.launchPoint(handle: handle, tip: CGPoint(x: 105, y: 302))
        XCTAssertEqual(curled.y, 302 - WhipPleas.throwBeyondTip, accuracy: 0.001)
    }

    /// Swung west, the word goes west of the pointer, as far out as the tip
    /// was — even though the tip trails east of the handle at the lash.
    func testLaunchPointFollowsThePointersHeadingNotTheTrailingTip() {
        let handle = CGPoint(x: 500, y: 300), trailingTip = CGPoint(x: 700, y: 300)
        let p = WhipPleas.launchPoint(handle: handle, tip: trailingTip, heading: CGVector(dx: -80, dy: 0))
        XCTAssertEqual(p.x, 500 - 200 - WhipPleas.throwBeyondTip, accuracy: 0.001)
        XCTAssertEqual(p.y, 300, accuracy: 0.001)
        // Tip right on the pointer: still at least `minReach` out.
        let near = WhipPleas.launchPoint(handle: handle, tip: handle, heading: CGVector(dx: 0, dy: 40))
        XCTAssertEqual(near.y, 300 + WhipPleas.minReach + WhipPleas.throwBeyondTip, accuracy: 0.001)
        // A pointer that barely moved has no heading: the tip line decides.
        let still = WhipPleas.launchPoint(handle: handle, tip: trailingTip, heading: CGVector(dx: -5, dy: 0))
        XCTAssertEqual(still.x, 700 + WhipPleas.throwBeyondTip, accuracy: 0.001)
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
