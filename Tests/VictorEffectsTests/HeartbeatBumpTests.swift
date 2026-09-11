import XCTest
@testable import VictorEffects

/// A retina-sized overlay: 1512 × 982 points, bottom-origin — the same one
/// `HeartbeatDogFollowTests` uses, so the two read as one effect.
private let W: CGFloat = 1512
private let H: CGFloat = 982

final class HeartbeatBumpTests: XCTestCase {

    // The size, as Victor last pinned it: half the screen tall, then asked 20 %
    // larger — three fifths of the screen TALL. Stated against the height alone
    // — the width deliberately plays no part, which is the whole reason the old
    // area formula was dropped.
    func testLensDiameterIsThreeFifthsOfTheScreenHeight() {
        let r = HeartbeatBump.radius(in: CGRect(x: 0, y: 0, width: W, height: H))
        XCTAssertEqual(2 * r, H * HeartbeatBump.diameterFraction, accuracy: 0.0001)
        XCTAssertEqual(2 * r, H * 0.6, accuracy: 0.0001)
    }

    // The 20 % was asked for as a size, so it is 20 % on the diameter — not on
    // the area, which grows 44 %, and not on the amplitude, which is untouched.
    func testTheLensGrewByAFifthOverTheHalfHeightItReplaced() {
        let r = HeartbeatBump.radius(in: CGRect(x: 0, y: 0, width: W, height: H))
        XCTAssertEqual(2 * r, (H / 2) * 1.2, accuracy: 0.0001)
    }

    // …stated as a plain number too, so a future tweak has to face what the lens
    // actually looks like on the screen it runs on.
    func testLensRadiusOnTheRetina() {
        let r = HeartbeatBump.radius(in: CGRect(x: 0, y: 0, width: W, height: H))
        XCTAssertEqual(r, 294.6, accuracy: 0.1)
        // Still a lens, not the whole screen: a still margin survives all round.
        XCTAssertLessThan(2 * r, H)
        XCTAssertLessThan(2 * r, W)
    }

    // The point of anchoring on the height: a wide external monitor and the
    // built-in retina get the SAME lens, where the old area rule stretched it
    // with the aspect ratio.
    func testTheLensIgnoresHowWideTheScreenIs() {
        let tall = CGRect(x: 0, y: 0, width: W, height: H)
        let wide = CGRect(x: 0, y: 0, width: W * 2, height: H)
        XCTAssertEqual(HeartbeatBump.radius(in: tall), HeartbeatBump.radius(in: wide))
    }

    // …and it grew without getting punchier: `inputScale` is relative to the
    // radius, so the convexity constant must stay exactly where it was.
    func testAmplitudeWasNotTouchedWhenTheLensGrew() {
        XCTAssertEqual(HeartbeatBump.peakScale, 0.5, accuracy: 0.0001)
    }

    // A degenerate overlay (no screen yet) must not produce a NaN radius that
    // would poison CIBumpDistortion.
    func testEmptyBoundsGiveNoLens() {
        XCTAssertEqual(HeartbeatBump.radius(in: .zero), 0)
    }

    // The lens sits exactly on the cursor: the anchor is the unit-square mouse
    // position `layerAnchor(forGlobalMouse:…)` hands over.
    func testCentreFollowsTheCursorAnchor() {
        let bounds = CGRect(x: 0, y: 0, width: W, height: H)
        XCTAssertEqual(HeartbeatBump.center(forAnchor: CGPoint(x: 0.5, y: 0.5), bounds: bounds),
                       CGPoint(x: 756, y: 491))
        XCTAssertEqual(HeartbeatBump.center(forAnchor: CGPoint(x: 0.25, y: 0.75), bounds: bounds),
                       CGPoint(x: 378, y: 736.5))
    }

    // Not clamped inward: a cursor in the corner gets a corner lens, not one
    // that has slid off the pointer to keep its whole circle on screen.
    func testCornerCursorKeepsTheLensOnTheCorner() {
        let bounds = CGRect(x: 0, y: 0, width: W, height: H)
        XCTAssertEqual(HeartbeatBump.center(forAnchor: .zero, bounds: bounds), .zero)
        XCTAssertEqual(HeartbeatBump.center(forAnchor: CGPoint(x: 1, y: 1), bounds: bounds),
                       CGPoint(x: W, y: H))
    }

    // The periphery is the whole complaint this change answers. The old effect
    // scaled everything by 1.30 around the cursor; what is left is a breathe
    // small enough that the far corner travels under 20 pt.
    func testResidualBreatheBarelyMovesTheFarCorner() {
        let halfDiagonal = (W * W + H * H).squareRoot() / 2
        let drift = halfDiagonal * (HeartbeatBump.breatheScale - 1)
        XCTAssertLessThan(drift, 20)
        // …versus the 270 pt it used to sweep at 1.30.
        XCTAssertGreaterThan(halfDiagonal * 0.30, 250)
    }
}
