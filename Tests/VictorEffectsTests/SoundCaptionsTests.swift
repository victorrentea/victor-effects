import XCTest
@testable import VictorEffects

/// The press caption. What is worth pinning is the promise to the person who
/// cannot hear: every audible tile says *something*, a silent one says nothing,
/// and the line never outstays a subtitle's welcome.
final class SoundCaptionsTests: XCTestCase {

    func testSongsAndNoisesComeFromTheTable() {
        XCTAssertEqual(SoundCaptions.caption(for: "62_lionel_richie.mp3"),
                       "♪ Hello, is it me you're looking for? ♪")
        XCTAssertEqual(SoundCaptions.caption(for: "04_wolf.mp3"), "[wolf howling]")
    }

    func testSilentTileHasNoCaption() {
        XCTAssertNil(SoundCaptions.caption(for: "80_badumtss.mp3"),
                     "the minion crowd is silent — a caption would describe a noise nobody made")
    }

    func testUnknownTileFallsBackToItsFilename() {
        XCTAssertEqual(SoundCaptions.caption(for: "92_door_open.mp3"), "[door open]")
        XCTAssertEqual(SoundCaptions.caption(for: "38b_dreamer.mp3"), "[dreamer]")
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

    /// Every tile on this Mac's board has a hand-written line, so the filename
    /// fallback stays a safety net for a tile added tomorrow, not the caption
    /// the room reads tonight.
    func testEveryShippedTileHasAWrittenCaption() throws {
        let tilesJSON = EffectsConfig.shared.soundsDir.appendingPathComponent("tiles.json")
        guard let data = try? Data(contentsOf: tilesJSON),
              let doc = TilesManifest.parse(data) else {
            throw XCTSkip("no tiles.json under soundsDir — tablet assets not on this machine")
        }
        for tile in doc.tiles where !SoundCaptions.silent.contains(tile.asset) {
            XCTAssertNotNil(SoundCaptions.table[tile.asset],
                            "#\(tile.n) \(tile.asset) has no line in SoundCaptions.table")
        }
    }
}
