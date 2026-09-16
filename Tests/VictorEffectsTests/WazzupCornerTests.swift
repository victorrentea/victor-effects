import XCTest
@testable import VictorEffects

/// The same retina-sized overlay the heartbeat tests use — 1512 × 982 points,
/// bottom-origin — so every corner effect is measured on one screen.
private let W: CGFloat = 1512
private let H: CGFloat = 982
private let bounds = CGRect(x: 0, y: 0, width: W, height: H)

/// The cut-out `wazzup.png` is 209 × 271 — taller than it is wide, so HEIGHT is
/// the binding dimension of the box on the retina.
private let maskSize = CGSize(width: 209, height: 271)

final class WazzupCornerTests: XCTestCase {

    func testTheMaskIsFlushToTheBottomLeftCorner() {
        let f = WazzupCorner.frame(imageSize: maskSize, in: bounds)
        XCTAssertEqual(f.minX, 0, accuracy: 0.001, "flush to the left edge")
        XCTAssertEqual(f.minY, 0, accuracy: 0.001, "flush to the bottom edge")
    }

    /// The point of `boxSideFraction`: it is the old fifth-of-the-screen's-area
    /// box (√0.2 per side) scaled 1.2× — Victor's "make it 20 % bigger" read as
    /// 20 % bigger to the eye (per side), not 20 % more area.
    func testTheBoxIsTwentyPercentBiggerPerSideThanTheOldFifthAreaBox() {
        let oldSide = (0.2 as CGFloat).squareRoot()
        XCTAssertEqual(WazzupCorner.boxSideFraction, oldSide * 1.2, accuracy: 1e-9)
    }

    /// Aspect-fit means the mask fills the binding dimension exactly and falls
    /// short on the other — it is never stretched and never overflows the box.
    func testAspectFitKeepsTheMasksShapeInsideTheBox() {
        let f = WazzupCorner.frame(imageSize: maskSize, in: bounds)
        let box = CGSize(width: W * WazzupCorner.boxSideFraction,
                         height: H * WazzupCorner.boxSideFraction)
        XCTAssertEqual(f.height, box.height, accuracy: 0.001, "height binds for a portrait mask")
        XCTAssertLessThan(f.width, box.width)
        XCTAssertEqual(f.width / f.height, maskSize.width / maskSize.height, accuracy: 0.001)
    }

    /// A landscape image would bind on width instead — the same function, no
    /// special case, so re-cropping the asset can never overflow the box.
    func testALandscapeAssetBindsOnWidthInstead() {
        let f = WazzupCorner.frame(imageSize: CGSize(width: 400, height: 100), in: bounds)
        XCTAssertEqual(f.width, W * WazzupCorner.boxSideFraction, accuracy: 0.001)
        XCTAssertLessThan(f.height, H * WazzupCorner.boxSideFraction)
    }

    /// A zero-sized or unreadable image must not produce a NaN frame.
    func testADegenerateImageFallsBackToTheBoxItself() {
        let f = WazzupCorner.frame(imageSize: .zero, in: bounds)
        XCTAssertEqual(f.origin, .zero)
        XCTAssertEqual(f.width, W * WazzupCorner.boxSideFraction, accuracy: 0.001)
    }

    /// The start of the slide must be fully off-screen (right edge exactly at
    /// the left screen edge), not a corner that is still partly visible —
    /// otherwise it would read as a pop-in with a wobble, not a slide.
    func testSlideStartsFullyOffTheLeftEdge() {
        let start = WazzupCorner.slideInStartFrame(imageSize: maskSize, in: bounds)
        XCTAssertEqual(start.maxX, 0, accuracy: 0.001, "right edge flush with the screen's left edge")
    }

    /// The slide is purely horizontal: same size, same vertical position as the
    /// resting frame, shifted left by exactly its own width so it travels the
    /// shortest distance that still starts fully hidden.
    func testSlideStartMatchesTheRestingFrameExceptShiftedLeftByItsWidth() {
        let end = WazzupCorner.frame(imageSize: maskSize, in: bounds)
        let start = WazzupCorner.slideInStartFrame(imageSize: maskSize, in: bounds)
        XCTAssertEqual(start.width, end.width, accuracy: 0.001)
        XCTAssertEqual(start.height, end.height, accuracy: 0.001)
        XCTAssertEqual(start.minY, end.minY, accuracy: 0.001, "purely horizontal, no vertical drift")
        XCTAssertEqual(end.minX - start.minX, end.width, accuracy: 0.001, "travels exactly its own width")
    }

    /// A degenerate image must not turn the slide start into a NaN frame either.
    func testSlideStartIsSafeForADegenerateImage() {
        let start = WazzupCorner.slideInStartFrame(imageSize: .zero, in: bounds)
        XCTAssertFalse(start.minX.isNaN)
        XCTAssertEqual(start.maxX, 0, accuracy: 0.001)
    }

    /// The tablet's tile 69 is what fires this; the mapping is the whole wiring.
    func testTile69IsMappedToTheWazzupEffect() {
        XCTAssertEqual(SoundEffectMap.pressEffect(for: WazzupCorner.soundName), "wazzup")
        XCTAssertNil(SoundEffectMap.stopEffect(for: WazzupCorner.soundName),
                     "nothing loops, so it self-terminates rather than waiting for a stop")
    }
}
