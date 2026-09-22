import CryptoKit
import XCTest
@testable import VictorEffects

/// The ⭐ set, written out by hand.
///
/// `SoundEffectMapDriftTests` proves the catalogue is CONSISTENT with the rest
/// of the app — every effect it names exists, every play-path special case is
/// starred. This file proves something the consistency checks cannot: that the
/// set is what somebody *decided* it should be. Both tables feeding
/// `EffectsCatalog` are dictionaries a one-line diff can add to or delete from,
/// and the tablet now paints its badges straight off the answer — so a slip in
/// either place changes what the room sees with nothing to say so.
///
/// The literal below is therefore deliberately tedious. Adding an effect is
/// meant to cost a second edit *here*, in a file whose whole content is the
/// promise being made, so the diff says "and this tile gains a star" out loud.
final class EffectsCatalogTests: XCTestCase {

    /// Asset → the effect its tile fires on the desktop. 45 of the 91 tiles.
    private let expected: [String: String] = [
        "02_siren.mp3":          "alarm",          // the one toggled overlay, via /alarm/*
        "03_explosion.mp3":      "explosion",
        "06_copyright_cartoon.mp3": "magnifier",  // 🔍 the Pink Panther's glass, on the pointer
        "07_animated_phone.mp3": "red-button",  // the one that waits to be clicked
        "08_scream_man.mp3":     "fear",
        "10_red_phone.mp3":      "phone-ring",
        "11_fire.mp3":           "fire",
        "13_heartbeat.mp3":      "heartbeat",      // in-clip cue
        "15_flatline.mp3":       "pulse",
        "18_chainsaw.mp3":       "chainsaw",
        "19_fail.mp3":           "fail",
        "20_storm.mp3":          "storm",          // took square #20 off fail2
        "22_minigun.mp3":        "bullet-holes",
        "23_radar.mp3":          "sonar",          // in-clip cue
        "25_dark_door.mp3":      "dark-door",      // in-clip cue
        "26_drum.mp3":           "drum-roll",
        "27_clapping.mp3":       "applause",
        "29_gangnam_style.mp3":  "gangnam",
        "31_tarzan.mp3":         "iris",
        "34_phoenix.mp3":        "phoenix",
        "37_rainbow.mp3":        "rainbow",
        "40_joker.mp3":          "blood-drip",
        "41_love_hearts.mp3":    "love-hands",
        "42_saxophone.mp3":      "spiral-hearts",
        "44_laugh_emoji.mp3":    "laugh",
        "46_michael_buble.mp3":  "snow",
        "49_wrong.mp3":          "wrong-x",
        "50_gong.mp3":           "gong",
        "51_beethoven.mp3":      "beethoven",      // in-clip cue
        "53_rain.mp3":           "money",          // in-clip cue
        "55_star_wars.mp3":      "star-wars",
        "59_game_over.mp3":      "game-over",
        "61_dinner.mp3":         "microwave",      // in-clip cue
        "64_fbi.mp3":            "fbi-knock",      // in-clip cue
        "65_school_bell.mp3":    "fire-alarm",
        "67_sfx_109.mp3":        "brother",
        "69_scream_ghost.mp3":   "wazzup",
        "70_cavalry.mp3":        "cavalry",
        "71_one_more_time.mp3":  "sketch-arrow",
        "73_counter_strike.mp3": "counter-strike",
        "76_sfx_118.mp3":        "wasnt-me",
        "78_projector.mp3":      "sepia",
        "80_badumtss.mp3":       "minion",
        "89_fireworks.mp3":      "fireworks",
        "90_breaking-glass.mp3": "broken-glass",
    ]

    func testCatalogIsExactlyTheDecidedSet() {
        XCTAssertEqual(Set(EffectsCatalog.assets), Set(expected.keys),
                       """
                       The ⭐ set changed. If that was the point, update the table in \
                       EffectsCatalogTests too — it is the only place that says which \
                       tiles are SUPPOSED to animate the desktop.
                       """)
    }

    func testEveryAssetResolvesToItsDecidedEffectName() {
        for (asset, effect) in expected {
            XCTAssertEqual(EffectsCatalog.effectName(forAsset: asset), effect,
                           "\(asset) should fire '\(effect)'")
        }
    }

    func testASoundWithNoVisualHasNoEffectName() {
        // #01 baby and #52 saw: ordinary tiles. The saw in particular USED to
        // have a visual, and its absence here is the shape of a removal done
        // right.
        XCTAssertNil(EffectsCatalog.effectName(forAsset: "01_baby.mp3"))
        XCTAssertNil(EffectsCatalog.effectName(forAsset: "52_saw.mp3"))
        XCTAssertNil(EffectsCatalog.effectName(forAsset: "nope.mp3"))
    }

    func testAssetsAreSortedAndUnique() {
        XCTAssertEqual(EffectsCatalog.assets, EffectsCatalog.assets.sorted())
        XCTAssertEqual(EffectsCatalog.assets.count, Set(EffectsCatalog.assets).count)
    }

    // MARK: - effectsHash

