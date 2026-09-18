import XCTest
@testable import VictorEffects

/// The same retina-sized overlay `HeartbeatBumpTests` and `HeartbeatDogFollowTests`
/// use — 1512 × 982 points, bottom-origin — so the three read as one effect.
private let W: CGFloat = 1512
private let H: CGFloat = 982
private let bounds = CGRect(x: 0, y: 0, width: W, height: H)

/// The cropped `scared_cat.gif` is 486 × 346 — squarer than the half-screen box,
/// so height is the binding dimension on the retina.
private let catSize = CGSize(width: 486, height: 346)

/// The cat as it is actually drawn here: ≈ 724 × 516 since the 1.5× of
/// 2026-09-19, its top edge ≈ 469 above the floor once the sink is taken off.
private let drawn = HeartbeatCatFollow.size(imageSize: catSize, in: bounds)
private let gap = HeartbeatCatFollow.nearGap(in: bounds)
private let top = HeartbeatCatFollow.topY(height: drawn.height)

/// A beat low enough that the cat's top corner is not below it at all, so the
/// whole clearance has to be paid sideways.
private let lowBeat: CGFloat = 100
/// A beat high enough that standing on the floor already pays the whole
/// clearance — the cat may then walk in directly underneath it.
private let highBeat: CGFloat = top + gap + 50

final class HeartbeatCatFollowTests: XCTestCase {

    // MARK: - Which side

    /// A mouse in the LEFT half puts the cat on the beat's right — it leans in
    /// from the roomy side rather than standing on the pointer. Asked once, at
    /// the first poll, and then kept: the mirror is baked into the layer.
    func testAMouseInTheLeftHalfPutsTheCatOnTheRight() {
        XCTAssertTrue(HeartbeatCatFollow.onRight(cursorX: 1, boundsWidth: W))
        XCTAssertTrue(HeartbeatCatFollow.onRight(cursorX: W / 2 - 1, boundsWidth: W))
        XCTAssertFalse(HeartbeatCatFollow.onRight(cursorX: W / 2 + 1, boundsWidth: W))
        XCTAssertFalse(HeartbeatCatFollow.onRight(cursorX: W - 1, boundsWidth: W))
    }

    /// Only the right-hand cat is mirrored, so it faces the same way relative to
    /// the edge it came from.
    func testOnlyTheRightHandCatIsMirrored() {
        XCTAssertTrue(CATransform3DIsIdentity(HeartbeatCatFollow.facing(onRight: false)))
        XCTAssertEqual(HeartbeatCatFollow.facing(onRight: true).m11, -1, accuracy: 0.001)
        XCTAssertEqual(HeartbeatCatFollow.facing(onRight: true).m22, 1, accuracy: 0.001)
    }

    // MARK: - The distance to the beat

    /// The cat stands on the dog's circle, not on a circle of its own — that is
    /// what "a similar distance to the dog's" was asked for on 2026-09-14, and
    /// the only way to keep it true is to read the dog's own constants.
    func testTheClearanceIsTheDogsOwnCircle() {
        XCTAssertEqual(gap,
                       (HeartbeatBump.radius(in: bounds) + HeartbeatDogFollow.clearMargin)
                           * HeartbeatDogFollow.closeness,
                       accuracy: 0.001)
        XCTAssertLessThan(gap, HeartbeatBump.radius(in: bounds),
                          "leaning into the ring, not standing aside from it")
    }

    /// A beat down near the floor: the cat is level with it, so nothing is paid
    /// by standing below and the near edge lands the full gap away.
    func testALowBeatPaysTheWholeClearanceSideways() {
        let f = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds, onRight: false,
                                         cursor: CGPoint(x: W - 1, y: lowBeat))
        XCTAssertEqual(f.maxX, W - 1 - gap, accuracy: 0.001)

