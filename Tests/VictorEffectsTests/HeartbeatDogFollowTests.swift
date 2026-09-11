import XCTest
@testable import VictorEffects

/// A retina-sized overlay: 1512 × 982 points, bottom-origin.
private let W: CGFloat = 1512
private let H: CGFloat = 982
private let bounds = CGRect(x: 0, y: 0, width: W, height: H)

/// 462 × 524 is the dog at 2/3 of the aspect-fit of half this overlay.
private let box = CGSize(width: 462, height: 524)

/// The lens the dog has to stay out of, for this overlay: ~435 pt.
private let lens = HeartbeatBump.radius(in: bounds)

/// The lens on a screen small enough that the dog cannot simply step aside —
/// it is the old, area-derived radius, kept as a stress case for the fallbacks
/// that the current half-the-height lens no longer reaches.
private let crampedLens: CGFloat = 435

private func face(onRight: Bool, cursor: CGPoint, radius: CGFloat = lens) -> CGPoint {
    HeartbeatDogFollow.facePoint(onRight: onRight, cursor: cursor, boxSize: box,
                                 clearRadius: radius, bounds: bounds)
}

/// Where the near edge of the silhouette ends up, i.e. the ear that has to clear
/// the pulsing disc.
private func nearEdgeX(onRight: Bool, cursor: CGPoint, radius: CGFloat = lens) -> CGFloat {
    let f = face(onRight: onRight, cursor: cursor, radius: radius)
    let near = HeartbeatDogFollow.faceToNearEdge(boxWidth: box.width)
    return onRight ? f.x - near : f.x + near
}

/// How much of the box hangs off either side of the frame.
private func overflow(cursor: CGPoint, radius: CGFloat = lens) -> CGFloat {
    let onRight = HeartbeatDogFollow.shouldBeOnRight(cursorX: cursor.x, wasOnRight: true,
                                                     boundsWidth: W)
    let p = HeartbeatDogFollow.position(onRight: onRight, cursor: cursor, boxSize: box,
                                        clearRadius: radius, bounds: bounds)
    return max(0, box.width / 2 - p.x) + max(0, p.x + box.width / 2 - W)
}

final class HeartbeatDogFollowTests: XCTestCase {

    // MARK: - Which side

    func testCursorOnTheLeftPutsTheDogToItsRight() {
        XCTAssertTrue(HeartbeatDogFollow.shouldBeOnRight(cursorX: 200, wasOnRight: false, boundsWidth: W))
    }

    func testCursorOnTheRightPutsTheDogToItsLeft() {
        XCTAssertFalse(HeartbeatDogFollow.shouldBeOnRight(cursorX: 1300, wasOnRight: true, boundsWidth: W))
    }

    /// The side is asked for once per heartbeat, so the dead band is what
    /// decides a cursor sitting on the seam: the caller passes the side it is
    /// already on (false before the first placement), and that answer stands.
    func testInsideTheDeadBandTheDogKeepsItsSide() {
        let justLeftOfCentre = W / 2 - W * HeartbeatDogFollow.midlineHysteresis / 2
        XCTAssertTrue(HeartbeatDogFollow.shouldBeOnRight(cursorX: justLeftOfCentre,
                                                         wasOnRight: true, boundsWidth: W))
        XCTAssertFalse(HeartbeatDogFollow.shouldBeOnRight(cursorX: justLeftOfCentre,
                                                          wasOnRight: false, boundsWidth: W))
    }

    func testPastTheDeadBandTheDogCommits() {
        let clearlyLeft = W / 2 - W * HeartbeatDogFollow.midlineHysteresis - 1
        XCTAssertTrue(HeartbeatDogFollow.shouldBeOnRight(cursorX: clearlyLeft,
                                                         wasOnRight: false, boundsWidth: W))
        let clearlyRight = W / 2 + W * HeartbeatDogFollow.midlineHysteresis + 1
        XCTAssertFalse(HeartbeatDogFollow.shouldBeOnRight(cursorX: clearlyRight,
                                                          wasOnRight: true, boundsWidth: W))
    }

