import XCTest
@testable import VictorEffects

/// The pair behind one button. What is worth pinning is not the dictionary but
/// the *turn-taking*: a press that always returned the same file would be the
/// old behaviour wearing the new name, and nothing else in the app would notice.
final class AlternatingSoundsTests: XCTestCase {

    private let pairKey = "19_fail.mp3"
    private let partner = "20_fail2.mp3"

    // MARK: - The cycle

    func testFirstPressPlaysTheTileItself() {
        let alt = AlternatingSounds(table: [pairKey: [pairKey, partner]])
        XCTAssertEqual(alt.next(for: pairKey), pairKey,
                       "the first run of a pair is the tile that was pressed — not a surprise")
    }

    func testPressesAlternate() {
        let alt = AlternatingSounds(table: [pairKey: [pairKey, partner]])
        let runs = (0..<5).map { _ in alt.next(for: pairKey) }
        XCTAssertEqual(runs, [pairKey, partner, pairKey, partner, pairKey])
    }

    func testCyclesLongerThanTwoRotate() {
        let alt = AlternatingSounds(table: ["a.mp3": ["a.mp3", "b.mp3", "c.mp3"]])
        XCTAssertEqual((0..<4).map { _ in alt.next(for: "a.mp3") },
                       ["a.mp3", "b.mp3", "c.mp3", "a.mp3"],
                       "nothing here may assume a pair is exactly two files")
    }

    func testEachKeyKeepsItsOwnCursor() {
        let alt = AlternatingSounds(table: ["a.mp3": ["a.mp3", "b.mp3"],
                                            "x.mp3": ["x.mp3", "y.mp3"]])
        XCTAssertEqual(alt.next(for: "a.mp3"), "a.mp3")
        XCTAssertEqual(alt.next(for: "x.mp3"), "x.mp3", "one pair's press must not advance another's")
        XCTAssertEqual(alt.next(for: "a.mp3"), "b.mp3")
        XCTAssertEqual(alt.next(for: "x.mp3"), "y.mp3")
    }

    // MARK: - Everything else must pass through untouched

    func testUnlistedAssetIsReturnedUnchanged() {
        let alt = AlternatingSounds(table: [pairKey: [pairKey, partner]])
        for _ in 0..<3 {
            XCTAssertEqual(alt.next(for: "13_heartbeat.mp3"), "13_heartbeat.mp3",
                           "the lookup sits on EVERY /sound/play — an unpaired tile must be a no-op")
        }
    }

    func testPartnerPressedDirectlyPlaysItself() {
        let alt = AlternatingSounds(table: [pairKey: [pairKey, partner]])
        XCTAssertEqual(alt.next(for: partner), partner,
                       "only the KEY alternates; pressing the partner asset behaves as it always did")
    }

    func testEmptyCycleDegradesToTheAssetItself() {
        let alt = AlternatingSounds(table: ["a.mp3": []])
        XCTAssertEqual(alt.next(for: "a.mp3"), "a.mp3")
    }

    // MARK: - State

    func testPeekDoesNotAdvance() {
        let alt = AlternatingSounds(table: [pairKey: [pairKey, partner]])
        XCTAssertEqual(alt.peek(for: pairKey), pairKey)
        XCTAssertEqual(alt.peek(for: pairKey), pairKey, "peek describes, it does not spend")
        XCTAssertEqual(alt.next(for: pairKey), pairKey)
        XCTAssertEqual(alt.peek(for: pairKey), partner)
    }

    func testResetStartsTheCycleOver() {
        let alt = AlternatingSounds(table: [pairKey: [pairKey, partner]])
        XCTAssertEqual(alt.next(for: pairKey), pairKey)
        alt.reset()
        XCTAssertEqual(alt.next(for: pairKey), pairKey, "a fresh run begins at the first file, like a fresh launch")
    }

    // MARK: - The shipped table

    /// The table is the app's promise about which tiles are one button. Both
    /// halves of a cycle must be real, starred tiles: the partner still fires
    /// the KEY's effect (the press path reports the key, not what was played),
    /// so a pair that straddles two different effects would animate the wrong
    /// thing every other run.
    func testShippedPairsShareOneEffect() {
        XCTAssertFalse(AlternatingSounds.defaultTable.isEmpty)
        for (key, files) in AlternatingSounds.defaultTable {
            XCTAssertGreaterThan(files.count, 1, "\(key) is listed as alternating but has nothing to alternate with")
            XCTAssertEqual(files.first, key, "the first run of \(key) must be \(key) itself")
            let effects = Set(files.map { EffectsCatalog.effectName(forAsset: $0) ?? "" })
            XCTAssertEqual(effects.count, 1,
                           "\(key)'s cycle spans more than one desktop effect \(effects.sorted()) — "
                           + "the press path only ever reports \(key), so the other runs would fire the wrong visual")
        }
    }

    /// A cycle must not contain a file that is itself a key: pressing it would
    /// be two different alternations in one, and `playSound` resolves exactly
    /// once.
    func testNoPartnerIsAlsoAKey() {
        for (key, files) in AlternatingSounds.defaultTable {
            for partner in files.dropFirst() {
                XCTAssertNil(AlternatingSounds.defaultTable[partner],
                             "\(partner) is both a partner of \(key) and a cycle of its own")
            }
        }
    }

    /// Every file in the table has to be a tile that exists, for the same
    /// reason `SoundEffectMapDriftTests` checks the star set: a renamed mp3
    /// would leave a button silently playing nothing every other press.
    func testShippedPairsAreRealTiles() throws {
        let tilesJSON = EffectsConfig.shared.soundsDir.appendingPathComponent("tiles.json")
        guard let data = try? Data(contentsOf: tilesJSON),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tiles = obj["tiles"] as? [[String: Any]] else {
            throw XCTSkip("no tiles.json under soundsDir — tablet assets not on this machine")
        }
        let assets = Set(tiles.compactMap { $0["asset"] as? String })
        for (key, files) in AlternatingSounds.defaultTable {
            for file in files {
                XCTAssertTrue(assets.contains(file), "\(file) (in \(key)'s cycle) is not a tile in tiles.json")
            }
        }
    }
}
