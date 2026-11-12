import XCTest
@testable import VictorEffects

/// 🎵 A soundtrack-only video's `.srt` lines, karaoke-paced (`VideoCaptions`).
final class VideoCaptionsTests: XCTestCase {

    func testTheRouteCarriesTheIdAndTheCues() {
        let json = #"[{"at":0,"end":1.5,"text":"Mayday! Mayday!"}]"#
        let encoded = json.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            .replacingOccurrences(of: "&", with: "%26")
        XCTAssertEqual(EffectsRouter.route(forPath: "/caption/video/KLSdOY-6R_U?cues=\(encoded)"),
                       .videoCaption("KLSdOY-6R_U", json))
        XCTAssertEqual(EffectsRouter.route(forPath: "/caption/video/KLSdOY-6R_U/stop"),
                       .videoCaptionStop("KLSdOY-6R_U"))
        XCTAssertEqual(EffectsRouter.route(forPath: "/caption/video/KLSdOY-6R_U"), .unknown)
    }

    func testCuesDecodeOrRefuse() {
        XCTAssertEqual(VideoCaptions.decode(#"[{"at":1,"end":2,"text":"Hi"}]"#),
                       [VideoCaptions.Cue(at: 1, end: 2, text: "Hi")])
        XCTAssertNil(VideoCaptions.decode("nope"))
    }

    /// Every word lights up inside its cue, first word at the cue, a long word
    /// taking longer than a short one.
    func testWordsShareTheCueByTheirLetters() {
        let starts = VideoCaptions.wordStarts("This device... and this device.", span: 2)
        XCTAssertEqual(starts.count, SoundCaptions.wordEnds("This device... and this device.").count)
        XCTAssertEqual(starts.first, 0)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertLessThan(starts.last!, 2)
        // "This"(4) then "device"(6): the second word starts 4/23 of the way in (4+6+3+4+6).
        XCTAssertEqual(starts[1], 2 * 4 / 23, accuracy: 1e-9)
    }

    func testALineIsTimedEndsWithItsCueAndStaysToBeRead() {
        let lines = VideoCaptions.lines([
            .init(at: 0.2, end: 2.0, text: "This is the most important device\nof the coast guard."),
            .init(at: 3, end: 3, text: "   "),
        ])
        XCTAssertEqual(lines.count, 1)
        let line = lines[0]
        XCTAssertEqual(line.at, 0.2)
        XCTAssertEqual(line.text, "This is the most important device of the coast guard.")
        XCTAssertEqual(line.words.count, SoundCaptions.wordEnds(line.text).count)
        XCTAssertEqual(line.lastWordEnd!, 1.8, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(line.seconds, 1.8 + SoundCaptions.readHold)
        XCTAssertFalse(SoundCaptions.fill(line.text, words: line.words, seconds: line.seconds,
                                          lastWordEnd: line.lastWordEnd).isEmpty)
    }
}