    // MARK: - The face is what gets parked

    /// The whole inversion in one assertion: the dog is now *beside* the beat,
    /// not on the far half of the screen.
    func testTheFaceSitsAgainstTheBeatNotAcrossTheScreen() {
        let cursor = CGPoint(x: 400, y: H / 2)
        let f = face(onRight: true, cursor: cursor)
        let reach = f.x - cursor.x
        XCTAssertGreaterThan(reach, 0)                    // on its own side of the beat…
        XCTAssertLessThan(reach, lens + box.width / 2)    // …and hugging it
    }

    /// It is the ear, not the face, that the clearance is written around, so the
    /// face is exactly one ear further out than the circle the ear is put on —
    /// and since 2026-09-10 that circle is `closeness` of the strict one.
    func testTheEarLeansInsideTheEdgeOfTheDisc() {
        let cursor = CGPoint(x: 400, y: H / 2)
        let edge = nearEdgeX(onRight: true, cursor: cursor)
        XCTAssertEqual(edge - cursor.x,
                       (lens + HeartbeatDogFollow.clearMargin) * HeartbeatDogFollow.closeness,
                       accuracy: 0.001)
        XCTAssertLessThan(edge - cursor.x, lens)   // 30 % closer means overlapping
    }

    /// The strict "never enters the disc" rule is gone, but the placement is
    /// still a circle: nothing may come closer than `closeness` of it, anywhere.
    func testTheSilhouetteNeverGoesDeeperThanTheClosenessCircle() {
        // Both the lens as it ships and a lens big enough to force every
        // fallback — the placement has to hold on either.
        for radius in [lens, crampedLens] {
            let want = (radius + HeartbeatDogFollow.clearMargin) * HeartbeatDogFollow.closeness
            for x in stride(from: CGFloat(0), through: W, by: 24) {
                for y in stride(from: CGFloat(0), through: H, by: 24) {
                    let cursor = CGPoint(x: x, y: y)
                    let onRight = HeartbeatDogFollow.shouldBeOnRight(cursorX: x, wasOnRight: true,
                                                                     boundsWidth: W)
                    let f = face(onRight: onRight, cursor: cursor, radius: radius)
                    // The corner of the silhouette nearest the beat: near edge
                    // horizontally, ear-top vertically.
                    let corner = CGPoint(x: nearEdgeX(onRight: onRight, cursor: cursor, radius: radius),
                                         y: f.y + HeartbeatDogFollow.faceToTop(boxHeight: box.height))
                    let d = ((corner.x - x) * (corner.x - x) + (corner.y - y) * (corner.y - y)).squareRoot()
                    XCTAssertGreaterThanOrEqual(d, want - 0.001,
                                                "lens \(radius), cursor \(cursor) put the dog too deep into the beat")
                }
            }
        }
    }

    func testThePlacementIsMirroredOnTheOtherSide() {
        let cursor = CGPoint(x: 640, y: 300)
        let mirrored = CGPoint(x: W - 640, y: 300)
        XCTAssertEqual(face(onRight: false, cursor: mirrored).x,
                       W - face(onRight: true, cursor: cursor).x, accuracy: 0.001)
    }

    // MARK: - Height: the face tracks the cursor, the body may leave the frame

    /// Below the bottom anchor the face simply is the cursor's height.
    func testTheFaceRidesAtTheCursorsOwnHeight() {
        let anchor = HeartbeatDogFollow.bottomAnchoredFaceY(boxHeight: box.height)
        for y in stride(from: CGFloat(120), through: anchor, by: 20) {
            XCTAssertEqual(face(onRight: true, cursor: CGPoint(x: 300, y: y)).y, y, accuracy: 0.001)
        }
    }

