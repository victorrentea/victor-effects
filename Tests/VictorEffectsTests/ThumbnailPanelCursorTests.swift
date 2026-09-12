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

    // MARK: - The cursor

    func testNothingOverThePanelAsksForAPointingHand() throws {
        for path in Self.panelSources {
            XCTAssertFalse(
                try code(path).contains("pointingHand"),
                """
                \(path) asks for a pointing hand. The board is one surface of 91 \
                buttons and the pointer must not change shape anywhere on it — \
                including into a hand. Pin NSCursor.arrow via PanelCursor.pinArrow().
                """
            )
        }
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
                swift.contains("PanelCursor.pinArrow()"),
                "\(path) should pin the arrow through PanelCursor, so there is one cursor policy and one log"
            )
        }
    }

    /// The tempting fix that cannot work here, nailed down so nobody spends an
    /// afternoon on it twice.
    func testTheArrowIsNotPinnedWithCursorRects() throws {
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
