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

    // MARK: - The corner is the triangle under the fold

    func testTheCornerIsTheTriangleBelowTheFold() {
        let side: CGFloat = 90                       // fold from (0,60) to (60,0)
        XCTAssertTrue(TileView.isInPeek(NSPoint(x: 5, y: 5), side: side))
        XCTAssertTrue(TileView.isInPeek(NSPoint(x: 30, y: 30), side: side))   // on the fold
        XCTAssertFalse(TileView.isInPeek(NSPoint(x: 31, y: 31), side: side))
        XCTAssertFalse(TileView.isInPeek(NSPoint(x: 80, y: 80), side: side))
        XCTAssertFalse(TileView.isInPeek(NSPoint(x: 5, y: 70), side: side))   // top-left = #NN, layer A
    }

    func testAClickOnTheCornerPressesTheTileUnderneath() throws {
        let host = try XCTUnwrap(TilesManifest.parse(Data(sample.utf8))).tiles[0]
        XCTAssertEqual(TileView.target(of: host, at: NSPoint(x: 5, y: 5), side: 90).asset, "81b_let_go.mp3")
        XCTAssertEqual(TileView.target(of: host, at: NSPoint(x: 70, y: 70), side: 90).asset, "81_let_it_be.mp3")
    }

    func testATileWithNothingUnderneathIsLayerAEverywhere() {
        let plain = Tile(n: 1, asset: "a.mp3", image: "a.jpg")
        XCTAssertEqual(TileView.target(of: plain, at: NSPoint(x: 1, y: 1), side: 90), plain)
    }

    // MARK: - Anti-drift: the corner has to be the tablet's corner

    /// The tablet's `TileImageView.drawPeek`, read from the sibling checkout.
    /// Skipped where the tablet repo is not next to this one (CI, a trainee's
    /// clone); on Victor's Mac it runs on every `build-app.sh`, which is the
    /// moment a drift would reach the room.
    private func tabletDrawPeek() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let kt = root.deletingLastPathComponent()
            .appendingPathComponent("victor-vibe-board/app/src/main/java/ro/victorrentea/helloworld/MainActivity.kt")
        guard let source = try? String(contentsOf: kt, encoding: .utf8) else {
            throw XCTSkip("no victor-vibe-board checkout beside this repo")
        }
        let start = try XCTUnwrap(source.range(of: "private fun drawPeek("),
                                  "drawPeek is gone from the tablet — the corner moved; follow it here")
        return String(source[start.lowerBound...].prefix(1800))
    }

    private func ratio(_ pattern: String, in body: String) throws -> CGFloat {
        let re = try NSRegularExpression(pattern: pattern)
        let m = try XCTUnwrap(re.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                              "tablet drawPeek no longer matches /\(pattern)/")
        return CGFloat(Double(body[Range(m.range(at: 1), in: body)!])!)
    }

    func testTheFoldIsTheTabletsFold() throws {
        let body = try tabletDrawPeek()
        let num = try ratio(#"val side = width \* ([0-9.]+)f / 3f"#, in: body)
        XCTAssertEqual(num / 3, TileView.peekSideRatio, accuracy: 1e-6)
        XCTAssertEqual(try ratio(#"peekShadowPaint\.strokeWidth = width \* ([0-9.]+)f"#, in: body),
                       TileView.peekShadowRatio, accuracy: 1e-6)
        XCTAssertEqual(try ratio(#"peekCreasePaint\.strokeWidth = width \* ([0-9.]+)f"#, in: body),
                       TileView.peekCreaseRatio, accuracy: 1e-6)
        XCTAssertTrue(body.contains("width * \(TileView.peekCreaseRatio)f"),
                      "the shadow's offset is the crease width on the tablet too")
    }
}
