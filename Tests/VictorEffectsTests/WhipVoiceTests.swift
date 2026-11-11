import XCTest
@testable import VictorEffects

/// The right-click on the whip (2026-11-11): the last thank-you, said out
/// loud in its own language, with its country under it.
final class WhipVoiceTests: XCTestCase {

    func testTheFlagPicksTheLanguageUnlessTheWordsDo() {
        XCTAssertEqual(WhipVoice.language(of: "arigatō 🇯🇵"), "ja")
        XCTAssertEqual(WhipVoice.language(of: "mersi 🇲🇩"), "ro")
        XCTAssertEqual(WhipVoice.language(of: "cheers mate 🇬🇧"), "en-GB")
        // Three languages under one flag: the words decide.
        XCTAssertEqual(WhipVoice.language(of: "gràcies 🇪🇸"), "ca")
        XCTAssertEqual(WhipVoice.language(of: "milesker 🇪🇸"), "eu")
        XCTAssertEqual(WhipVoice.language(of: "gracias 🇪🇸"), "es")
        XCTAssertEqual(WhipVoice.language(of: "merci 🇨🇭"), "fr")
    }

    /// Google is asked for the words, never the flag or its ISO code.
    func testOnlyTheWordsAreSpoken() throws {
        XCTAssertEqual(WhipVoice.spokenText(of: "săru-mâna 🇷🇴"), "săru-mâna")
        let url = try XCTUnwrap(WhipVoice.googleURL(for: "धन्यवाद 🇮🇳"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "धन्यवाद")
        XCTAssertEqual(items.first { $0.name == "tl" }?.value, "hi")
    }

    /// Keyed by what is SAID — language and words — not by the flag: Romania's
    /// and Moldova's *mersi* is one file, France's *merci* another.
    func testCacheIsKeyedByLanguageAndWords() {
        XCTAssertEqual(WhipVoice.cacheURL(for: "mersi 🇷🇴"), WhipVoice.cacheURL(for: "mersi 🇲🇩"))
        XCTAssertNotEqual(WhipVoice.cacheURL(for: "merci 🇫🇷"), WhipVoice.cacheURL(for: "mersi 🇷🇴"))
        XCTAssertTrue(WhipVoice.cacheURL(for: "grazie 🇮🇹").lastPathComponent.hasPrefix("it-"))
    }

    func testCountryNameIsInEnglish() {
        XCTAssertEqual(WhipVoice.countryName(of: "grazie 🇮🇹"), "Italy")
        XCTAssertEqual(WhipVoice.countryName(of: "mersi 🇲🇩"), "Moldova")
        XCTAssertEqual(WhipVoice.countryName(of: "arigatō 🇯🇵"), "Japan")
    }

    /// An explained word stops where it was, stays fully opaque for the hold,
    /// then fades — and lives exactly that long.
    func testAnExplainedPleaHoldsThenFades() {
        var plea = WhipPleas.Plea(text: "grazie 🇮🇹", at: .zero, bornMs: 0)
        XCTAssertTrue(WhipPleas.isAlive(plea, now: WhipPleas.lifeMs))
        XCTAssertFalse(WhipPleas.isAlive(plea, now: WhipPleas.lifeMs + 1))

        plea.explainedMs = 1500   // already fading (t ≈ 0.77) when right-clicked
        XCTAssertEqual(WhipPleas.progress(plea, now: 1500), 0.6, accuracy: 1e-9, "back to full colour")
        XCTAssertEqual(WhipPleas.progress(plea, now: 1500 + WhipPleas.explainHoldMs - 1), 0.6, accuracy: 1e-9)
        XCTAssertEqual(WhipPleas.progress(plea, now: 1500 + WhipPleas.explainHoldMs + WhipPleas.fadeMs), 1, accuracy: 1e-9)
        XCTAssertTrue(WhipPleas.isAlive(plea, now: 1500 + WhipPleas.explainHoldMs))
        XCTAssertFalse(WhipPleas.isAlive(plea, now: 1500 + WhipPleas.explainHoldMs + WhipPleas.fadeMs))

        var early = WhipPleas.Plea(text: "grazie 🇮🇹", at: .zero, bornMs: 0)
        early.explainedMs = 200
        XCTAssertEqual(WhipPleas.progress(early, now: 1000), 200 / WhipPleas.lifeMs, accuracy: 1e-9, "frozen mid-rise")
    }
}
