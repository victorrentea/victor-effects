import XCTest
@testable import VictorEffects

final class TilesManifestTests: XCTestCase {
    /// A hand-written sample in the shape the tablet repo writes. Deliberately
    /// not the real 91-tile file: that lives in a private repo, and a test that
    /// needs it would be red on every machine but one.
    private let sample = """
    {
      "columns": 13,
      "tiles": [
        { "n": 1,  "asset": "01_baby.mp3",   "image": "tiles/sfx_01_baby.jpg" },
        { "n": 53, "asset": "53_rain.mp3",   "image": "tiles/sfx_53_money.png", "restartable": true },
        { "n": 62, "asset": "62_lionel.mp3", "image": "tiles/sfx_62.jpg", "label": "HELLO", "copyright": true }
      ]
    }
    """

    func testParsesEveryField() throws {
        let doc = try XCTUnwrap(TilesManifest.parse(Data(sample.utf8)))
        XCTAssertEqual(doc.columns, 13)
        XCTAssertEqual(doc.tiles.count, 3)

        XCTAssertEqual(doc.tiles[0], Tile(n: 1, asset: "01_baby.mp3", image: "tiles/sfx_01_baby.jpg"))
        XCTAssertEqual(doc.tiles[1].restartable, true)
        XCTAssertEqual(doc.tiles[2].label, "HELLO")
        XCTAssertEqual(doc.tiles[2].copyright, true)
    }

    func testOptionalKeysDefaultToFalseAndNil() throws {
        let doc = try XCTUnwrap(TilesManifest.parse(Data(sample.utf8)))
        let first = doc.tiles[0]
        XCTAssertNil(first.label)
        XCTAssertFalse(first.restartable)
        XCTAssertFalse(first.copyright)
    }

    func testOrderIsGridOrder() throws {
        // The array order IS the grid order (rows of `columns`); the `n` field
        // is a label, not a position. A tile list that sorted itself by `n`
        // would silently rearrange a grid whose author put #62 first.
        let doc = try XCTUnwrap(TilesManifest.parse(Data(sample.utf8)))
        XCTAssertEqual(doc.tiles.map(\.n), [1, 53, 62])
    }

    func testMissingColumnsFallsBackRatherThanFailing() throws {
        let doc = try XCTUnwrap(TilesManifest.parse(Data(#"{"tiles":[]}"#.utf8)))
        XCTAssertEqual(doc.columns, 13)
        XCTAssertTrue(doc.tiles.isEmpty)
    }

    func testAnUnknownKeyDoesNotTakeTheManifestDown() throws {
        // The tablet may add a key before this app learns about it. Dropping
        // every tile because of one unknown field would turn a forward-compatible
        // addition into an outage.
        let json = #"{"columns":4,"tiles":[{"n":1,"asset":"a.mp3","image":"i.jpg","future":42}]}"#
        let doc = try XCTUnwrap(TilesManifest.parse(Data(json.utf8)))
        XCTAssertEqual(doc.columns, 4)
        XCTAssertEqual(doc.tiles.count, 1)
    }

    func testGarbageIsNil() {
        XCTAssertNil(TilesManifest.parse(Data("not json".utf8)))
    }

    func testTileImagePathCannotEscapeTheSoundsFolder() throws {
        // The image paths come from a JSON file this app does not own, and the
        // route hands the bytes to anyone who can reach the port.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tiles-escape-\(UUID().uuidString)")
        let outside = dir.appendingPathComponent("secret.txt")
        let inside = dir.appendingPathComponent("sounds/tiles/ok.png")
        try FileManager.default.createDirectory(at: inside.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("classified".utf8).write(to: outside)
        try Data("png".utf8).write(to: inside)
        defer { try? FileManager.default.removeItem(at: dir) }

        let previous = EffectsConfig.shared.values
        defer { EffectsConfig.shared.override(previous) }
        var v = previous
        v.soundsDir = dir.appendingPathComponent("sounds").path
        EffectsConfig.shared.override(v)

        XCTAssertNotNil(TilesManifest.image(relativePath: "tiles/ok.png"))
        XCTAssertNil(TilesManifest.image(relativePath: "../secret.txt"))
        XCTAssertNil(TilesManifest.image(relativePath: "tiles/../../secret.txt"))
    }
}
