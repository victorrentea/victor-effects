import AppKit
import XCTest
@testable import VictorEffects

/// The press caption. What is worth pinning is the promise to the person who
/// cannot hear: every tile says *something*,
/// and the line never outstays a subtitle's welcome.
final class SoundCaptionsTests: XCTestCase {

    func testSongsAndNoisesComeFromTheTable() {
        XCTAssertEqual(SoundCaptions.caption(for: "62_lionel_richie.mp3"),
                       "♪ Hello, is it me you're looking for? ♪")
        XCTAssertEqual(SoundCaptions.caption(for: "04_wolf.mp3"), "[wolf howling]")
    }

    func testUnknownTileFallsBackToItsFilename() {
        XCTAssertEqual(SoundCaptions.caption(for: "92_door_open.mp3"), "[door open]")
        XCTAssertEqual(SoundCaptions.caption(for: "99b_dreamer.mp3"), "[dreamer]")
        XCTAssertEqual(SoundCaptions.caption(for: "alarm.mp3"), "[alarm]")
        XCTAssertEqual(SoundCaptions.caption(for: "90_breaking-glass.mp3"), "[glass shattering]")
        XCTAssertEqual(SoundCaptions.fallback(for: "99_breaking-glass.mp3"), "[breaking glass]")
    }

    func testLifetimeFollowsTheClipWithinBounds() {
        XCTAssertEqual(SoundCaptions.lifetime(clipSeconds: 4), 4)
        XCTAssertEqual(SoundCaptions.lifetime(clipSeconds: 0.4), SoundCaptions.minSeconds,
                       "a blip still stays up long enough to read")
        XCTAssertEqual(SoundCaptions.lifetime(clipSeconds: 37), SoundCaptions.maxSeconds,
                       "a theme tune does not hang a caption over the slides")
        XCTAssertEqual(SoundCaptions.lifetime(clipSeconds: nil), SoundCaptions.minSeconds)
    }

    func testANoiseIsATrackOfOneLine() {
        let track = SoundCaptions.schedule(for: "04_wolf.mp3", clipSeconds: 4)
        XCTAssertEqual(track.map(\.text), ["[wolf howling]"])
        XCTAssertEqual(track.map(\.at), [0])
        XCTAssertEqual(track.map(\.seconds), [4])
    }

    /// The point of the track: the words go up as they are sung, each line
    /// overlapping the next by the handover so they swap instead of blinking.
    func testASongFlowsLineByLine() {
        let track = SoundCaptions.schedule(for: "76_sfx_118.mp3", clipSeconds: 6.55)
        XCTAssertEqual(track.map(\.text), ["♪ It wasn't me ♪",
                                           "♪ Heard the words that I told her ♪",
                                           "♪ It wasn't me ♪",
                                           "♪ Heard the screams getting louder ♪",
                                           "♪ It wasn't me ♪"])
        XCTAssertEqual(track[0].seconds, 0.7 + SoundCaptions.handover, accuracy: 0.001)
        XCTAssertEqual(track.last!.seconds, SoundCaptions.minSeconds, accuracy: 0.001,
                       "the last line still stays up long enough to read")
    }

    func testASongWithAnIntroOpensOnItsTitle() {
        let track = SoundCaptions.schedule(for: "81_let_it_be.mp3", clipSeconds: 15.2)
        XCTAssertEqual(track.first?.text, "♪ Let it be ♪")
        XCTAssertEqual(track.first?.at, 0)
        XCTAssertEqual(track.first!.seconds, 2.3 + SoundCaptions.handover, accuracy: 0.001)
        XCTAssertEqual(track[1].text, "♪ When I find myself in times of trouble ♪")
    }

    func testAnInstrumentalGapGoesBlank() {
        let track = SoundCaptions.schedule(for: "61_hallelujah.mp3", clipSeconds: 17.1)
        XCTAssertEqual(track[0].seconds, SoundCaptions.maxSeconds,
                       "seven silent seconds do not keep the last Hallelujah on the slide")
    }

    /// A line out of order would be shown and immediately replaced; a song
    /// with lyrics but no `table` line would have no title to open on.
    func testEveryLyricTrackIsInOrderAndTitled() {
        for (asset, lines) in SoundCaptions.lyrics {
            XCTAssertNotNil(SoundCaptions.table[asset], "\(asset) has lyrics but no title line")
            XCTAssertEqual(lines.map(\.at), lines.map(\.at).sorted(), "\(asset) lines out of order")
        }
    }

