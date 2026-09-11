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
}
