import XCTest
@testable import VictorEffects

/// The four layouts this panel has to survive. Only one of them exists on any
/// given day — which is exactly why the rule is a pure function over described
/// screens instead of a walk over `NSScreen.screens`.
final class ThumbnailPanelPlacementTests: XCTestCase {
    private func screen(_ name: String, _ frame: NSRect,
                        primary: Bool = false, overlay: Bool = false) -> PanelScreen {
        PanelScreen(name: name, visibleFrame: frame, isPrimary: primary, isOverlay: overlay)
    }

    private let retina = NSRect(x: 0, y: 0, width: 1728, height: 1080)
    private let asus = NSRect(x: 1728, y: 0, width: 1920, height: 1055)
    private let wide = NSRect(x: -2560, y: 0, width: 2560, height: 1415)

    // MARK: - One screen

    func testSingleScreenTakesTwoThirdsBottomRight() throws {
        let only = screen("Color LCD", retina, primary: true, overlay: true)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(screens: [only]))

        XCTAssertEqual(p.screen, only)
        XCTAssertEqual(p.frame.width, (1728 * 2 / 3).rounded(.down))
        XCTAssertEqual(p.frame.height, (1080 * 2 / 3).rounded(.down))
        // Bottom-right: away from the menu bar and from the top-left of a slide.
        XCTAssertEqual(p.frame.maxX, retina.maxX - ThumbnailPanelPlacement.margin)
        XCTAssertEqual(p.frame.minY, retina.minY + ThumbnailPanelPlacement.margin)
    }

    func testSingleScreenPanelStaysInsideTheScreen() throws {
        let only = screen("Color LCD", retina, primary: true, overlay: true)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(screens: [only]))
        XCTAssertTrue(retina.contains(p.frame))
    }

    // MARK: - Two screens

    func testHomeLayoutPutsThePanelOnTheExternal() throws {
        // Desk: the built-in retina is primary AND the screen the effects (and
        // any mirroring) live on; the ASUS is the spare.
        let builtIn = screen("Color LCD", retina, primary: true, overlay: true)
        let external = screen("ASUS MB166C", asus)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(screens: [builtIn, external]))

        XCTAssertEqual(p.screen.name, "ASUS MB166C")
        XCTAssertEqual(p.frame, asus.insetBy(dx: ThumbnailPanelPlacement.inset,
                                             dy: ThumbnailPanelPlacement.inset))
    }

    func testVenueLayoutFallsBackToThePrimaryRatherThanTheProjectedScreen() throws {
        // Venue: the ASUS is made primary so the menu bar is off the projector,
        // and the retina is mirrored to the room. The only screen left is the
        // primary — and taking it is right: the literal "never the main screen"
        // rule would put the soundboard on the projector, in front of everyone.
        let asusPrimary = screen("ASUS MB166C", asus, primary: true)
        let projected = screen("Color LCD", retina, overlay: true)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(screens: [asusPrimary, projected]))

        XCTAssertEqual(p.screen.name, "ASUS MB166C")
        XCTAssertTrue(p.screen.isPrimary)
        XCTAssertFalse(p.screen.isOverlay)
        XCTAssertEqual(p.frame, asus.insetBy(dx: ThumbnailPanelPlacement.inset,
                                             dy: ThumbnailPanelPlacement.inset))
    }

    // MARK: - Three screens

    func testThreeScreensPickNeitherTheProjectedNorThePrimary() throws {
        let builtIn = screen("Color LCD", retina, primary: true, overlay: true)
        let asusScreen = screen("ASUS MB166C", asus)
        let wideScreen = screen("LG UltraFine", wide)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(
            screens: [builtIn, asusScreen, wideScreen]))

        XCTAssertFalse(p.screen.isOverlay)
        XCTAssertFalse(p.screen.isPrimary)
        // Tie-break with no mouse: the largest, so the most tiles stay legible.
        XCTAssertEqual(p.screen.name, "LG UltraFine")
    }

    func testMouseWinsTheTieBreakAmongEligibleScreens() throws {
        let builtIn = screen("Color LCD", retina, primary: true, overlay: true)
        let asusScreen = screen("ASUS MB166C", asus)
        let wideScreen = screen("LG UltraFine", wide)
        let onTheAsus = NSPoint(x: asus.midX, y: asus.midY)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(
            screens: [builtIn, asusScreen, wideScreen], mouse: onTheAsus))

        XCTAssertEqual(p.screen.name, "ASUS MB166C")
    }

    func testTheMouseNeverDragsThePanelOntoTheProjector() throws {
        // The mouse is often ON the projected screen — that is where the slides
        // are. It is a tie-break among eligible screens, never a way in.
        let builtIn = screen("Color LCD", retina, primary: true, overlay: true)
        let external = screen("ASUS MB166C", asus)
        let onTheProjector = NSPoint(x: retina.midX, y: retina.midY)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(
            screens: [builtIn, external], mouse: onTheProjector))

        XCTAssertEqual(p.screen.name, "ASUS MB166C")
    }

    // MARK: - Degenerate

    func testNoScreensIsNil() {
        XCTAssertNil(ThumbnailPanelPlacement.choose(screens: []))
    }

    func testEveryScreenProjectedStillPlacesThePanel() throws {
        // A mirrored rig can report two screens that are both "the overlay
        // screen". A panel on the projector beats no panel at all.
        let a = screen("Color LCD", retina, primary: true, overlay: true)
        let b = screen("Surface Hub", asus, overlay: true)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(screens: [a, b]))
        XCTAssertFalse(p.frame.isEmpty)
    }

    // MARK: - Hugging the grid

    /// The real board: 91 tiles, 13 columns, so 7 rows.
    private func metrics(_ size: NSSize) -> ThumbnailGridView.Metrics {
        ThumbnailGridView.metrics(fitting: size, count: 91, columns: 13)
    }

    func testAWideFrameIsWidthBoundAndLeavesABandToTrim() {
        // 13 columns across 1872 pt of a 1920 screen vs 7 rows down 1007 pt:
        // the width binds, the grid comes out shorter than the frame, and the
        // difference is exactly the black band the panel used to frame.
        let frame = asus.insetBy(dx: ThumbnailPanelPlacement.inset,
                                 dy: ThumbnailPanelPlacement.inset)
        let m = metrics(frame.size)
        XCTAssertLessThan(m.hugHeight, frame.height)
        XCTAssertEqual(m.rows, 7)
        // rows × cell + gaps + padding, asserted as the arithmetic itself.
        XCTAssertEqual(m.hugHeight,
                       m.cell * 7 + ThumbnailGridView.gap * 6 + ThumbnailGridView.padding * 2,
                       accuracy: 0.001)
    }

    func testHuggingIsStable() {
        // Shrinking the panel to the hugged height must not shrink the cell
        // again — otherwise every show would creep the board smaller.
        let frame = asus.insetBy(dx: ThumbnailPanelPlacement.inset,
                                 dy: ThumbnailPanelPlacement.inset)
        let first = metrics(frame.size)
        let second = metrics(NSSize(width: frame.width, height: first.hugHeight))
        XCTAssertEqual(second.cell, first.cell)
        XCTAssertEqual(second.hugHeight, first.hugHeight, accuracy: 1)
    }

    func testHugKeepsTheBottomRightCornerOnOneScreen() {
        let only = screen("Color LCD", retina, primary: true, overlay: true)
        let p = ThumbnailPanelPlacement.choose(screens: [only])!
        XCTAssertEqual(p.anchor, .bottom)
        let hugged = ThumbnailPanelPlacement.hug(p.frame, toContentHeight: 300, anchor: .bottom)
        // The corner the eye is trained on does not move; only the top comes down.
        XCTAssertEqual(hugged.minY, p.frame.minY)
        XCTAssertEqual(hugged.maxX, p.frame.maxX)
        XCTAssertEqual(hugged.width, p.frame.width)
        XCTAssertEqual(hugged.height, 300)
    }

    func testHugStaysCentredOnAFilledScreen() throws {
        let retinaScreen = screen("Color LCD", retina, primary: true, overlay: true)
        let asusScreen = screen("ASUS", asus)
        let p = try XCTUnwrap(ThumbnailPanelPlacement.choose(screens: [retinaScreen, asusScreen]))
        XCTAssertEqual(p.anchor, .centred)
        let hugged = ThumbnailPanelPlacement.hug(p.frame, toContentHeight: 400, anchor: .centred)
        XCTAssertEqual(hugged.midY, p.frame.midY, accuracy: 1)
        XCTAssertEqual(hugged.height, 400)
        XCTAssertEqual(hugged.width, p.frame.width)
    }

    func testHugNeverGrowsTheFrame() {
        // A grid taller than its frame is the shrunk-cell case: it already uses
        // every point it was given and must not be handed more.
        let frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        XCTAssertEqual(ThumbnailPanelPlacement.hug(frame, toContentHeight: 900, anchor: .bottom), frame)
        XCTAssertEqual(ThumbnailPanelPlacement.hug(frame, toContentHeight: 400, anchor: .centred), frame)
    }

    func testTheSlideIsFasterThanTheHoldThatAsksForIt() {
        // A slide longer than the 180 ms hold would mean the board is still
        // flying when a quick hold is already over.
        XCTAssertLessThan(ThumbnailPanel.slideInDuration, ThumbnailPanelController.holdDelay + 0.05)
        XCTAssertLessThanOrEqual(ThumbnailPanel.slideOutDuration, 0.15)
    }
}