    /// **The hard rule.** The photo's bottom edge may be below the screen's, never
    /// above it: a gap underneath turns a dog leaning into frame into a sticker
    /// floating in mid-air.
    func testTheBottomOfThePhotoIsNeverAboveTheBottomOfTheScreen() {
        for radius in [lens, crampedLens] {
            for x in stride(from: CGFloat(0), through: W, by: 12) {
                for y in stride(from: CGFloat(0), through: H, by: 12) {
                    let onRight = HeartbeatDogFollow.shouldBeOnRight(cursorX: x, wasOnRight: true,
                                                                     boundsWidth: W)
                    let p = HeartbeatDogFollow.position(onRight: onRight, cursor: CGPoint(x: x, y: y),
                                                        boxSize: box, clearRadius: radius,
                                                        bounds: bounds)
                    XCTAssertLessThanOrEqual(p.y - box.height / 2, 0.001,
                                             "lens \(radius), cursor (\(x), \(y)) floated the dog")
                }
            }
        }
    }

    /// A beat high on the screen does not lift the dog — it pins it to the floor
    /// underneath. The dog does not just hold still, though: standing below the
    /// beat pays for part of the clearance, so it tucks in much closer sideways
    /// than it would beside a beat at its own height.
    func testAHighBeatIsAnsweredBySlidingUnderIt() {
        let low = CGPoint(x: 500, y: 200)
        let high = CGPoint(x: 500, y: H - 100)
        XCTAssertEqual(face(onRight: true, cursor: high).y,
                       HeartbeatDogFollow.bottomAnchoredFaceY(boxHeight: box.height), accuracy: 0.001)
        XCTAssertLessThan(face(onRight: true, cursor: high).x - high.x,
                          face(onRight: true, cursor: low).x - low.x)
    }

    /// The ask, stated as a test: a beat low on the screen is allowed to leave
    /// most of the dog below the bottom edge rather than drag its face upward.
    func testALowBeatPushesTheBodyOffTheBottom() {
        let cursor = CGPoint(x: 300, y: 90)
        let p = HeartbeatDogFollow.position(onRight: true, cursor: cursor, boxSize: box,
                                            clearRadius: lens, bounds: bounds)
        XCTAssertLessThan(p.y - box.height / 2, 0)                  // body below the floor
        XCTAssertEqual(face(onRight: true, cursor: cursor).y, 90, accuracy: 0.001)
    }

    /// …but there is no dog above the ears to crop, so the top is a hard stop.
    func testTheEarsNeverLeaveTheTopOfTheFrame() {
        for y in stride(from: CGFloat(0), through: H, by: 20) {
            let f = face(onRight: true, cursor: CGPoint(x: 300, y: y))
            XCTAssertLessThanOrEqual(f.y + HeartbeatDogFollow.faceToTop(boxHeight: box.height),
                                     H + 0.001)
        }
    }

    func testTheFaceNeverSinksOutOfSight() {
        for x in stride(from: CGFloat(0), through: W, by: 24) {
            for y in stride(from: CGFloat(0), through: H, by: 24) {
                let onRight = HeartbeatDogFollow.shouldBeOnRight(cursorX: x, wasOnRight: true,
                                                                 boundsWidth: W)
                XCTAssertGreaterThanOrEqual(face(onRight: onRight, cursor: CGPoint(x: x, y: y)).y, 0)
            }
        }
    }

    // MARK: - The frame

    /// With the lens as it actually ships — half the screen tall — the dog stays
    /// well inside its overflow budget everywhere. It is not always flat zero:
    /// a beat up in a corner pins the dog to the floor beneath it and lets it
    /// tuck in close, and from there its rump leans a little past the side.
    func testWithTheRealLensTheDogStaysWellInsideItsBudget() {
        var worst: CGFloat = 0
        for x in stride(from: CGFloat(0), through: W, by: 12) {
            for y in stride(from: CGFloat(0), through: H, by: 12) {
                worst = max(worst, overflow(cursor: CGPoint(x: x, y: y)))
            }
        }
        XCTAssertLessThan(worst, box.width * HeartbeatDogFollow.maxBackOverflow / 2)
    }

