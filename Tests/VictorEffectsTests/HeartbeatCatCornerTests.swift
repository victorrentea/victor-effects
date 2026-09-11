import XCTest
@testable import VictorEffects

/// The same retina-sized overlay `HeartbeatBumpTests` and `HeartbeatDogFollowTests`
/// use — 1512 × 982 points, bottom-origin — so the three read as one effect.
private let W: CGFloat = 1512
private let H: CGFloat = 982
private let bounds = CGRect(x: 0, y: 0, width: W, height: H)

/// The cropped `scared_cat.gif` is 486 × 346 — wider than the half-screen box is
/// tall relative to its width, so width is the binding dimension on the retina.
private let catSize = CGSize(width: 486, height: 346)

final class HeartbeatCatCornerTests: XCTestCase {

    func testTheCatSitsInTheBottomLeftCornerWhenTheMouseIsOnTheRight() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds, onRight: false)
        XCTAssertEqual(f.minX, 0, accuracy: 0.001, "flush to the left edge")
    }

    /// A mouse in the LEFT half sends the cat to the far corner, flush to the
    /// right edge — it never sits under the pointer, i.e. under the lens.
    func testAMouseInTheLeftHalfSendsTheCatToTheRightCorner() {
        XCTAssertTrue(HeartbeatCatCorner.onRight(cursorX: 1, boundsWidth: W))
        XCTAssertTrue(HeartbeatCatCorner.onRight(cursorX: W / 2 - 1, boundsWidth: W))
        XCTAssertFalse(HeartbeatCatCorner.onRight(cursorX: W / 2 + 1, boundsWidth: W))
        XCTAssertFalse(HeartbeatCatCorner.onRight(cursorX: W - 1, boundsWidth: W))

        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds, onRight: true)
        XCTAssertEqual(f.maxX, W, accuracy: 0.001, "flush to the right edge")
    }

    /// Only the right-hand cat is mirrored, so it faces the same way relative to
    /// whichever corner it is standing in.
    func testOnlyTheRightHandCatIsMirrored() {
        XCTAssertTrue(CATransform3DIsIdentity(HeartbeatCatCorner.facing(onRight: false)))
        XCTAssertEqual(HeartbeatCatCorner.facing(onRight: true).m11, -1, accuracy: 0.001)
        XCTAssertEqual(HeartbeatCatCorner.facing(onRight: true).m22, 1, accuracy: 0.001)
    }

    /// The cat is sunk below the floor of the screen so the tail can run off the
    /// edge — a deliberate clip, not a placement to clamp back up.
    func testTheCatIsSunkBelowTheBottomEdge() {
        for right in [false, true] {
            let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds, onRight: right)
            XCTAssertLessThan(f.minY, 0, "the tail pokes below the screen edge")
            XCTAssertEqual(f.minY, -f.height * HeartbeatCatCorner.sinkFraction, accuracy: 0.001)
        }
    }

    func testTheBoxIsAQuarterOfTheScreenArea() {
        let box = (W * HeartbeatCatCorner.boxWidthFraction) * (H * HeartbeatCatCorner.boxHeightFraction)
        XCTAssertEqual(box / (W * H), 0.25, accuracy: 1e-9)
    }

    func testItFitsInsideTheScaledBoxAndKeepsItsAspectRatio() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds, onRight: false)
        XCTAssertLessThanOrEqual(f.width, W / 2 * HeartbeatCatCorner.scale + 0.001)
        XCTAssertLessThanOrEqual(f.height, H / 2 * HeartbeatCatCorner.scale + 0.001)
        XCTAssertEqual(f.width / f.height, catSize.width / catSize.height, accuracy: 0.001)
    }

    /// The real asset (1.40) is squarer than the retina's half-box (756 × 491 =
    /// 1.54), so **height** is what binds; at 0.7 of that fit the cat draws
    /// ~483 × 344 — the size Victor asked for on 2026-09-11.
    func testTheRealCatIsBoundByTheBoxHeightAndTakenDownByTheScale() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds, onRight: false)
        XCTAssertEqual(f.height, H / 2 * HeartbeatCatCorner.scale, accuracy: 0.001)
        XCTAssertEqual(f.width, 482.77, accuracy: 0.5)
        XCTAssertEqual(f.height, 343.7, accuracy: 0.5)
    }

    /// A wider-than-the-box asset is limited by the width instead — still
    /// cornered, still whole, never cropped to fill.
    func testAVeryWideCatIsBoundByTheBoxWidth() {
        let f = HeartbeatCatCorner.frame(imageSize: CGSize(width: 1600, height: 400), in: bounds, onRight: false)
        XCTAssertEqual(f.width, W / 2 * HeartbeatCatCorner.scale, accuracy: 0.001)
        XCTAssertLessThan(f.height, H / 2 * HeartbeatCatCorner.scale)
        XCTAssertEqual(f.minX, 0, accuracy: 0.001)
    }

    func testADegenerateImageStillProducesTheBox() {
        let f = HeartbeatCatCorner.frame(imageSize: .zero, in: bounds, onRight: false)
        XCTAssertEqual(f, CGRect(x: 0, y: 0, width: W / 2, height: H / 2))
    }

    // MARK: - The alternation

    /// Run 1 dog, run 2 cat, run 3 dog — the first run of a cold start is the
    /// dog, which is what makes the cat read as the variation.
    func testTheCompanionAlternatesStartingWithTheDog() {
        HeartbeatCompanion.resetForTesting()
        XCTAssertEqual(HeartbeatCompanion.next(), .dog)
        XCTAssertEqual(HeartbeatCompanion.next(), .cat)
        XCTAssertEqual(HeartbeatCompanion.next(), .dog)
        XCTAssertEqual(HeartbeatCompanion.next(), .cat)
    }
}
