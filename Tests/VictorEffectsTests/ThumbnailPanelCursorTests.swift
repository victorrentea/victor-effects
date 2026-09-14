import XCTest
@testable import VictorEffects

/// Two promises about the board that nothing in the compiler keeps.
///
/// **The pointer does not change shape over the panel.** That is not a property
/// of being a window on top: a borderless, non-activating panel that answers no
/// cursor question lets the window UNDERNEATH answer it, so the board showed an
/// I-beam over a terminal and a pointing hand over a browser link — a pointer
/// reacting to a window the user cannot see. The fix is a tracking area with
/// `.cursorUpdate` on every view the pointer can be over, and it is invisible
/// when it rots: delete `.cursorUpdate` from one options array and the panel
/// still builds, still shows, and quietly goes back to borrowing its cursor.
///
/// **The mark under the pointer never moves the picture.** Hover and press are
/// painted in the dead black gutter around the cell — green and red — and reach
/// exactly as far as the neighbours. The old mark did the opposite: it scaled
/// the tile up 1.04 and glowed, so the artwork twitched under the mouse.
///
/// **And the panel is the same board as the tablet.** Same ⭐ on the same tiles
/// (the catalogue's answer, in process), at the same fractions of the cell; the
/// video titles at the tablet's own ratio, which the panel had been drawing at
/// half size because `textSize = 48f` in Kotlin is sp and it had been copied as
/// px.
///
/// Both are asserted against THE SOURCE where no value is exported, the same
/// trick as `SoundEffectMapDriftTests` — the only way to pass is to make the
/// real thing true.
final class ThumbnailPanelCursorTests: XCTestCase {

