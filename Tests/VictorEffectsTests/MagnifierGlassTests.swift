import CoreGraphics
import XCTest
@testable import VictorEffects

/// 🔍 The prop's geometry, checked without a screen.
///
/// Two things here are promises rather than implementation: the lens is **two
/// thirds of the screen height** (what Victor asked for — a third, then twice
/// that on the same day), and the point under
/// the pointer is **exactly** in the middle of the glass — a magnifier that
/// magnifies something half an inch off the thing being pointed at is worse
/// than no magnifier, and the arithmetic that keeps it honest is two
/// multiplications that are easy to get backwards.
final class MagnifierGlassTests: XCTestCase {

    private let retina = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testLensIsTwoThirdsOfTheScreenHeight() {
        XCTAssertEqual(MagnifierGlass.outerDiameter(in: retina), 1117.0 * 2 / 3, accuracy: 0.001)
        // …and of the HEIGHT, not the width or the area: the same lens has to
        // read the same on a wide external as on the built-in.
        let wide = CGRect(x: 0, y: 0, width: 3440, height: 1117)
        XCTAssertEqual(MagnifierGlass.outerDiameter(in: wide),
                       MagnifierGlass.outerDiameter(in: retina), accuracy: 0.001)
    }

    func testAZeroSizedOverlayDrawsNothing() {
        XCTAssertEqual(MagnifierGlass.outerDiameter(in: .zero), 0)
        XCTAssertNil(MagnifierGlass.image(outerDiameter: 0, scale: 2))
    }

    func testTheGlassIsTheLensMinusItsRim() {
        let d = MagnifierGlass.outerDiameter(in: retina)
        XCTAssertEqual(MagnifierGlass.glassRadius(outerDiameter: d),
                       d / 2 - d * MagnifierGlass.ringFraction, accuracy: 0.001)
        XCTAssertLessThan(MagnifierGlass.glassRadius(outerDiameter: d), d / 2)
    }

    /// The one that matters in the room: whatever the pointer is on has to land
    /// dead centre in the glass, magnified.
    func testThePointedAtSpotLandsInTheMiddleOfTheGlass() {
        let d = MagnifierGlass.outerDiameter(in: retina)
        let r = MagnifierGlass.glassRadius(outerDiameter: d)
        let z = MagnifierGlass.zoom
        for focus in [CGPoint(x: 864, y: 558), CGPoint(x: 0, y: 0),
                      CGPoint(x: 1728, y: 1117), CGPoint(x: 120, y: 940)] {
            let frame = MagnifierGlass.shotFrame(screen: retina, focus: focus, glassRadius: r)
            // Where the focused point ends up inside the clip layer, which is
            // 2r × 2r with its middle at (r, r).
            let inClip = CGPoint(x: frame.minX + focus.x * z, y: frame.minY + focus.y * z)
            XCTAssertEqual(inClip.x, r, accuracy: 0.001, "\(focus) slid sideways")
            XCTAssertEqual(inClip.y, r, accuracy: 0.001, "\(focus) slid vertically")
        }
    }

    func testTheScreenshotIsBlownUpByTheZoom() {
        let r = MagnifierGlass.glassRadius(outerDiameter: MagnifierGlass.outerDiameter(in: retina))
        let frame = MagnifierGlass.shotFrame(screen: retina, focus: CGPoint(x: 10, y: 10), glassRadius: r)
        XCTAssertEqual(frame.width, retina.width * MagnifierGlass.zoom, accuracy: 0.001)
        XCTAssertEqual(frame.height, retina.height * MagnifierGlass.zoom, accuracy: 0.001)
        XCTAssertGreaterThan(MagnifierGlass.zoom, 1, "a magnifier that does not magnify")
    }

    // MARK: The wheel

