import XCTest
@testable import VictorEffects

/// 🔊 `TileAudio`: what a press of each tile is HEARD as — the one table the
/// ▲/＋ hints, the ＋ renders and the per-tile gain read. The drift test parses
/// `EffectsEngine.playSound` (the way `SoundEffectMapDriftTests` does) so a tile
/// that starts playing another file cannot leave the hints measuring the wrong one.
final class TileAudioTests: XCTestCase {
    private let all: (String) -> Bool = { _ in true }

    func testTheTilesThatPlayAnotherFile() {
        XCTAssertEqual(TileAudio.files(forTile: "31_tarzan.mp3", exists: all), ["50_gong.mp3"])
        XCTAssertEqual(TileAudio.files(forTile: "53_rain.mp3", exists: all), ["57_checkmark.mp3"])
        XCTAssertEqual(TileAudio.files(forTile: "14_universal.mp3", exists: all), ["universal-minions.mp3"])
        XCTAssertEqual(TileAudio.files(forTile: "09_ave_maria.mp3", exists: all), [PrayController.tabletHymn])
        XCTAssertEqual(TileAudio.files(forTile: "09_ave_maria.mp3", exists: { $0 == PrayController.hymn }), [PrayController.hymn],
                       "the hymn the player falls back to")
        XCTAssertEqual(TileAudio.files(forTile: "01_baby.mp3", exists: all), ["01_baby.mp3"])
    }

    func testAnAlternatingTileIsHeardAsBothTakes() {
        XCTAssertEqual(TileAudio.files(forTile: "19_fail.mp3", exists: all), ["19_fail.mp3", "20_fail2.mp3"])
        XCTAssertEqual(TileAudio.files(forTile: "49_wrong.mp3", exists: all), ["49_wrong.mp3", "49b_tiktok_core.mp3"])
    }

    func testAFileIsOwnedByTheTileThatIsIt() {
        let tiles = ["31_tarzan.mp3", "50_gong.mp3", "14_universal.mp3"]
        XCTAssertEqual(TileAudio.owningTile(ofFile: "50_gong.mp3", tiles: tiles), "50_gong.mp3")
        XCTAssertEqual(TileAudio.owningTile(ofFile: "universal-minions.mp3", tiles: tiles), "14_universal.mp3")
        XCTAssertNil(TileAudio.owningTile(ofFile: "click.wav", tiles: tiles))
    }

    /// Every `if name == "<tile>"` branch of `playSound` that plays a file by
    /// name must play the tile's own file or one `TileAudio` lists for it.
    func testEffectsEngineDoesNotPlayAFileTileAudioDoesNotKnow() throws {
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/VictorEffects/EffectsEngine.swift")
        let text = try String(contentsOf: src, encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "func playSound(_ name: String"))
        let body = String(text[start.lowerBound...])
        let constants = ["TileAudio.irisSound": TileAudio.irisSound, "TileAudio.moneySound": TileAudio.moneySound,
                         "TileAudio.universalSound": TileAudio.universalSound]
        let branch = try NSRegularExpression(pattern: #"if name == "([^"]+)""#)
        let play = try NSRegularExpression(pattern: #"play(?:Overlapping)?TabletSound(?:Clipped)?\(\s*("([^"]+)"|TileAudio\.\w+)"#)
        let ns = body as NSString
        let branches = branch.matches(in: body, range: NSRange(location: 0, length: ns.length))
        XCTAssertGreaterThan(branches.count, 10, "the parser no longer finds playSound's branches")
        var checked = 0
        for (i, m) in branches.enumerated() {
            let tile = ns.substring(with: m.range(at: 1))
            let end = i + 1 < branches.count ? branches[i + 1].range.location : min(ns.length, m.range.location + 1500)
            let block = ns.substring(with: NSRange(location: m.range.location, length: end - m.range.location))
            let bns = block as NSString
            for p in play.matches(in: block, range: NSRange(location: 0, length: bns.length)) {
                let token = bns.substring(with: p.range(at: 1))
                let file = token.hasPrefix("\"") ? String(token.dropFirst().dropLast()) : (constants[token] ?? token)
                let heard = TileAudio.files(forTile: tile, exists: all)
                XCTAssertTrue(file == tile || heard.contains(file),
                              "\(tile) plays \(file), but TileAudio says it is heard as \(heard) — add it to TileAudio")
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 3, "the parser no longer finds the file plays")
    }
}
