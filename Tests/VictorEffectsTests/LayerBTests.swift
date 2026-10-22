import AppKit
import XCTest
@testable import VictorEffects

/// Layer B on the panel: the tile under a tile, drawn as the tablet's folded
/// corner and pressed by clicking that corner.
final class LayerBTests: XCTestCase {
    private let sample = """
    {"columns":13,"tiles":[
      {"n":81,"asset":"81_let_it_be.mp3","image":"tiles/81.jpg",
       "under":{"asset":"81b_let_go.mp3","image":"tiles/81b.jpg","label":"GO","copyright":true}},
      {"n":82,"asset":"82_x.mp3","image":"tiles/82.jpg"}
    ]}
    """

    func testTheUnderRowIsParsedAndBorrowsItsHostsNumber() throws {
        let doc = try XCTUnwrap(TilesManifest.parse(Data(sample.utf8)))
        let under = try XCTUnwrap(doc.tiles[0].under)
        XCTAssertEqual(under, Tile(n: 81, asset: "81b_let_go.mp3", image: "tiles/81b.jpg",
                                   label: "GO", copyright: true))
        XCTAssertNil(doc.tiles[1].under)
    }

    func testAnUnderRowWithoutAnAssetIsNoUnderRow() throws {
        let json = #"{"tiles":[{"n":1,"asset":"a.mp3","image":"a.jpg","under":{"image":"b.jpg"}}]}"#
        XCTAssertNil(try XCTUnwrap(TilesManifest.parse(Data(json.utf8))).tiles[0].under)
    }

    // MARK: - The corner is the triangle under the fold, minus a band along it

    // side 100: the fold runs from (0,76) to (76,0) — x + y = 76 — and the dead
    // band reaches 12 pt either side of it, measured across the fold.

    func testDeepInTheCornerIsTheTileUnderneath() {
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 8, y: 8), side: 100), .under)
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 2, y: 40), side: 100), .under)    // up the left edge
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 40, y: 2), side: 100), .under)    // along the bottom
    }

    func testTheRestOfTheTileIsTheTileItself() {
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 50, y: 50), side: 100), .top)     // centre, the label
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 5, y: 95), side: 100), .top)      // top-left, #NN
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 95, y: 5), side: 100), .top)      // bottom-right
    }

    func testOnTheCreaseNothingPlays() {
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 38, y: 38), side: 100), .none)    // on the fold
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 32, y: 32), side: 100), .none)    // a little inside
        XCTAssertEqual(TileView.peekHit(NSPoint(x: 44, y: 44), side: 100), .none)    // a little outside
        let edge = (76 - 12 * 2.0.squareRoot()) / 2                                  // d exactly 12 inside
        XCTAssertEqual(TileView.peekHit(NSPoint(x: edge - 0.3, y: edge - 0.3), side: 100), .under)
        XCTAssertEqual(TileView.peekHit(NSPoint(x: edge + 0.3, y: edge + 0.3), side: 100), .none)
    }

    func testAClickOnTheCornerPressesTheTileUnderneath() throws {
        let host = try XCTUnwrap(TilesManifest.parse(Data(sample.utf8))).tiles[0]
        XCTAssertEqual(TileView.target(of: host, at: NSPoint(x: 5, y: 5), side: 90)?.asset, "81b_let_go.mp3")
        XCTAssertEqual(TileView.target(of: host, at: NSPoint(x: 70, y: 70), side: 90)?.asset, "81_let_it_be.mp3")
    }

    func testAClickOnTheCreasePressesNothing() throws {
        let host = try XCTUnwrap(TilesManifest.parse(Data(sample.utf8))).tiles[0]
        XCTAssertNil(TileView.target(of: host, at: NSPoint(x: 34, y: 34), side: 90))
    }

    func testAClickThatCrossesTheCreasePressesNothing() throws {
        let host = try XCTUnwrap(TilesManifest.parse(Data(sample.utf8))).tiles[0]
        XCTAssertNil(TileView.target(of: host, down: NSPoint(x: 5, y: 5), up: NSPoint(x: 70, y: 70), side: 90))
        XCTAssertNil(TileView.target(of: host, down: NSPoint(x: 70, y: 70), up: NSPoint(x: 5, y: 5), side: 90))
    }

    func testATileWithNothingUnderneathIsLayerAEverywhere() {
        let plain = Tile(n: 1, asset: "a.mp3", image: "a.jpg")
        XCTAssertEqual(TileView.target(of: plain, at: NSPoint(x: 1, y: 1), side: 90), plain)
        XCTAssertEqual(TileView.target(of: plain, at: NSPoint(x: 34, y: 34), side: 90), plain)   // no crease to fear
    }

    func testTheCornerIsThirtyPercentBiggerThanTheOldTwoThirds() {
        let old = (2.0 / 3.0) * (2.0 / 3.0)
        XCTAssertEqual(Double(TileView.peekSideRatio * TileView.peekSideRatio) / old, 1.30, accuracy: 0.01)
    }

    // MARK: - Anti-drift: the corner has to be the tablet's corner

    /// A file of the tablet repo, read from the sibling checkout. Skipped where
    /// the tablet repo is not next to this one (CI, a trainee's clone); on
    /// Victor's Mac it runs on every `build-app.sh`, which is the moment a
    /// drift would reach the room.
    private func tabletSource(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let kt = root.deletingLastPathComponent()
            .appendingPathComponent("victor-vibe-board/app/src/main/java/ro/victorrentea/helloworld/\(name)")
        guard let source = try? String(contentsOf: kt, encoding: .utf8) else {
            throw XCTSkip("no victor-vibe-board checkout beside this repo (or \(name) moved)")
        }
        return source
    }

    private func kotlinConst(_ name: String, in source: String) throws -> CGFloat {
        let re = try NSRegularExpression(pattern: "const val \(name) = ([0-9.]+)f")
        let m = try XCTUnwrap(re.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                              "the tablet no longer declares \(name) — the corner moved; follow it here")
        return CGFloat(Double(source[Range(m.range(at: 1), in: source)!])!)
    }

    func testTheFoldIsTheTabletsFold() throws {
        let peek = try tabletSource("LayerBPeek.kt")
        XCTAssertEqual(try kotlinConst("SIDE_RATIO", in: peek), TileView.peekSideRatio, accuracy: 1e-6)
        XCTAssertEqual(try kotlinConst("SHADOW_RATIO", in: peek), TileView.peekShadowRatio, accuracy: 1e-6)
        XCTAssertEqual(try kotlinConst("CREASE_RATIO", in: peek), TileView.peekCreaseRatio, accuracy: 1e-6)
        XCTAssertEqual(try kotlinConst("DEAD_BAND_RATIO", in: peek), TileView.peekDeadBandRatio, accuracy: 1e-6)
    }

    func testTheFxBadgeIsTheTabletsBadge() throws {
        let fx = try tabletSource("FxMark.kt")
        XCTAssertEqual(try kotlinConst("HEIGHT_RATIO", in: fx), TileView.fxHeightRatio, accuracy: 1e-6)
        XCTAssertEqual(try kotlinConst("MARGIN_RATIO", in: fx), TileView.fxMarginRatio, accuracy: 1e-6)
        XCTAssertEqual(try kotlinConst("OUTLINE_RATIO", in: fx), TileView.fxOutlineRatio, accuracy: 1e-6)
        let outline = try tabletSource("FxMarkOutline.kt")
        XCTAssertTrue(outline.contains("The outline of \"\(TileView.fxMark)\""),
                      "the tablet's FX outline was generated from another mark — run its tools/make-fx-mark.swift")
    }
}