    /// The views the pointer can be over while the panel is up.
    private static let panelSources = [
        "Sources/VictorEffects/TileView.swift",
        "Sources/VictorEffects/ThumbnailGridView.swift",
        "Sources/VictorEffects/ThumbnailPanel.swift",
        // Page 2 is a second pair of views under the same pointer, and it would
        // lose the cursor in exactly the same silent way.
        "Sources/VictorEffects/VideoGridView.swift",
    ]

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VictorEffectsTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The same file with its `//` and `///` lines removed, which is what every
    /// assertion below reads.
    ///
    /// These files EXPLAIN the mechanisms they must not use — the note on why
    /// cursor rects cannot work here names `addCursorRect` — so a test that
    /// searched the raw text would be failed by its own documentation, and the
    /// only way to pass would be to delete the explanation.
    private func code(_ relativePath: String) throws -> String {
        try source(relativePath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - The hover mark must actually reach the glass

    /// **The bug the geometry tests could not see.** Every outset assertion
    /// passed while the green was invisible on screen: `gutterLayer` was the
    /// right size, at opacity 1, and then clipped away at the tile's own edge,
    /// because `NSView.clipsToBounds` defaults to TRUE on macOS 14 and quietly
    /// sets `masksToBounds` on the backing layer.
    ///
    /// The mark is painted OUTSIDE the cell by design, so a tile that clips is
    /// a tile with no hover mark at all — on either screen, at every size.
    func testATileNeverClipsItsOwnHoverMark() {
        let tile = Tile(n: 1, asset: "x.mp3", image: "x.png", label: nil, restartable: false)
        let view = TileView(tile: tile)
        view.frame = NSRect(x: 0, y: 0, width: 120, height: 120)
        view.layoutSubtreeIfNeeded()

        XCTAssertFalse(
            view.clipsToBounds,
            """
            TileView clips to its bounds, so the hover ring painted in the \
            gutter around it is cut off and nothing lights up. macOS 14 \
            defaults clipsToBounds to true — it must be set to false \
            explicitly, and a comment saying "NOT masksToBounds" does not do it.
            """
        )
        XCTAssertFalse(
            TileView.clippers(view).contains("TileView"),
            "TileView still clips its sublayers by some other route"
        )
    }

    func testAVideoTileNeverClipsItsOwnHoverMark() {
        let tile = VideoTile(n: 1, id: "v1", title: "t", startSeconds: 0, thumb: nil)
        let view = VideoTileView(tile: tile)
        view.frame = NSRect(x: 0, y: 0, width: 160, height: 90)
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(view.clipsToBounds, "VideoTileView clips its own hover ring away")
    }

    // MARK: - The cursor

    /// **This test used to assert the opposite.** Until 14 Sep 2026 the policy
    /// was "no pointing hand anywhere on the board"; Victor reversed it, because
    /// every cell is a button and the hand is what says so. The promise is kept
    /// in the same place rather than deleted: exactly ONE file may name a
    /// cursor shape for the board, so the policy cannot drift back a view at a
    /// time.
    func testOnlyPanelCursorChoosesTheBoardsShape() throws {
        for path in Self.panelSources {
            let swift = try code(path)
            guard !path.hasSuffix("ThumbnailGridView.swift") else { continue }
            XCTAssertFalse(
                swift.contains("pointingHand"),
                """
                \(path) names a cursor shape itself. The board's shape is \
                PanelCursor's single decision — call PanelCursor.pinHand() and \
                let it own which cursor that is.
                """
            )
        }
    }

    /// The hand has to be RE-asserted, not set once. An accessory app whose
    /// panel never becomes key loses the pointer's shape back to the active
    /// application between events, and `cursorUpdate`/`mouseMoved` only fire
    /// when the pointer moves — while a held key with a still mouse is the
    /// normal way this board is used.
    func testTheHandIsHeldForAsLongAsTheBoardIsUp() throws {
        let cursorSource = try code("Sources/VictorEffects/ThumbnailGridView.swift")
        XCTAssertTrue(cursorSource.contains("static func startPinning()"),
                      "PanelCursor no longer re-asserts the cursor; a single set() does not stick")

        let panel = try code("Sources/VictorEffects/ThumbnailPanel.swift")
        XCTAssertTrue(panel.contains("PanelCursor.startPinning()"),
                      "the panel shows the board without starting the cursor pin")
        XCTAssertEqual(
            panel.components(separatedBy: "PanelCursor.stopPinning()").count - 1, 2,
            """
            Every way the board leaves the screen must stop the pin — the slide \
            out AND the instant hide. A timer still asking for a hand over a \
            panel that is gone would fight whatever is underneath.
            """
        )
    }

    func testTheBoardShowsAPointingHand() throws {
        let swift = try code("Sources/VictorEffects/ThumbnailGridView.swift")
        XCTAssertTrue(
            swift.contains("static var cursor: NSCursor { .pointingHand }"),
            """
            PanelCursor no longer pins the pointing hand. Every cell on the \
            board is a button and Victor asked for the hand on 14 Sep 2026 — \
            if this is being changed back, change the doc comment that explains \
            the reversal too.
            """
        )
    }

    func testEveryViewUnderThePointerAnswersTheCursorQuestion() throws {
        for path in Self.panelSources {
            let swift = try code(path)
            guard swift.contains("NSTrackingArea(") else { continue }
            XCTAssertTrue(
                swift.contains(".cursorUpdate"),
                """
                \(path) builds a tracking area without `.cursorUpdate`. Without \
                that option this view never answers "what is the cursor here?", \
                the window UNDER the overlay answers instead, and the pointer \
                morphs to that window's idea of the spot.
                """
            )
            XCTAssertTrue(
                swift.contains(".activeAlways"),
                """
                \(path) builds a tracking area without `.activeAlways`. This app \
                is never the active one while the panel is up — without it the \
                events simply do not arrive.
                """
            )
            XCTAssertTrue(
                swift.contains("func cursorUpdate(with"),
                "\(path) takes `.cursorUpdate` events and never implements cursorUpdate(with:)"
            )
            XCTAssertTrue(
                swift.contains("PanelCursor.pinHand()"),
                "\(path) should pin the cursor through PanelCursor, so there is one cursor policy and one log"
            )
        }
    }

    /// The tempting fix that cannot work here, nailed down so nobody spends an
    /// afternoon on it twice.
    func testTheCursorIsNotPinnedWithCursorRects() throws {
        for path in Self.panelSources {
            XCTAssertFalse(
                try code(path).contains("addCursorRect"),
                """
                \(path) uses a cursor RECT. Cursor rects are dispatched to the key \
                window only, and this panel deliberately never becomes key \
                (ThumbnailPanel.canBecomeKey) so the caret stays in the app being \
                demonstrated — the rect would never fire once.
                """
            )
        }
    }

    /// A click on a window that refuses key status is always a "first mouse".
    func testThePanelTakesTheFirstClick() throws {
        for path in Self.panelSources {
            let swift = try code(path)
            guard swift.contains("NSTrackingArea(") else { continue }
            XCTAssertTrue(
                swift.contains("acceptsFirstMouse"),
                "\(path) would swallow the first click trying to focus a window that refuses focus"
            )
        }
    }

    // MARK: - The hover mark

    /// **The picture never moves.** Hover was a 1.04 scale-up with a white glow
    /// and press was a 0.95 scale-down; on a board of 91 photographs that reads
    /// as the artwork twitching under the pointer rather than as "the mouse is
    /// here". The mark moved OUT of the tile and into the dead black gutter
    /// around it, and nothing in the compiler stops a transform from creeping
    /// back — so this reads the source of both tile views.
    func testNeitherTileViewEverMovesItsPicture() throws {
        for path in ["Sources/VictorEffects/TileView.swift",
                     "Sources/VictorEffects/VideoGridView.swift"] {
            let swift = try code(path)
            XCTAssertFalse(swift.contains("setAffineTransform"),
                           "\(path) transforms the tile — hover and press must not move the artwork")
            XCTAssertFalse(swift.contains("shadowOpacity = on"),
                           "\(path) glows on hover — the mark belongs in the gutter, not around the picture")
            XCTAssertFalse(swift.contains("hoverScale"),
                           "\(path) still scales on hover")
        }
    }

    /// The mark reaches exactly to the neighbours: a fill short of the gap would
    /// leave a black hairline down the middle of the gutter, which is precisely
    /// the "a tile with an edge" reading the old 2 pt ring was replaced for.
    func testTheHoverFillCoversTheWholeGutter() {
        XCTAssertGreaterThanOrEqual(
            TileView.highlightGutter, ThumbnailGridView.gap,
            "the hover fill must reach the neighbouring tiles, not stop inside the gap"
        )
    }

    /// Green for hover, red for press, and they must not be the same mark: the
    /// press is the only feedback left now that the tile no longer sinks.
    func testHoverAndPressAreTellableApart() {
        XCTAssertNotEqual(TileView.hoverColor, TileView.pressColor)
        // Bright, saturated green — a dull one is lost against the panel's own
        // near-black ground from a metre away.
        var h = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        TileView.hoverColor.usingColorSpace(.sRGB)?.getRed(&h.r, green: &h.g, blue: &h.b, alpha: &h.a)
        XCTAssertGreaterThan(h.g, 0.8, "the hover green has to be bright")
        XCTAssertGreaterThan(h.g - max(h.r, h.b), 0.5, "and unmistakably green")
    }

    /// **No black is left around the tile under the pointer.**
    ///
    /// The fill reached one `gap` on all four sides, which is exactly right
    /// between two tiles and wrong on the rim of the board: the margin outside
    /// column 0 is `padding` plus whatever the centring left over after the cell
    /// was floored (page 1) or quantised to a multiple of 16 (page 2) — 8 pt of
    /// surviving black beside an edge sound tile on a 1400 pt panel, and 42 pt
    /// beside an edge video tile. An edge cell's fill therefore runs to the grid
    /// view's own edge, which is the panel's rounded card.
    func testTheHoverFillLeavesNoBlackOnTheRimOfTheBoard() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        // Top-left cell of a 3×3 grid whose centring left 20 pt over each way.
        let corner = NSRect(x: 20, y: 200, width: 80, height: 80)
        let o = TileView.highlightOutsets(cell: corner, in: bounds,
                                          row: 0, col: 0, rows: 3, cols: 3)
        XCTAssertEqual(corner.minX - o.left, bounds.minX, accuracy: 0.001,
                       "the fill must reach the left edge of the board, not stop 6 pt out")
        XCTAssertEqual(corner.maxY + o.top, bounds.maxY, accuracy: 0.001,
                       "the fill must reach the top edge of the board")
        // ...and towards a neighbour it is still exactly the gap, so the two
        // tiles' marks meet with no hairline and no overlap.
        XCTAssertEqual(o.right, ThumbnailGridView.gap, accuracy: 0.001)
        XCTAssertEqual(o.bottom, ThumbnailGridView.gap, accuracy: 0.001)
    }

    /// An interior cell is unchanged — the mark is still one gap on every side,
    /// which is the whole channel and no more.
    func testAnInteriorCellStillReachesExactlyItsNeighbours() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let middle = NSRect(x: 106, y: 114, width: 80, height: 80)
        let o = TileView.highlightOutsets(cell: middle, in: bounds,
                                          row: 1, col: 1, rows: 3, cols: 3)
        for side in [o.top, o.left, o.bottom, o.right] {
            XCTAssertEqual(side, ThumbnailGridView.gap, accuracy: 0.001)
        }
    }

