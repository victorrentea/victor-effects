import XCTest
@testable import VictorEffects

/// The tuner's file is written on the web and read on a press: it must not be
/// able to cost a press its caption, and its track must obey the Mac's rules.
final class CaptionEditsTests: XCTestCase {

    private func cues(_ json: String) -> [CaptionEdits.Cue] {
        CaptionEdits.parse(Data(json.utf8))["a.mp3"] ?? []
    }

    func testABrokenFileMeansNoEdits() {
        XCTAssertTrue(CaptionEdits.parse(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(CaptionEdits.parse(Data(#"{"a.mp3":{"cues":[{"text":"no time"}]}}"#.utf8)).isEmpty)
        XCTAssertTrue(CaptionEdits.parse(Data(#"{"a.mp3":{"cues":[]}}"#.utf8)).isEmpty, "an empty track would mute the clip")
    }

    func testWordsAreOnsetsIntoTheClipAndTheLineLivesByThem() {
        let track = CaptionEdits.lines(cues(#"{"a.mp3":{"cues":[{"at":1,"text":"one two","words":[1.25,1.5]}]}}"#), clipSeconds: 30)
        XCTAssertEqual(track.count, 1)
        XCTAssertEqual(track[0].words, [0.25, 0.5])
        XCTAssertEqual(track[0].seconds, 2.5, accuracy: 0.001, "held to be read, however long the clip goes on")
    }

    func testAWordCountThatDisagreesWithTheTextLeavesTheLinePlain() {
        let track = CaptionEdits.lines(cues(#"{"a.mp3":{"cues":[{"at":0,"text":"one two three","words":[0,1]}]}}"#), clipSeconds: 5)
        XCTAssertEqual(track[0].words, [])
        XCTAssertEqual(track[0].seconds, 5)
    }

    func testAnUnorderedFileStillPlaysInOrder() {
        let track = CaptionEdits.lines(cues(#"{"a.mp3":{"cues":[{"at":3,"text":"b"},{"at":0,"text":"a"}]}}"#), clipSeconds: 8)
        XCTAssertEqual(track.map(\.text), ["a", "b"])
    }

    func testNoTitleLineIsAddedToAnEditedTrack() {
        let track = CaptionEdits.lines(cues(#"{"a.mp3":{"cues":[{"at":3,"text":"b"}]}}"#), clipSeconds: 8)
        XCTAssertEqual(track.map(\.at), [3])
    }

    func testTheExportCarriesTheWordsSoTheTunerCanStartFromThem() {
        let line = CaptionLine(at: 2, text: "one two", seconds: 3, words: [0.25, 0.75])
        let out = CaptionsExport.build(assets: ["a.mp3"], track: { _, _ in [line] }, duration: { _ in 6 })
        let cue = ((out["a.mp3"] as? [String: Any])?["cues"] as? [[String: Any]])?.first
        XCTAssertEqual(cue?["words"] as? [Double], [2.25, 2.75])
    }
}