    /// Squeeze it — a lens the old area rule's size — and the budget starts
    /// being spent, but only at the seam, where neither side has room.
    func testACrampedLensSpendsTheBudgetOnlyAtTheSeam() {
        for x in stride(from: CGFloat(0), through: W, by: 24) {
            guard abs(x - W / 2) > W * HeartbeatDogFollow.midlineHysteresis else { continue }
            for y in stride(from: CGFloat(0), through: H, by: 24) {
                XCTAssertLessThanOrEqual(overflow(cursor: CGPoint(x: x, y: y), radius: crampedLens),
                                         box.width * HeartbeatDogFollow.maxBackOverflow,
                                         "cursor (\(x), \(y)) hung too much of the dog off the edge")
            }
        }
    }

    /// A cursor held on the midline *and* low on the screen, with a lens that
    /// wide, used to be the one case that spent **past** the budget: neither half
    /// had room and there was no sink left, so the dog stepped further out and let
    /// more of its rump go. Pulling the whole placement 30 % closer on 2026-09-10
    /// bought that case back — the emergency sidestep is now unreachable even
    /// there, and the seam merely spends *some* of the budget.
    func testEvenTheSeamNowStaysInsideTheBudget() {
        var worst: CGFloat = 0
        for x in stride(from: CGFloat(0), through: W, by: 8) {
            for y in stride(from: CGFloat(0), through: H, by: 8) {
                worst = max(worst, overflow(cursor: CGPoint(x: x, y: y), radius: crampedLens))
            }
        }
        XCTAssertGreaterThan(worst, 0)
        XCTAssertLessThanOrEqual(worst, box.width * HeartbeatDogFollow.maxBackOverflow)
    }

    /// The one hard stop of the emergency sidestep: whatever else gets cropped,
    /// the face has to be on the screen.
    func testTheFaceIsAlwaysInsideTheFrame() {
        for x in stride(from: CGFloat(0), through: W, by: 24) {
            for y in stride(from: CGFloat(0), through: H, by: 24) {
                let onRight = HeartbeatDogFollow.shouldBeOnRight(cursorX: x, wasOnRight: true,
                                                                 boundsWidth: W)
                let f = face(onRight: onRight, cursor: CGPoint(x: x, y: y))
                XCTAssertGreaterThanOrEqual(f.x, 0)
                XCTAssertLessThanOrEqual(f.x, W)
                XCTAssertLessThanOrEqual(f.y, H)
            }
        }
    }

    /// The mirror flips which end of the box the face is at, so the layer centre
    /// lands on opposite sides of the same face point.
    func testTheFaceOffsetFlipsWithTheDog() {
        let left = HeartbeatDogFollow.faceOffset(onRight: false, boxSize: box)
        let right = HeartbeatDogFollow.faceOffset(onRight: true, boxSize: box)
        XCTAssertEqual(left.dx, -right.dx, accuracy: 0.001)
        XCTAssertEqual(left.dy, right.dy, accuracy: 0.001)
        XCTAssertGreaterThan(left.dy, 0)          // the face is above the box's centre
    }

    func testPositionAndFacePointAgree() {
        let cursor = CGPoint(x: 500, y: 400)
        let p = HeartbeatDogFollow.position(onRight: true, cursor: cursor, boxSize: box,
                                            clearRadius: lens, bounds: bounds)
        let o = HeartbeatDogFollow.faceOffset(onRight: true, boxSize: box)
        let f = face(onRight: true, cursor: cursor)
        XCTAssertEqual(p.x + o.dx, f.x, accuracy: 0.001)
        XCTAssertEqual(p.y + o.dy, f.y, accuracy: 0.001)
    }

    func testADogWiderThanTheScreenIsSimplyCentred() {
        let huge = CGSize(width: W * 1.5, height: box.height)
        XCTAssertEqual(HeartbeatDogFollow.facePoint(onRight: true, cursor: CGPoint(x: 100, y: 400),
                                                    boxSize: huge, clearRadius: lens,
                                                    bounds: bounds).x, W / 2)
    }
}