    /// Every tile on this Mac's board has a hand-written line, so the filename
    /// fallback stays a safety net for a tile added tomorrow, not the caption
    /// the room reads tonight.
    func testEveryShippedTileHasAWrittenCaption() throws {
        let tilesJSON = EffectsConfig.shared.soundsDir.appendingPathComponent("tiles.json")
        guard let data = try? Data(contentsOf: tilesJSON),
              let doc = TilesManifest.parse(data) else {
            throw XCTSkip("no tiles.json under soundsDir — tablet assets not on this machine")
        }
        // Layer B too (`under`): the tiles under the tiles are pressed and
        // heard like any other, and this loop once skipped them — 38b and 46b
        // went out captioned "[dreamer]" and "[my way]" (2026-10-14).
        let pressable = doc.tiles.flatMap { tile in
            [("#\(tile.n)", tile.asset)] + (tile.under.map { [("#\(tile.n)b", $0.asset)] } ?? [])
        }
        XCTAssertTrue(pressable.contains { $0.0.hasSuffix("b") }, "no layer-B tile seen — is `under` still parsed?")
        for (n, asset) in pressable {
            XCTAssertNotNil(SoundCaptions.table[asset], "\(n) \(asset) has no line in SoundCaptions.table")
        }
    }

    // MARK: the karaoke fill

    /// ♪ and a lone dash are not words: the opening ♪ lights with the first
    /// word, the closing one with the last, so the line ends all yellow.
    func testWordsAreTokensWithALetter() {
        let text = "♪ Oops, I did it again ♪"
        XCTAssertEqual(SoundCaptions.wordEnds(text).count, 5)
        XCTAssertEqual(SoundCaptions.litLength(text, lit: 0), 0)
        XCTAssertEqual((text as NSString).substring(to: SoundCaptions.litLength(text, lit: 1)), "♪ Oops,")
        XCTAssertEqual(SoundCaptions.litLength(text, lit: 5), text.utf16.count)
        XCTAssertEqual(SoundCaptions.wordEnds("[wolf howling]").count, 2)
    }

    /// A sung line lights up as the review placed it, relative to the line.
    func testASungLineFillsAsItIsSung() {
        let track = SoundCaptions.schedule(for: "62_lionel_richie.mp3", clipSeconds: 8.6)
        let line = track[1]
        XCTAssertEqual(line.words.count, 6)
        XCTAssertEqual(line.words.first!, 4.53 - line.at, accuracy: 0.001,
                       "\"Is\" waits for the silence after the held Hello")
        XCTAssertEqual(line.words, line.words.sorted())
    }

    /// Nothing is said in a noise or an instrumental title, so nothing lights
    /// up: an even-paced fill read as the karaoke being out of sync.
    func testAnUntimedLineNeverFills() {
        XCTAssertEqual(SoundCaptions.schedule(for: "04_wolf.mp3", clipSeconds: 4)[0].words, [])
        XCTAssertEqual(SoundCaptions.schedule(for: "06_copyright_cartoon.mp3", clipSeconds: 4)[0].words, [])
    }

    /// An untimed line is plain white; a timed one starts dimmed, so its
    /// yellow is a step up in brightness, not just a tint of the white.
    func testUntimedIsWhiteAndUpcomingIsDimmed() {
        let colour = { (s: NSAttributedString) in s.attribute(.foregroundColor, at: s.length - 1, effectiveRange: nil) as? NSColor }
        XCTAssertEqual(colour(CaptionOverlay.label("[wolf howling]", lit: nil)), .white)
        XCTAssertEqual(colour(CaptionOverlay.label("♪ Let it be ♪", lit: 1)), CaptionOverlay.upcomingColor)
        XCTAssertEqual(colour(CaptionOverlay.label("♪ Let it be ♪", lit: 3)), CaptionOverlay.litColor)
    }

    /// The generated table only fires on a cue with the same start AND word
    /// count; edit a lyric without rerunning `tools/caption-words.py` and that
    /// line silently goes back to the even pace. This says which one.
    func testEveryHeardCueStillMatchesItsLine() {
        for (asset, cues) in SoundCaptions.wordTimes {
            let track = SoundCaptions.schedule(for: asset, clipSeconds: 30)
            for cue in cues {
                let line = track.first { abs($0.at - cue.at) < 0.01 }
                XCTAssertNotNil(line, "\(asset) @\(cue.at): no such line — rerun tools/caption-words.py")
                if let line {
                    XCTAssertEqual(SoundCaptions.wordEnds(line.text).count, cue.words.count,
                                   "\(asset) \"\(line.text)\": word count drifted — rerun tools/caption-words.py")
                }
            }
        }
    }
}