    /// The hash is what the tablet compares on every 5-second ping, so it has to
    /// be stable across runs (no Set iteration order leaking in) and it has to
    /// MOVE when the set moves — a hash that did neither would silently pin the
    /// tablet to whatever it cached first.
    func testEffectsHashIsStableAndShapedLikeASha256() {
        XCTAssertEqual(EffectsCatalog.effectsHash, EffectsCatalog.effectsHash)
        XCTAssertEqual(EffectsCatalog.effectsHash.count, 64)
        XCTAssertTrue(EffectsCatalog.effectsHash.allSatisfy { $0.isHexDigit })
    }

    func testEffectsHashIsTheHashOfTheSortedAssetList() throws {
        // Recomputed independently rather than pinned to a literal: pinning the
        // digest would mean every new effect fails this test for no reason, and
        // the first tired person to paste the new value in would be right.
        let expectedHash = sha256Hex(EffectsCatalog.assets.joined(separator: "\n"))
        XCTAssertEqual(EffectsCatalog.effectsHash, expectedHash)
        XCTAssertNotEqual(expectedHash, sha256Hex(EffectsCatalog.assets.dropLast().joined(separator: "\n")),
                          "dropping an asset must change the hash")
    }

    private func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - the JSON bodies

    func testAssetsJSONListsEverythingSorted() throws {
        let data = Data(EffectsCatalog.assetsJSON.utf8)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["assets"] as? [String], EffectsCatalog.assets)
    }

    /// `GET /tiles` stamps the effect onto the tile itself. The tablet reads the
    /// badge off this field, so the three things that must hold are: a starred
    /// tile carries the NAME, an ordinary tile carries no key at all, and every
    /// key the manifest already had survives the round trip.
    func testTilesJSONIsEnrichedPerTile() throws {
        let manifest = """
        {"columns": 13, "tiles": [
          {"n": 1, "asset": "01_baby.mp3", "image": "tiles/sfx_01_baby.jpg"},
          {"n": 3, "asset": "03_explosion.mp3", "image": "tiles/sfx_03_explosion.jpg"},
          {"n": 53, "asset": "53_rain.mp3", "image": "tiles/sfx_53_money.png", "restartable": true},
          {"n": 62, "asset": "62_lionel_richie.mp3", "image": "x.jpg", "label": "HELLO", "copyright": true}
        ]}
        """
        let enriched = try XCTUnwrap(TilesManifest.enrich(Data(manifest.utf8)))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(enriched.utf8)) as? [String: Any])
        let tiles = try XCTUnwrap(obj["tiles"] as? [[String: Any]])

        XCTAssertEqual(obj["columns"] as? Int, 13)
        XCTAssertEqual(obj["effectsHash"] as? String, EffectsCatalog.effectsHash)
        XCTAssertEqual(tiles.count, 4)
        XCTAssertNil(tiles[0]["effect"], "an ordinary tile gets no key, not effect:null")
        XCTAssertEqual(tiles[1]["effect"] as? String, "explosion")
        XCTAssertEqual(tiles[2]["effect"] as? String, "money", "a play-path visual is starred too")
        XCTAssertNil(tiles[3]["effect"])
        // Nothing the manifest said is lost or reordered.
        XCTAssertEqual(tiles.map { $0["n"] as? Int }, [1, 3, 53, 62])
        XCTAssertEqual(tiles[2]["restartable"] as? Bool, true)
        XCTAssertEqual(tiles[3]["label"] as? String, "HELLO")
        XCTAssertEqual(tiles[3]["copyright"] as? Bool, true)
    }

    /// A key this build has never heard of must come out the other side: the
    /// manifest is written in the tablet's repo, and a Mac that silently dropped
    /// its newest field would be the exact drift this whole change removes.
    func testUnknownKeysSurviveTheEnrichment() throws {
        let manifest = #"{"columns":13,"future":"yes","tiles":[{"n":1,"asset":"01_baby.mp3","hue":42}]}"#
        let enriched = try XCTUnwrap(TilesManifest.enrich(Data(manifest.utf8)))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(enriched.utf8)) as? [String: Any])
        XCTAssertEqual(obj["future"] as? String, "yes")
        XCTAssertEqual((obj["tiles"] as? [[String: Any]])?.first?["hue"] as? Int, 42)
    }

    /// A stale `effect` written into the file by some older tool must not win
    /// over the live catalogue — otherwise the second source of truth this
    /// change deletes would quietly come back through the manifest.
    func testAStaleEffectKeyInTheFileIsOverwritten() throws {
        let manifest = """
        {"columns":13,"tiles":[
          {"n":1,"asset":"01_baby.mp3","effect":"ghost"},
          {"n":3,"asset":"03_explosion.mp3","effect":"wrong"}
        ]}
        """
        let enriched = try XCTUnwrap(TilesManifest.enrich(Data(manifest.utf8)))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(enriched.utf8)) as? [String: Any])
        let tiles = try XCTUnwrap(obj["tiles"] as? [[String: Any]])
        XCTAssertNil(tiles[0]["effect"], "01_baby has no effect — the stale key must go")
        XCTAssertEqual(tiles[1]["effect"] as? String, "explosion")
    }

    /// Bytes that are not a JSON object are passed through untouched rather than
    /// 404'd: `tiles.json` belongs to the other repo, and a manifest this build
    /// cannot parse is still the grid the tablet asked for.
    func testUnparseableManifestIsNotEnriched() {
        XCTAssertNil(TilesManifest.enrich(Data("not json".utf8)))
        XCTAssertNil(TilesManifest.enrich(Data("[1,2,3]".utf8)))
    }
}