    /// A ragged last row must not stretch its final tile to the rim while the
    /// full rows above it stop at the gap: 18 videos, 5 to a row, leaves three
    /// in row 3 and the one at column 2 has no neighbour but is not an edge.
    func testARaggedLastRowDoesNotStretchToTheRim() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let cell = NSRect(x: 20, y: 20, width: 80, height: 45)
        let o = TileView.highlightOutsets(cell: cell, in: bounds,
                                          row: 3, col: 2, rows: 4, cols: 5)
        XCTAssertEqual(o.right, ThumbnailGridView.gap, accuracy: 0.001,
                       "a short last row keeps the plain gutter on its open side")
        XCTAssertEqual(cell.minY - o.bottom, bounds.minY, accuracy: 0.001,
                       "but it is the bottom row, so downwards it still reaches the rim")
    }

    /// Both grids must hand their cells the per-side reach — a grid that kept
    /// the uniform inset would go back to framing its edge tiles in black, and
    /// nothing in the compiler notices.
    func testBothGridsGiveTheirEdgeCellsTheWiderReach() throws {
        for path in ["Sources/VictorEffects/ThumbnailGridView.swift",
                     "Sources/VictorEffects/VideoGridView.swift"] {
            XCTAssertTrue(try code(path).contains("TileView.highlightOutsets"),
                          "\(path) must measure each cell's reach to its neighbours or the rim")
        }
    }

    /// **The tile under the pointer lights up even when the pointer never
    /// moved.** Hover was `mouseEntered` and nothing else, which answers "the
    /// pointer crossed into this tile" rather than "which tile is the pointer
    /// on" — and those differ exactly when the board moves instead of the mouse.
    /// A panel sliding in, hugging to a new height or flipping page under a held
    /// key delivers no enter at all. On one screen the board takes the
    /// bottom-right corner and the pointer usually travels in, so a real enter
    /// hides the bug; on two screens it fills the second screen and lands under
    /// wherever the pointer already was, and nothing ever lit up.
    func testTheTileUnderAMouseThatNeverMovedIsStillHighlighted() throws {
        for path in ["Sources/VictorEffects/ThumbnailGridView.swift",
                     "Sources/VictorEffects/VideoGridView.swift"] {
            let swift = try code(path)
            XCTAssertTrue(swift.contains("func syncHoverToMouse"),
                          "\(path) must be able to resolve the hover with no event in hand")
            XCTAssertTrue(swift.contains("NSEvent.mouseLocation"),
                          "\(path) must ask where the pointer actually is")
            XCTAssertTrue(swift.contains("func hover(at point: NSPoint?)"),
                          "\(path) must resolve the hover from a POINT, not only from enter/exit")
        }
        let panel = try code("Sources/VictorEffects/ThumbnailPanel.swift")
        // The three moments the board moves and the mouse does not.
        XCTAssertGreaterThanOrEqual(
            panel.components(separatedBy: "syncHoverToMouse()").count - 1, 4,
            "the panel must re-resolve the hover when it lands, when it resizes and when it flips page")
        XCTAssertTrue(panel.contains("clearHover()"),
                      "a panel ordered out owes its grids no mouseExited — the hover must be cleared")
    }

    /// Both pages share one mark, because it is one pointer over one panel.
    func testTheVideoPageUsesTheSameHoverMark() throws {
        let swift = try code("Sources/VictorEffects/VideoGridView.swift")
        XCTAssertTrue(swift.contains("TileView.hoverColor") && swift.contains("TileView.pressColor"),
                      "page 2 must reuse TileView's hover/press colours, not invent its own")
        XCTAssertTrue(swift.contains("TileView.highlightGutter"),
                      "page 2 must reuse the same gutter width")
    }

    // MARK: - The ⭐, and the tablet's proportions

    /// The panel was the one surface drawing the board WITHOUT the star the
    /// tablet has had for weeks — same grid, same `tiles.json`, a star on one
    /// screen and not on the other. The set is the catalogue's, in process:
    /// exactly the tiles `GET /tiles` stamps an `effect` on.
    func testThePanelStarsExactlyTheCatalogueTiles() throws {
        let tilesJSON = EffectsConfig.shared.soundsDir.appendingPathComponent("tiles.json")
        guard let data = try? Data(contentsOf: tilesJSON),
              let doc = TilesManifest.parse(data), !doc.tiles.isEmpty else {
            throw XCTSkip("no tiles.json under soundsDir — tablet assets not on this machine")
        }
        let starred = Set(doc.tiles.filter { TileView.desktopEffect(for: $0) != nil }.map(\.asset))
        XCTAssertEqual(starred, Set(EffectsCatalog.assets),
                       "the panel's stars and the catalogue have drifted apart")

        // And against what the tablet is actually told, so the two boards cannot
        // disagree even if the catalogue itself is wrong.
        let enriched = try XCTUnwrap(TilesManifest.enrich(data))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(enriched.utf8)) as? [String: Any])
        let stamped = Set((obj["tiles"] as? [[String: Any]] ?? [])
            .filter { $0["effect"] != nil }
            .compactMap { $0["asset"] as? String })
        XCTAssertEqual(starred, stamped, "the panel stars a different set than GET /tiles hands the tablet")
    }

    /// The star is drawn at the tablet's own fractions (`w * 0.22f` of type, a
    /// `w * 0.05f` margin), because the panel's cell is whatever 13 columns
    /// leave on the screen it opens on and the two boards have to look like one.
    func testTheStarKeepsTheTabletsProportions() throws {
        XCTAssertEqual(TileView.starSizeRatio, 0.22, accuracy: 0.001)
        XCTAssertEqual(TileView.starMarginRatio, 0.05, accuracy: 0.001)
        let swift = try code("Sources/VictorEffects/TileView.swift")
        XCTAssertTrue(swift.contains("\u{2605}"), "the badge is the solid star glyph, as on the tablet")
        XCTAssertTrue(swift.contains("side * Self.starSizeRatio"),
                      "the star must scale off the tile width, never a fixed point size")
    }

    /// The video title was half the tablet's: `textSize = 48f` on a TextView is
    /// **sp**, and the panel had copied it as px.
    func testTheVideoTitleIsTheTabletsSize() {
        XCTAssertEqual(VideoTileView.titleSizeRatio, 0.20, accuracy: 0.001,
                       "48 sp at density 1.25 × font scale 1.3 on a 382 px cell ≈ 0.20 of the tile")
        let m = VideoGridView.metrics(fitting: NSSize(width: 2560, height: 1415), count: 5)
        let size = m.cellWidth * VideoTileView.titleSizeRatio
        XCTAssertLessThan(size, m.cellHeight / 2,
                          "a title taller than half the 16:9 cell would swallow the thumbnail")
    }
}
