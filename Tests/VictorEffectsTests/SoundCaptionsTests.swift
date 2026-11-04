import AppKit
import XCTest
@testable import VictorEffects

/// The press caption. What is worth pinning is the promise to the person who
/// cannot hear: every tile says *something*,
/// and the line never outstays a subtitle's welcome.
final class SoundCaptionsTests: XCTestCase {

    func testSongsAndNoisesComeFromTheTable() {
        XCTAssertEqual(SoundCaptions.caption(for: "62_lionel_richie.mp3"),
                       "Hello, is it me you're looking for?")
        XCTAssertEqual(SoundCaptions.caption(for: "04_wolf.mp3"), "[wolf howling]")
    }

    func testUnknownTileFallsBackToItsFilename() {
        XCTAssertEqual(SoundCaptions.caption(for: "92_door_open.mp3"), "[door open]")
        XCTAssertEqual(SoundCaptions.caption(for: "99b_dreamer.mp3"), "[dreamer]")
        XCTAssertEqual(SoundCaptions.caption(for: "alarm.mp3"), "[alarm]")
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
    /// each one staying up until it has been read, under the next one coming in.
    func testASongFlowsLineByLine() {
        let track = SoundCaptions.schedule(for: "76_sfx_118.mp3", clipSeconds: 6.55)
        XCTAssertEqual(track.map(\.text), ["Wasn't me",
                                           "Heard the words that I told her",
                                           "Wasn't me",
                                           "Heard the screams getting louder",
                                           "Wasn't me"])
        XCTAssertEqual(track[1].seconds, 1.58 + SoundCaptions.lastWordSweep + SoundCaptions.readHold, accuracy: 0.001,
                       "until its last word is full, plus a second to read it")
        XCTAssertGreaterThan(track[1].at + track[1].seconds, track[2].at, "the next line comes in under it")
        XCTAssertEqual(track.first!.seconds, SoundCaptions.minSeconds, accuracy: 0.001,
                       "a two-word line still stays up long enough to read")
    }

    /// The screen already says it (Victor, 2026-11-04): no line, not even the
    /// one made from the filename.
    func testTheTilesWithAPictureHaveNoCaption() {
        for asset in ["03_explosion.mp3", "10_red_phone.mp3", "11_fire.mp3", "15_flatline.mp3"] {
            XCTAssertNil(SoundCaptions.caption(for: asset), asset)
            XCTAssertEqual(SoundCaptions.schedule(for: asset, clipSeconds: 5).count, 0, asset)
            XCTAssertNil(SoundCaptions.table[asset], "\(asset): a line nobody will ever see")
        }
    }

    /// What the clip really says past its title, one cue per breath, every
    /// word timed, and never more lines at once than the stack holds.
    func testTheAnimatedPhoneCarriesOnPastItsTitle() {
        XCTAssertEqual(SoundCaptions.caption(for: "07_animated_phone.mp3"), "What does this button do?")
        let track = SoundCaptions.schedule(for: "07_animated_phone.mp3", clipSeconds: 8.26)
        XCTAssertEqual(track.map(\.text), ["What does this button do?",
                                           "Please, please…",
                                           "Do not push the button!",
                                           "You have no idea…"])
        for line in track {
            XCTAssertEqual(line.words.count, SoundCaptions.wordEnds(line.text).count, line.text)
        }
        let glass = track.map { $0.ahead() }
        for (i, line) in glass.enumerated() {
            let up = glass.filter { $0.at <= line.at && $0.at + $0.seconds > line.at }
            XCTAssertLessThanOrEqual(up.count, SoundCaptions.maxRows, "\(i): no line pushed out early")
        }
    }

    /// The fill holds as the note does, and the line stays to be read after it.
    func testAHeldLastWordFillsToItsEnd() {
        let line = SoundCaptions.schedule(for: "09_ave_maria.mp3", clipSeconds: 20.8)[0]
        XCTAssertEqual(line.text, "Ave Maria")
        XCTAssertEqual(line.lastWordEnd ?? 0, 11.2, accuracy: 0.001)
        XCTAssertEqual(line.seconds, 11.2 + SoundCaptions.readHold, accuracy: 0.001)
        let path = SoundCaptions.fill(line.text, words: line.words, seconds: line.seconds, lastWordEnd: line.lastWordEnd)
        XCTAssertEqual(path.last!.t, 11.2, accuracy: 0.001)
        let ahead = line.ahead()
        XCTAssertEqual(ahead.at + (ahead.lastWordEnd ?? 0), 11.2, accuracy: 0.001, "going up early moves no moment in the clip")
    }

    /// The press only raises the gun, in silence: the line comes with the shot.
    func testTheGunIsCaptionedAtItsFirstShotNotItsPress() {
        XCTAssertEqual(SoundCaptions.caption(for: "22_minigun.mp3"), "[AK47 firing]")
        XCTAssertFalse(SoundCaptions.captionsAtPress("22_minigun.mp3"))
        XCTAssertTrue(SoundCaptions.captionsAtPress("04_wolf.mp3"))
    }

    /// Sung words wait to be sung: only a [noise] opens a long intro.
    func testOnlyANoiseOpensALongIntro() {
        let rainbow = SoundCaptions.schedule(for: "37_rainbow.mp3", clipSeconds: 14)
        XCTAssertEqual(rainbow.first?.text, "Somewhere over the rainbow")
        XCTAssertEqual(rainbow.first?.at, 2.8)
        let letItBe = SoundCaptions.schedule(for: "81_let_it_be.mp3", clipSeconds: 15.2)
        XCTAssertEqual(letItBe.first?.text, "When I find myself in times of trouble")
        XCTAssertEqual(SoundCaptions.schedule(for: "39_skull_boom.mp3", clipSeconds: 10).first?.text, "[boom]")
    }

    /// A said line is not wrapped in quotes (Victor, 2026-11-04): the caption
    /// is the line itself. An apostrophe is not a quote.
    func testNoCaptionIsInQuotes() {
        let quotes = CharacterSet(charactersIn: "\"“”„«»")
        for (asset, text) in SoundCaptions.table {
            XCTAssertNil(text.rangeOfCharacter(from: quotes), "\(asset): \(text)")
        }
        for (asset, lines) in SoundCaptions.lyrics {
            for line in lines { XCTAssertNil(line.text.rangeOfCharacter(from: quotes), "\(asset): \(line.text)") }
        }
    }

    /// No subtitle carries a music note (Victor, 2026-11-04), whichever way
    /// a line reaches the glass.
    func testNoCaptionCarriesAMusicNote() {
        for asset in SoundCaptions.table.keys {
            for line in SoundCaptions.schedule(for: asset, clipSeconds: 20) {
                XCTAssertFalse(line.text.contains { "♪♫♬🎵".contains($0) }, "\(asset): \(line.text)")
            }
        }
    }

    /// No more words, no more line: it does not wait for the clip to end, or
    /// for the next line, whichever comes first.
    func testALineLeavesAfterItsWordsNotAfterTheClip() {
        let line = CaptionLine(at: 0, text: "Let it be", seconds: 6, words: [0, 1, 2])
        XCTAssertEqual(SoundCaptions.heldToBeRead(line).seconds,
                       2 + SoundCaptions.lastWordSweep + SoundCaptions.readHold, accuracy: 0.001)
        let noise = CaptionLine(at: 0, text: "[wolf howling]", seconds: 4)
        XCTAssertEqual(SoundCaptions.heldToBeRead(noise), noise, "nothing said, nothing to hold")
    }

    /// A line is up a second before its fill starts; the words keep their
    /// place in the clip, and so does the moment the line leaves.
    func testALineGoesUpBeforeItIsSung() {
        let line = CaptionLine(at: 2, text: "Let it be", seconds: 3, words: [1, 1.5, 2])
        let up = line.ahead()
        XCTAssertEqual(up.at, 3 - SoundCaptions.leadIn, accuracy: 0.001)
        XCTAssertEqual(up.at + up.seconds, 5, accuracy: 0.001)
        XCTAssertEqual(up.words.map { up.at + $0 }, [3, 3.5, 4])
        let noise = CaptionLine(at: 0, text: "[wolf howling]", seconds: 4)
        XCTAssertEqual(noise.ahead(), noise)
    }

    /// The opening line has nowhere to go before the press, but while the clip
    /// is still on its way to the speaker it does get its lead.
    func testAnOpeningLineLeadsAsFarAsThePress() {
        let line = CaptionLine(at: 0, text: "Hello", seconds: 3, words: [0.2])
        XCTAssertEqual(line.ahead().at, 0, "played here and now: up at once")
        XCTAssertEqual(line.ahead(earliest: -1.5).at, 0.2 - SoundCaptions.leadIn, accuracy: 0.001)
        XCTAssertEqual(line.ahead(earliest: -0.3).at, -0.3, accuracy: 0.001)
    }

    /// The roll-up: the newest row sits at the foot, the older ones above it.
    func testRowsRollUpFromTheFoot() {
        XCTAssertEqual(SoundCaptions.rollUp(heights: [60, 110, 60], gap: 8), [186, 68, 0])
        XCTAssertEqual(SoundCaptions.rollUp(heights: [60], gap: 8), [0])
        XCTAssertEqual(SoundCaptions.rollUp(heights: [], gap: 8), [])
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
            if SoundCaptions.uncaptioned.contains(asset) { continue }
            XCTAssertNotNil(SoundCaptions.table[asset], "\(n) \(asset) has no line in SoundCaptions.table")
        }
    }

