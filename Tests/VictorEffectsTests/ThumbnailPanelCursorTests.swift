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
/// **The hover mark is thick enough to find from a metre away.** Its numbers are
/// also load-bearing against each other: the red playing border has to keep
/// covering the hover outline exactly, and the hover scale-up has to stay inside
/// the gap between tiles.
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

    func testTheHoverRingIsThickEnoughToFindFromAMetreAway() {
        XCTAssertGreaterThanOrEqual(
            TileView.hoverRingWidth, 5,
            "the bright ring was 2 pt and read as 'a tile with an edge', not as 'THIS one'"
        )
        XCTAssertGreaterThan(
            TileView.hoverRimWidth, TileView.hoverRingWidth,
            "the dark rim has to show OUTSIDE the white ring, or the ring vanishes on the light half of the board"
        )
        XCTAssertGreaterThan(TileView.hoverRingInset, 0)
    }

    func testAHoveredTileLiftsWithoutTouchingItsNeighbours() {
        XCTAssertGreaterThan(TileView.hoverScale, 1, "hover should bring the tile forward")
        // The biggest cell the grid will ever lay out: the full board on the
        // widest panel it is placed on.
        let m = ThumbnailGridView.metrics(fitting: NSSize(width: 2560, height: 1415),
                                          count: 91, columns: 13)
        let growthPerSide = m.cell * (TileView.hoverScale - 1) / 2
        XCTAssertLessThan(
            growthPerSide, ThumbnailGridView.gap,
            """
            a hovered \(m.cell) pt tile grows \(growthPerSide) pt a side into a \
            \(ThumbnailGridView.gap) pt gap — it would overlap its neighbour, and \
            sibling order (not hover) decides which one wins
            """
        )
    }

    /// The red border is added after the two hover layers and covers them
    /// exactly. Growing the hover outline without growing the border would leave
    /// the white ring peeking out around a playing tile.
    func testThePlayingBorderStillCoversTheHoverOutline() throws {
        let swift = try code("Sources/VictorEffects/TileView.swift")
        XCTAssertTrue(
            swift.contains("borderLayer.borderWidth = Self.hoverRimWidth"),
            """
            the red playing border's width must be TIED to hoverRimWidth, not a \
            literal of its own: its job is to cover the hover outline exactly, so \
            a tile that is playing says that first.
            """
        )
    }
}
