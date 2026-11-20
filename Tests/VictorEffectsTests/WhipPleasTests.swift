import XCTest
@testable import VictorEffects

final class WhipPleasTests: XCTestCase {

    /// Every phrase comes up once per round, and no word ever follows itself —
    /// not even across the refill between two rounds.
    func testBagVisitsEveryPhraseAndNeverRepeatsBackToBack() {
        var bag = WhipPleas.Bag(here: { nil })
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

    /// In Sweden every third crack is Swedish, the first one included — a
    /// count, not a probability (2026-11-20) — the rest are everyone else's,
    /// and still no word follows itself.
    func testEveryThirdCrackIsInTodaysLanguage() {
        var bag = WhipPleas.Bag(here: { "SE" })
        let draws = (0..<6000).map { _ in bag.next() }
        let swedish = draws.filter { WhipPleas.flagged($0).iso == "SE" }
        for (i, word) in draws.enumerated() {
            XCTAssertEqual(WhipPleas.flagged(word).iso == "SE", i % 3 == 0, "crack #\(i + 1): \(word)")
        }
        XCTAssertEqual(Set(swedish), ["snälla 🇸🇪", "var så snäll 🇸🇪"])
        XCTAssertEqual(Set(draws), Set(WhipPleas.phrases))
        for (a, b) in zip(draws, draws.dropFirst()) { XCTAssertNotEqual(a, b) }
    }

    /// Every country of the room has at least two pleas (2026-11-18), so its
    /// local third can alternate instead of going quiet after one word.
    func testEveryRoomCountryHasAtLeastTwoPleas() {
        for iso in ["NL", "FR", "SE", "DE", "IT", "RS", "ES", "PT", "HU", "PL", "RO"] {
            let count = WhipPleas.phrases.filter { WhipPleas.flagged($0).iso == iso }.count
            XCTAssertGreaterThanOrEqual(count, 2, "\(iso) has \(count) plea(s)")
        }
    }

    /// A country picked by hand in addons today (a remote group abroad) beats
    /// the Mac's own timezone; yesterday's pick does not.
    func testTodaysManualPickInAddonsBeatsTheMacsZone() throws {
        let suite = "whip-test-\(UUID().uuidString)"
        let addons = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { addons.removePersistentDomain(forName: suite) }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let now = Date()
        addons.set("Europe/Warsaw", forKey: "BreakTimer.country.tz")
        addons.set(day.string(from: now), forKey: "BreakTimer.country.day")
        XCTAssertEqual(WhipPleas.hereISO(addons: addons, now: now, macZone: "Europe/Bucharest"), "PL")
        addons.set(day.string(from: now.addingTimeInterval(-86_400)), forKey: "BreakTimer.country.day")
        XCTAssertEqual(WhipPleas.hereISO(addons: addons, now: now, macZone: "Europe/Bucharest"), "RO")
    }

    func testStockholmIsSweden() {
        XCTAssertEqual(WhipPleas.isoByTimeZone["Europe/Stockholm"], "SE")
        XCTAssertEqual(WhipPleas.isoByTimeZone["Europe/Bucharest"], "RO")
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

    /// Four words at most (2026-11-12, *te rog io mult*; three from 2026-11-10, one from 2026-10-31, two before).
    func testEveryPhraseIsShort() {
        XCTAssertEqual(WhipPleas.maxWords, 4)
        for phrase in WhipPleas.phrases {
            let words = WhipPleas.flagged(phrase).words.split(separator: " ")
            XCTAssertLessThanOrEqual(words.count, WhipPleas.maxWords, "\(phrase) is too long")
        }
    }

    /// The flag is the only emoji left (2026-10-29): words, then the country.
    func testNoEmojiBesideTheFlag() {
        for phrase in WhipPleas.phrases {
            let words = WhipPleas.flagged(phrase).words
            XCTAssertTrue(words.allSatisfy { $0.isLetter || $0.isWhitespace || $0.isPunctuation },
                          "\(phrase) carries more than its flag")
        }
    }

    /// Every thank-you ends with its country's flag (2026-10-29; it opened
    /// with it from 2026-10-23), one glyph of two regional indicators, from a
    /// country the right-click can give a voice to (Schengen ∪ euro only,
    /// until 2026-11-11).
    func testEveryPhraseEndsWithAFlagThatHasAVoice() {
        for phrase in WhipPleas.phrases {
            let (flag, iso, _) = WhipPleas.flagged(phrase)
            XCTAssertEqual(flag.unicodeScalars.count, 2, "\(phrase) has no flag")
            XCTAssertEqual(iso.count, 2, "\(phrase) has no flag")
            XCTAssertNotNil(WhipVoice.languageByCountry[iso], "\(phrase): no voice language for \(iso)")
            XCTAssertNotNil(WhipVoice.countryName(of: phrase), "\(phrase): \(iso) is no country")
        }
    }

    /// The ISO code is read off the flag itself — no second table to drift.
    func testFlaggedReadsTheIsoCodeOffTheFlag() {
        let (flag, iso, words) = WhipPleas.flagged("merci beaucoup 🇫🇷")
        XCTAssertEqual(flag, "🇫🇷")
        XCTAssertEqual(iso, "FR")
        XCTAssertEqual(words, "merci beaucoup ")
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