        let g = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds, onRight: true,
                                         cursor: CGPoint(x: 1, y: lowBeat))
        XCTAssertEqual(g.minX, 1 + gap, accuracy: 0.001)
    }

    /// A beat high on the screen: the cat is already a whole clearance below it,
    /// so it walks in until its near edge is under the beat — the dog's trade,
    /// with the cat's floor standing in for the dog's sunk body.
    func testAHighBeatLetsTheCatWalkInUnderneathIt() {
        let f = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds, onRight: false,
                                         cursor: CGPoint(x: W - 1, y: highBeat))
        XCTAssertEqual(f.maxX, W - 1, accuracy: 0.001, "straight under the beat")

        let g = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds, onRight: true,
                                         cursor: CGPoint(x: 1, y: highBeat))
        XCTAssertEqual(g.minX, 1, accuracy: 0.001)
    }

    /// Between the two: the near TOP corner is what sits on the circle, so the
    /// higher the beat the closer in the cat tucks — monotonically, never a jump.
    func testTheNearCornerStaysOnTheCircleAndTheCatTucksInAsTheBeatRises() {
        var previousGap = CGFloat.greatestFiniteMagnitude
        for y in stride(from: lowBeat, through: highBeat, by: 20) {
            let cursor = CGPoint(x: W - 1, y: y)
            let f = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds,
                                             onRight: false, cursor: cursor)
            let dx = cursor.x - f.maxX
            let dy = max(0, cursor.y - f.maxY)
            let distance = (dx * dx + dy * dy).squareRoot()
            if dy <= gap {
                XCTAssertEqual(distance, gap, accuracy: 0.5,
                               "near top corner on the clearance circle at y = \(y)")
            } else {
                // Past that height the drop alone is more than the clearance, and
                // the cat cannot climb to give any of it back: it just stands
                // directly under the beat, further away than the circle asks.
                XCTAssertEqual(dx, 0, accuracy: 0.001, "straight under the beat at y = \(y)")
                XCTAssertGreaterThan(distance, gap)
            }
            XCTAssertLessThanOrEqual(dx, previousGap + 0.001, "tucking in, never stepping back out")
            previousGap = dx
        }
    }

    /// Whatever the beat does, the cat stays on the screen sideways — the frame
    /// beats the gap. Only the bottom edge is allowed to clip it.
    func testTheCatNeverWalksOffTheSideOfTheScreen() {
        for right in [false, true] {
            for x in stride(from: CGFloat(0), through: W, by: 37) {
                for y in stride(from: CGFloat(0), through: H, by: 61) {
                    let f = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds,
                                                     onRight: right,
                                                     cursor: CGPoint(x: x, y: y))
                    XCTAssertGreaterThanOrEqual(f.minX, -0.001)
                    XCTAssertLessThanOrEqual(f.maxX, W + 0.001)
                }
            }
        }
    }

    /// The clamp in the other direction: a beat close to the cat's own edge
    /// cannot push it off the screen, it just parks it flush in the corner —
    /// which is where the cat spent its first three days.
    func testABeatCloseToTheEdgeParksTheCatFlushInTheCorner() {
        let f = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds, onRight: false,
                                         cursor: CGPoint(x: 300, y: lowBeat))
        XCTAssertEqual(f.minX, 0, accuracy: 0.001)

        let g = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds, onRight: true,
                                         cursor: CGPoint(x: W - 300, y: lowBeat))
        XCTAssertEqual(g.maxX, W, accuracy: 0.001)
    }

    // MARK: - Height and size

    /// The cat is sunk below the floor of the screen so the tail can run off the
    /// edge — a deliberate clip, not a placement to clamp back up. The beat's own
    /// height never lifts it: unlike the dog, the cat stays on the floor.
    func testTheCatIsSunkBelowTheBottomEdgeWhereverTheBeatIs() {
        for right in [false, true] {
            for y in [lowBeat, H / 2, highBeat] {
                let f = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds, onRight: right,
                                                 cursor: CGPoint(x: W / 2, y: y))
                XCTAssertLessThan(f.minY, 0, "the tail pokes below the screen edge")
                XCTAssertEqual(f.minY, -f.height * HeartbeatCatFollow.sinkFraction, accuracy: 0.001)
            }
        }
    }

    func testTheBoxIsAQuarterOfTheScreenArea() {
        let box = (W * HeartbeatCatFollow.boxWidthFraction) * (H * HeartbeatCatFollow.boxHeightFraction)
        XCTAssertEqual(box / (W * H), 0.25, accuracy: 1e-9)
    }

    func testItFitsInsideTheScaledBoxAndKeepsItsAspectRatio() {
        let f = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds, onRight: false,
                                         cursor: CGPoint(x: W - 1, y: lowBeat))
        XCTAssertLessThanOrEqual(f.width, W / 2 * HeartbeatCatFollow.scale + 0.001)
        XCTAssertLessThanOrEqual(f.height, H / 2 * HeartbeatCatFollow.scale + 0.001)
        XCTAssertEqual(f.width / f.height, catSize.width / catSize.height, accuracy: 0.001)
    }

    /// The real asset (1.40) is squarer than the retina's half-box (756 × 491 =
    /// 1.54), so **height** is what binds; at 1.05 of that fit the cat draws
    /// ~724 × 516. The numbers are pinned rather than recomputed on purpose: the
    /// scale has been asked for four times now (0.7 → 1.4 → 0.7 → 1.05), and a
    /// test that only re-derives the formula would have passed every time.
    func testTheRealCatIsBoundByTheBoxHeightAndTakenDownByTheScale() {
        XCTAssertEqual(drawn.height, H / 2 * HeartbeatCatFollow.scale, accuracy: 0.001)
        XCTAssertEqual(drawn.width, 724.15, accuracy: 0.5)
        XCTAssertEqual(drawn.height, 515.55, accuracy: 0.5)
    }

    /// A wider-than-the-box asset is limited by the width instead — still whole,
    /// never cropped to fill.
    func testAVeryWideCatIsBoundByTheBoxWidth() {
        let s = HeartbeatCatFollow.size(imageSize: CGSize(width: 1600, height: 400), in: bounds)
        XCTAssertEqual(s.width, W / 2 * HeartbeatCatFollow.scale, accuracy: 0.001)
        XCTAssertLessThan(s.height, H / 2 * HeartbeatCatFollow.scale)
    }

    func testADegenerateImageStillProducesTheBox() {
        let f = HeartbeatCatFollow.frame(imageSize: .zero, in: bounds, onRight: false,
                                         cursor: CGPoint(x: W / 2, y: H / 2))
        XCTAssertEqual(f, CGRect(x: 0, y: 0, width: W / 2, height: H / 2))
    }

    /// The layer is positioned by its centre, and the mirror is a scale about
    /// that same centre — so `position` is just the frame's midpoint, whichever
    /// side the cat is on.
    func testThePositionIsTheFramesCentre() {
        for right in [false, true] {
            let cursor = CGPoint(x: right ? 200 : W - 200, y: H / 3)
            let f = HeartbeatCatFollow.frame(imageSize: catSize, in: bounds,
                                             onRight: right, cursor: cursor)
            let p = HeartbeatCatFollow.position(size: drawn, in: bounds,
                                                onRight: right, cursor: cursor)
            XCTAssertEqual(p.x, f.midX, accuracy: 0.001)
            XCTAssertEqual(p.y, f.midY, accuracy: 0.001)
        }
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
