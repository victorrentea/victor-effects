import XCTest
@testable import VictorEffects

/// "testul de 5" — verifies the scolding messages and the 5 crack sounds that
/// define the OpenWhip behavior were ported intact.
final class WhipMacroTests: XCTestCase {

    func testPhrasesPortedVerbatim() {
        // Ported from OpenWhip main.js sendMacro(): 7 phrases, weighted to FASTER.
        XCTAssertEqual(WhipMacro.phrases.count, 7)
        XCTAssertEqual(WhipMacro.phrases.filter { $0 == "FASTER" }.count, 3)
        XCTAssertTrue(WhipMacro.phrases.contains("GO FASTER"))
        XCTAssertTrue(WhipMacro.phrases.contains("Faster CLANKER"))
        XCTAssertTrue(WhipMacro.phrases.contains("Work FASTER"))
        XCTAssertTrue(WhipMacro.phrases.contains("Speed it up clanker"))
    }

    func testRandomPhraseAlwaysFromList() {
        let valid = Set(WhipMacro.phrases)
        for _ in 0..<1000 {
            XCTAssertTrue(valid.contains(WhipMacro.randomPhrase()))
        }
    }

    func testRandomPhraseVaries() {
        // 4 distinct phrases across 7 entries — 300 draws must yield more than one.
        let draws = Set((0..<300).map { _ in WhipMacro.randomPhrase() })
        XCTAssertGreaterThan(draws.count, 1)
    }

    func testAllFiveCrackSoundsBundled() {
        for letter in ["A", "B", "C", "D", "E"] {
            let name = "whip_\(letter).mp3"
            XCTAssertNotNil(SoundManager.shared.soundURL(for: name),
                            "\(name) should be bundled and resolvable")
        }
    }
}