    /// The floor is the glass the room already knows: scrolling down can bring
    /// the lens back to how it dropped onto the pointer and no further, so the
    /// wheel can never leave a pane of plain glass magnifying nothing.
    func testTheWheelCannotZoomOutPastTheGlassItStartsAt() {
        XCTAssertEqual(MagnifierGlass.minZoom, MagnifierGlass.zoom, accuracy: 0.001)
        XCTAssertEqual(MagnifierGlass.clampZoom(0.5), MagnifierGlass.zoom, accuracy: 0.001)
        XCTAssertEqual(MagnifierGlass.clampZoom(1.0), MagnifierGlass.zoom, accuracy: 0.001)
        XCTAssertGreaterThan(MagnifierGlass.maxZoom, MagnifierGlass.minZoom)
        XCTAssertEqual(MagnifierGlass.clampZoom(99), MagnifierGlass.maxZoom, accuracy: 0.001)
        XCTAssertEqual(MagnifierGlass.clampZoom(3.5), 3.5, accuracy: 0.001)
    }

    /// One notch has to be a *step*, and a step in the direction it was turned:
    /// a factor of 1 would make the wheel dead, and the clamp must not eat the
    /// first notch off the floor.
    func testANotchMovesTheZoomAndTheRangeIsAFlickApart() {
        XCTAssertGreaterThan(MagnifierGlass.zoomStep, 1)
        let up = MagnifierGlass.clampZoom(MagnifierGlass.minZoom * MagnifierGlass.zoomStep)
        XCTAssertGreaterThan(up, MagnifierGlass.minZoom)
        let down = MagnifierGlass.clampZoom(up / MagnifierGlass.zoomStep)
        XCTAssertEqual(down, MagnifierGlass.minZoom, accuracy: 0.001)
        // …and the whole range is a flick, not a minute of scrolling.
        let notches = log(MagnifierGlass.maxZoom / MagnifierGlass.minZoom) / log(MagnifierGlass.zoomStep)
        XCTAssertLessThan(notches, 15, "the wheel takes too long to cross its own range")
    }

    /// Zoomed in, the spot under the pointer still has to be the spot in the
    /// middle of the glass — the whole arithmetic is recomputed per notch, so
    /// the centring is pinned at the far end of the range too, not just at 2×.
    func testTheFocusStaysCentredAtEveryZoom() {
        let d = MagnifierGlass.outerDiameter(in: retina)
        let r = MagnifierGlass.glassRadius(outerDiameter: d)
        for z in [MagnifierGlass.minZoom, 3.1, MagnifierGlass.maxZoom] {
            let focus = CGPoint(x: 1200, y: 300)
            let frame = MagnifierGlass.shotFrame(screen: retina, focus: focus, glassRadius: r, zoom: z)
            XCTAssertEqual(frame.minX + focus.x * z, r, accuracy: 0.001, "off centre at \(z)×")
            XCTAssertEqual(frame.minY + focus.y * z, r, accuracy: 0.001, "off centre at \(z)×")
            XCTAssertEqual(frame.width, retina.width * z, accuracy: 0.001)
        }
    }

    /// The canvas has to hold the whole prop — a handle cropped by the edge of
    /// its own image is the failure this catches, and it is invisible in code
    /// because the layer would happily draw the truncated bitmap.
    func testTheCanvasHoldsBothTheLensAndTheHandleTip() {
        let d = MagnifierGlass.outerDiameter(in: retina)
        let canvas = MagnifierGlass.canvasSize(outerDiameter: d)
        let centre = MagnifierGlass.lensCentre(outerDiameter: d)
        let reach = MagnifierGlass.reach(outerDiameter: d)
        let tip = CGPoint(x: centre.x + reach * cos(MagnifierGlass.tiltRadians),
                          y: centre.y + reach * sin(MagnifierGlass.tiltRadians))
        let halfWidest = d * max(MagnifierGlass.ferruleWidthFraction,
                                 MagnifierGlass.handleWidthFraction) / 2

        XCTAssertGreaterThanOrEqual(centre.x - d / 2, 0, "the rim is cropped on the left")
        XCTAssertLessThanOrEqual(centre.y + d / 2, canvas.height, "the rim is cropped at the top")
        XCTAssertLessThanOrEqual(tip.x + halfWidest, canvas.width, "the handle runs off the right edge")
        XCTAssertGreaterThanOrEqual(tip.y - halfWidest, 0, "the handle runs off the bottom edge")
    }