    // MARK: the karaoke fill

    /// A lone dash is not a word, so it never needs a time of its own.
    func testWordsAreTokensWithALetter() {
        let text = "Oops, — I did it again"
        XCTAssertEqual(SoundCaptions.wordEnds(text).count, 5)
        XCTAssertEqual((text as NSString).substring(to: SoundCaptions.wordEnds(text)[0]), "Oops,")
        XCTAssertEqual(SoundCaptions.wordEnds("[wolf howling]").count, 2)
    }

    /// A soft hyphen times a long sung word by the syllable, and the room
    /// never sees it: the line is as wide as without it.
    func testASoftHyphenSplitsSyllablesAndDrawsNothing() {
        let text = "Hal\u{AD}le\u{AD}lu\u{AD}jah!"
        XCTAssertEqual(SoundCaptions.wordEnds(text).map { (text as NSString).substring(to: $0) },
                       ["Hal", "Hal\u{AD}le", "Hal\u{AD}le\u{AD}lu", "Hal\u{AD}le\u{AD}lu\u{AD}jah!"])
        func width(_ s: String) -> CGFloat {
            CTLineGetTypographicBounds(CTLineCreateWithAttributedString(CaptionOverlay.label(s, color: .white)), nil, nil, nil)
        }
        XCTAssertEqual(width(text), width("Hallelujah!"), accuracy: 0.01)
    }

