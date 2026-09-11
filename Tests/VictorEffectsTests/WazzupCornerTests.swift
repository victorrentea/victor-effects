import XCTest
@testable import VictorEffects

/// The same retina-sized overlay the heartbeat tests use — 1512 × 982 points,
/// bottom-origin — so every corner effect is measured on one screen.
private let W: CGFloat = 1512
private let H: CGFloat = 982
private let bounds = CGRect(x: 0, y: 0, width: W, height: H)

/// The cut-out `wazzup.png` is 209 × 271 — taller than it is wide, so HEIGHT is
/// the binding dimension of the fifth-area box on the retina.
private let maskSize = CGSize(width: 209, height: 271)

final class WazzupCornerTests: XCTestCase {

    func testTheMaskIsFlushToTheBottomLeftCorner() {
        let f = WazzupCorner.frame(imageSize: maskSize, in: bounds)
        XCTAssertEqual(f.minX, 0, accuracy: 0.001, "flush to the left edge")
        XCTAssertEqual(f.minY, 0, accuracy: 0.001, "flush to the bottom edge")
    }

    /// The point of `boxSideFraction`: the BOX is a fifth of the screen's area,
    /// which is √0.2 of each side and not 0.2 of each side.
    func testTheBoxIsAFifthOfTheScreensArea() {
        let side = WazzupCorner.boxSideFraction
        XCTAssertEqual(side * side, 0.2, accuracy: 1e-9)
        XCTAssertEqual(W * side * H * side, W * H * 0.2, accuracy: 0.01)
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

    /// The tablet's tile 69 is what fires this; the mapping is the whole wiring.
    func testTile69IsMappedToTheWazzupEffect() {
        XCTAssertEqual(SoundEffectMap.pressEffect(for: WazzupCorner.soundName), "wazzup")
        XCTAssertNil(SoundEffectMap.stopEffect(for: WazzupCorner.soundName),
                     "nothing loops, so it self-terminates rather than waiting for a stop")
    }
}
