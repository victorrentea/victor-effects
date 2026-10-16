import AppKit
import QuartzCore
import XCTest
@testable import VictorEffects

/// 🔍 Effects drawn AT THE POINTER under macOS ⌥-scroll zoom: each is drawn
/// 1/zoom the size, about the pointer, so the magnification brings it back to
/// exactly its unzoomed size ("I never want to zoom into an effect"). No
/// capture can show system zoom (it photographs the unzoomed framebuffer), so
/// what is checked here is the arithmetic each effect leans on — and that
/// every one of them is the identity at rest.
final class PointerZoomTests: XCTestCase {

    private let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    /// What 2× zoom shows of it, somewhere off-centre.
    private let slice2x = CGRect(x: 700, y: 400, width: 864, height: 558.5)

    // MARK: - Sprites riding the pointer (😱, ❤️, 🔥 ball, 🔫 crosshair)

    func testAGlyphAtThePointerIsHalvedAt2xAndUntouchedAtRest() {
        let glyph = CATextLayer()
        let box = CGSize(width: 200, height: 200)
        EmojiAnimator.fitPointerGlyph(glyph, fontSize: 166, box: box, factor: 2)
        XCTAssertEqual(glyph.fontSize, 83)
        XCTAssertEqual(glyph.bounds.size, CGSize(width: 100, height: 100))

        EmojiAnimator.fitPointerGlyph(glyph, fontSize: 166, box: box, factor: 1)
        XCTAssertEqual(glyph.fontSize, 166)
        XCTAssertEqual(glyph.bounds.size, box)
    }

    func testASpriteAtThePointerKeepsItsAspectAndItsAnchor() {
        let ball = CALayer()
        ball.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        ball.position = CGPoint(x: 400, y: 300)
        EmojiAnimator.fitPointerSprite(ball, base: CGSize(width: 180, height: 240), factor: 3)
        XCTAssertEqual(ball.bounds.width, 60, accuracy: 1e-9)
        XCTAssertEqual(ball.bounds.height, 80, accuracy: 1e-9)
        XCTAssertEqual(ball.position, CGPoint(x: 400, y: 300), "still centred on the pointer")
    }

    func testTheCrosshairScalesThroughItsOwnTransformAndIsIdentityAtRest() {
        let reticle = EmojiAnimator.makeSniperReticle(scale: EmojiAnimator.minigunReticleScale, armed: true)
        EmojiAnimator.fitPointerReticle(reticle, factor: 2)
        XCTAssertEqual(reticle.transform.m11, 0.5)
        XCTAssertEqual(reticle.transform.m22, 0.5)
        EmojiAnimator.fitPointerReticle(reticle, factor: 1)
        XCTAssertTrue(CATransform3DIsIdentity(reticle.transform))
    }

    /// The holes are shot at the crosshair's size, so "every hole whole inside
    /// the red ring" survives the zoom: the unzoomed spread scaled by 1/zoom is
    /// exactly the spread for a 1/zoom ring and a 1/zoom hole.
    func testMinigunHolesStayInsideTheShrunkRing() {
        let hole = CGSize(width: 43, height: 43)
        let s = ScreenZoom.counterScale(for: 4)
        let ring = EmojiAnimator.sniperReticleRingRadius(scale: EmojiAnimator.minigunReticleScale) * s
        let spread = EmojiAnimator.minigunSpreadRadius(holeSize: hole) * s
        XCTAssertLessThanOrEqual(spread + hole.width * s / 2, ring + 1e-9)
        XCTAssertGreaterThan(spread, 0, "at 4× a burst still scatters")
    }

    // MARK: - 🔍 The magnifier

    /// The lens is drawn 1/zoom, picture included, and the desktop around it is
    /// magnified by the zoom: the picture inside must be blown up by the zoom
    /// on top of the lens's own power, or a 2× lens at 2× screen zoom would
    /// show the desktop at the size it already has around it.
    func testTheLensKeepsItsPowerRelativeToTheMagnifiedDesktop() {
        XCTAssertEqual(EmojiAnimator.magnifierShotZoom(2, screenZoom: 1), 2)
        XCTAssertEqual(EmojiAnimator.magnifierShotZoom(2, screenZoom: 1.005), 2, "rest is rest")
        XCTAssertEqual(EmojiAnimator.magnifierShotZoom(2, screenZoom: 2), 4)
        // On the glass: shot zoom × stage (1/zoom) × screen zoom ÷ screen zoom
        // (what the surroundings get) = the lens's own power.
        let shot = EmojiAnimator.magnifierShotZoom(3, screenZoom: 2.5)
        XCTAssertEqual(shot * ScreenZoom.counterScale(for: 2.5), 3, accuracy: 1e-9)
    }

    // MARK: - ☢️ The bombs

    /// An aimed strike is sized on the slice on the glass: half the blast and
    /// half the fall speed at 2×, still anchored on the click.
    func testAnAimedStrikeIsSizedOnTheSliceAndStillLandsOnTheClick() {
        let click = CGPoint(x: 1000, y: 600)
        let rest = EmojiAnimator.bombBlastFrame(in: display, fullScreen: false, at: click)
        let zoomed = EmojiAnimator.bombBlastFrame(in: slice2x, fullScreen: false, at: click)
        XCTAssertEqual(zoomed.width, rest.width / 2, accuracy: 1e-9)
        XCTAssertEqual(zoomed.midX, click.x, accuracy: 1e-9)
        XCTAssertEqual(zoomed.minY + zoomed.height * EmojiAnimator.bombImpactFractionFromBottom,
                       click.y, accuracy: 1e-9)
        XCTAssertEqual(EmojiAnimator.bombFallSpeed(in: slice2x),
                       EmojiAnimator.bombFallSpeed(in: display) / 2, accuracy: 1e-6)
    }

    /// `bombBlastFrame` honours the rect's origin now, so the nuke's geometry
    /// laid out on a slice is the display's, moved and shrunk into it — and
    /// unchanged for the display itself (origin zero).
    func testTheNukeGeometryFollowsTheRectItIsGiven() {
        let rest = EmojiAnimator.bombBlastFrame(in: display, fullScreen: true, at: .zero)
        let zoomed = EmojiAnimator.bombBlastFrame(in: slice2x, fullScreen: true, at: .zero)
        XCTAssertEqual(zoomed.width, rest.width / 2, accuracy: 1e-9)
        XCTAssertEqual(zoomed.midX - slice2x.minX, (rest.midX - display.minX) / 2, accuracy: 1e-9)
        XCTAssertEqual(zoomed.minY - slice2x.minY, (rest.minY - display.minY) / 2, accuracy: 1e-9)
        let impact = EmojiAnimator.bombBlastImpactPoint(in: slice2x, fullScreen: true, at: .zero)
        XCTAssertTrue(slice2x.contains(impact))
    }
}
