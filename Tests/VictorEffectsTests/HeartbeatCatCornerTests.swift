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

    /// A beat just past the midline is already as close as the cat can get
    /// without leaving the screen, so the slide bottoms out at the old placement:
    /// flush to the far corner.
    func testTheCatFallsBackToTheCornerWhenTheBeatIsNearTheMiddle() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds,
                                         onRight: false, cursorX: W / 2 + 1)
        XCTAssertEqual(f.minX, 0, accuracy: 0.001, "flush to the left edge")

        let g = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds,
                                         onRight: true, cursorX: W / 2 - 1)
        XCTAssertEqual(g.maxX, W, accuracy: 0.001, "flush to the right edge")
    }

    /// The point of 2026-09-14: a beat out at the far edge no longer leaves the
    /// cat parked a screen away. It slides along the floor until its near edge is
    /// `nearGap` from the beat — and `nearGap` is under the lens radius, so the
    /// cat leans into the ring exactly as much as the dog does.
    func testTheCatSlidesAlongTheFloorTowardTheBeat() {
        let gap = HeartbeatCatCorner.nearGap(in: bounds)
        XCTAssertLessThan(gap, HeartbeatBump.radius(in: bounds), "leaning in, not standing aside")

        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds,
                                         onRight: false, cursorX: W - 1)
        XCTAssertGreaterThan(f.minX, 0, "no longer flush to the corner")
        XCTAssertEqual(f.maxX, W - 1 - gap, accuracy: 0.001, "near edge on the gap")

        let g = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds,
                                         onRight: true, cursorX: 1)
        XCTAssertLessThan(g.maxX, W, "no longer flush to the corner")
        XCTAssertEqual(g.minX, 1 + gap, accuracy: 0.001, "near edge on the gap")
    }

    /// Whatever the beat does, the cat stays on the screen sideways — the frame
    /// beats the gap. Only the bottom edge is allowed to clip it.
    func testTheCatNeverWalksOffTheSideOfTheScreen() {
        for right in [false, true] {
            for cursorX in stride(from: CGFloat(0), through: W, by: 37) {
                let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds,
                                                 onRight: right, cursorX: cursorX)
                XCTAssertGreaterThanOrEqual(f.minX, -0.001)
                XCTAssertLessThanOrEqual(f.maxX, W + 0.001)
            }
        }
    }

    /// A mouse in the LEFT half puts the cat on the beat's right — it leans in
    /// from the roomy side rather than standing on the pointer.
    func testAMouseInTheLeftHalfPutsTheCatOnTheRight() {
        XCTAssertTrue(HeartbeatCatCorner.onRight(cursorX: 1, boundsWidth: W))
        XCTAssertTrue(HeartbeatCatCorner.onRight(cursorX: W / 2 - 1, boundsWidth: W))
        XCTAssertFalse(HeartbeatCatCorner.onRight(cursorX: W / 2 + 1, boundsWidth: W))
        XCTAssertFalse(HeartbeatCatCorner.onRight(cursorX: W - 1, boundsWidth: W))
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
            let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds,
                                             onRight: right, cursorX: W / 2)
            XCTAssertLessThan(f.minY, 0, "the tail pokes below the screen edge")
            XCTAssertEqual(f.minY, -f.height * HeartbeatCatCorner.sinkFraction, accuracy: 0.001)
        }
    }

    func testTheBoxIsAQuarterOfTheScreenArea() {
        let box = (W * HeartbeatCatCorner.boxWidthFraction) * (H * HeartbeatCatCorner.boxHeightFraction)
        XCTAssertEqual(box / (W * H), 0.25, accuracy: 1e-9)
    }

    func testItFitsInsideTheScaledBoxAndKeepsItsAspectRatio() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds,
                                         onRight: false, cursorX: W - 1)
        XCTAssertLessThanOrEqual(f.width, W / 2 * HeartbeatCatCorner.scale + 0.001)
        XCTAssertLessThanOrEqual(f.height, H / 2 * HeartbeatCatCorner.scale + 0.001)
        XCTAssertEqual(f.width / f.height, catSize.width / catSize.height, accuracy: 0.001)
    }

    /// The real asset (1.40) is squarer than the retina's half-box (756 × 491 =
    /// 1.54), so **height** is what binds; at 1.4 of that fit the cat draws
    /// ~966 × 687 — twice the ~483 × 344 it drew until 2026-09-14, linearly.
    func testTheRealCatIsBoundByTheBoxHeightAndScaledByTheScale() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds,
                                         onRight: false, cursorX: W - 1)
        XCTAssertEqual(f.height, H / 2 * HeartbeatCatCorner.scale, accuracy: 0.001)
        XCTAssertEqual(f.width, 965.53, accuracy: 0.5)
        XCTAssertEqual(f.height, 687.4, accuracy: 0.5)
    }

    /// A wider-than-the-box asset is limited by the width instead — still
    /// cornered, still whole, never cropped to fill.
    func testAVeryWideCatIsBoundByTheBoxWidth() {
        let f = HeartbeatCatCorner.frame(imageSize: CGSize(width: 1600, height: 400),
                                         in: bounds, onRight: false, cursorX: W / 2)
        XCTAssertEqual(f.width, W / 2 * HeartbeatCatCorner.scale, accuracy: 0.001)
        XCTAssertLessThan(f.height, H / 2 * HeartbeatCatCorner.scale)
        XCTAssertEqual(f.minX, 0, accuracy: 0.001, "wider than the screen: the frame wins")
    }

    func testADegenerateImageStillProducesTheBox() {
        let f = HeartbeatCatCorner.frame(imageSize: .zero, in: bounds,
                                         onRight: false, cursorX: W / 2)
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