    /// Each word WIPES from left to right while it is said — up to the next
    /// word's start, so a held note fills slowly — never jumps in whole.
    func testEachWordSweepsUntilTheNextIsHeard() {
        let text = "Let it be"   // ends: 3, 6, 9
        let path = SoundCaptions.fill(text, words: [0.5, 1.0, 1.2], seconds: 4)
        XCTAssertEqual(path.map(\.t), [0, 0.5, 1.0, 1.2, 1.2 + SoundCaptions.lastWordSweep])
        XCTAssertEqual(path.map(\.offset), [0, 0, 3, 6, text.utf16.count])
    }

    /// A long gap is a pause, not a held note: the word is full before it.
    func testAWordDoesNotCrawlThroughAPause() {
        let path = SoundCaptions.fill("Hello is it me", words: [0, 4, 4.3, 4.6], seconds: 6)
        XCTAssertEqual(path[1].t, SoundCaptions.maxWordSweep)
        XCTAssertEqual(path[1].offset, 5, "\"Hello\" is full")
        XCTAssertEqual(path[2].t, 4, "and waits for \"is\"")
        XCTAssertEqual(path.map(\.t), path.map(\.t).sorted())
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

    /// The words are timed into the clip, so the track waits until the clip is
    /// HEARD: lead + Bluetooth silence + the speaker's latency, counted from
    /// the play, not from the press. A stale play is the client's own: no wait.
    func testTheTrackWaitsUntilTheClipIsHeard() {
        let played = Date(timeIntervalSince1970: 1000)
        let delay = { (now: TimeInterval) in
            SoundCaptions.audibleDelay(playedAt: played, now: played.addingTimeInterval(now), lead: 0.32,
                                       bluetoothCompensation: 0.8, outputLatency: 0.55)
        }
        XCTAssertEqual(delay(0), 1.67, accuracy: 0.001)
        XCTAssertEqual(delay(0.02), 1.65, accuracy: 0.001, "the press lands after the play")
        XCTAssertEqual(delay(SoundCaptions.routedWindow + 0.1), 0, "not this press's play")
        XCTAssertEqual(SoundCaptions.audibleDelay(playedAt: played, now: played, lead: 0,
                                                  bluetoothCompensation: 0, outputLatency: 0), 0,
                       "off Bluetooth the caption starts with the sound")
    }

    /// Nothing is said in a noise or an instrumental title, so nothing lights
    /// up: an even-paced fill read as the karaoke being out of sync.
    func testAnUntimedLineNeverFills() {
        XCTAssertEqual(SoundCaptions.schedule(for: "04_wolf.mp3", clipSeconds: 4)[0].words, [])
        XCTAssertEqual(SoundCaptions.schedule(for: "06_copyright_cartoon.mp3", clipSeconds: 4)[0].words, [])
    }

    /// An untimed line has no path, so it stays plain white; a timed one is
    /// drawn dimmed under its yellow copy.
    func testUntimedHasNoFill() {
        XCTAssertTrue(SoundCaptions.fill("[wolf howling]", words: [], seconds: 3).isEmpty)
        let colour = { (s: NSAttributedString) in s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor }
        XCTAssertEqual(colour(CaptionOverlay.label("Let it be", color: CaptionOverlay.upcomingColor)), CaptionOverlay.upcomingColor)
    }

    /// The generated table only fires on a cue with the same start AND word
    /// count; edit a lyric without rerunning `tools/caption-words.py` and that
    /// line silently goes back to the even pace. This says which one.
    /// The dash lights up with the syllable before it, and every syllable of
    /// the chorus reaches the screen timed: a count that drifts drops the fill.
    func testYummyFillsSyllableBySyllable() {
        let track = SoundCaptions.schedule(for: "83_yummy.mp3", clipSeconds: 7.1)
        XCTAssertEqual(track.map(\.words.count), [7, 4, 5])
        let line = track[1]
        XCTAssertEqual(line.text.replacingOccurrences(of: "\u{AD}", with: ""), "That yummy-yum")
        let path = SoundCaptions.fill(line.text, words: line.words, seconds: line.seconds)
        let myEnds = SoundCaptions.wordEnds(line.text)[2]
        XCTAssertEqual(String(decoding: Array(line.text.utf16)[0..<myEnds], as: UTF16.self).last, "-")
        let reached = path.first { $0.offset == myEnds }
        XCTAssertEqual(reached?.t ?? -1, 4.06 - line.at, accuracy: 0.001, "\"my-\" is full when \"yum\" starts")
    }

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