    /// The handle points down and to the right, the way the inspector holds it
    /// on the tile's own artwork.
    func testTheHandleHangsDownAndToTheRight() {
        let d = MagnifierGlass.outerDiameter(in: retina)
        let centre = MagnifierGlass.lensCentre(outerDiameter: d)
        let reach = MagnifierGlass.reach(outerDiameter: d)
        let tip = CGPoint(x: centre.x + reach * cos(MagnifierGlass.tiltRadians),
                          y: centre.y + reach * sin(MagnifierGlass.tiltRadians))
        XCTAssertGreaterThan(tip.x, centre.x)
        XCTAssertLessThan(tip.y, centre.y)   // the layer is y-up: down is smaller
        XCTAssertGreaterThan(reach, d / 2, "the handle does not reach past the rim")
    }

    /// `lensAnchor` is what lets one `position` drive both the lens and the
    /// prop, so it has to be `lensCentre` expressed in the unit square.
    func testTheAnchorIsTheLensCentreInUnitCoordinates() {
        let d = MagnifierGlass.outerDiameter(in: retina)
        let canvas = MagnifierGlass.canvasSize(outerDiameter: d)
        let centre = MagnifierGlass.lensCentre(outerDiameter: d)
        let anchor = MagnifierGlass.lensAnchor(outerDiameter: d)
        XCTAssertEqual(anchor.x * canvas.width, centre.x, accuracy: 0.001)
        XCTAssertEqual(anchor.y * canvas.height, centre.y, accuracy: 0.001)
        // Up and to the left of the middle, because the handle takes the room
        // down and to the right.
        XCTAssertLessThan(anchor.x, 0.5)
        XCTAssertGreaterThan(anchor.y, 0.5)
    }

    /// The prop is drawn, not loaded, so there is no asset to be missing — but
    /// there IS a bitmap to come back empty, and the effect would then show a
    /// magnified desktop with no glass around it.
    func testTheGlassRendersAtTheAskedForSize() throws {
        let d = MagnifierGlass.outerDiameter(in: retina)
        let canvas = MagnifierGlass.canvasSize(outerDiameter: d)
        let image = try XCTUnwrap(MagnifierGlass.image(outerDiameter: d, scale: 2))
        XCTAssertEqual(CGFloat(image.width), (canvas.width * 2).rounded(), accuracy: 1)
        XCTAssertEqual(CGFloat(image.height), (canvas.height * 2).rounded(), accuracy: 1)
    }

    /// The middle of the lens must stay see-through: it is the hole the
    /// magnified desktop shows through, and a fill slipped in there (a glare
    /// drawn unclipped, say) would hide the effect behind its own prop.
    func testTheMiddleOfTheLensIsTransparent() throws {
        let d: CGFloat = 300
        let image = try XCTUnwrap(MagnifierGlass.image(outerDiameter: d, scale: 1))
        let centre = MagnifierGlass.lensCentre(outerDiameter: d)
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        let bytesPerRow = image.bytesPerRow
        // CGImage rows run top-down; the geometry is y-up.
        let row = Int(CGFloat(image.height) - centre.y)
        let alpha = data[row * bytesPerRow + Int(centre.x) * 4 + 3]
        XCTAssertLessThan(alpha, 60, "the glass is not see-through — the desktop under it would be hidden")

        // …while the rim right beside it is solid, which is what proves the
        // sample above landed inside the drawing at all.
        let rimRow = Int(CGFloat(image.height) - centre.y)
        let rimX = Int(centre.x + d / 2 - d * MagnifierGlass.ringFraction / 2)
        XCTAssertGreaterThan(data[rimRow * bytesPerRow + rimX * 4 + 3], 200, "the rim is not opaque")
    }
}
