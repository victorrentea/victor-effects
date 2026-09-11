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

    func testTheCatSitsInTheBottomLeftCorner() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds)
        XCTAssertEqual(f.minX, 0, accuracy: 0.001, "flush to the left edge")
        XCTAssertEqual(f.minY, 0, accuracy: 0.001, "standing on the floor of the screen")
    }

    func testTheBoxIsAQuarterOfTheScreenArea() {
        let box = (W * HeartbeatCatCorner.boxWidthFraction) * (H * HeartbeatCatCorner.boxHeightFraction)
        XCTAssertEqual(box / (W * H), 0.25, accuracy: 1e-9)
    }

    func testItFitsInsideTheBoxAndKeepsItsAspectRatio() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds)
        XCTAssertLessThanOrEqual(f.width, W / 2 + 0.001)
        XCTAssertLessThanOrEqual(f.height, H / 2 + 0.001)
        XCTAssertEqual(f.width / f.height, catSize.width / catSize.height, accuracy: 0.001)
    }

    /// The real asset (1.40) is squarer than the retina's half-box (756 × 491 =
    /// 1.54), so **height** is what binds: the cat is 690 × 491 and the slack is
    /// spent rightward, away from the corner — never by lifting it off the floor.
    func testTheRealCatIsBoundByTheBoxHeightOnTheRetina() {
        let f = HeartbeatCatCorner.frame(imageSize: catSize, in: bounds)
        XCTAssertEqual(f.height, H / 2, accuracy: 0.001)
        XCTAssertEqual(f.width, 689.67, accuracy: 0.01)
        XCTAssertLessThan(f.width, W / 2)
    }

    /// A wider-than-the-box asset is limited by the width instead — still
    /// cornered, still whole, never cropped to fill.
    func testAVeryWideCatIsBoundByTheBoxWidth() {
        let f = HeartbeatCatCorner.frame(imageSize: CGSize(width: 1600, height: 400), in: bounds)
        XCTAssertEqual(f.width, W / 2, accuracy: 0.001)
        XCTAssertLessThan(f.height, H / 2)
        XCTAssertEqual(f.minX, 0, accuracy: 0.001)
        XCTAssertEqual(f.minY, 0, accuracy: 0.001)
    }

    func testADegenerateImageStillProducesTheBox() {
        let f = HeartbeatCatCorner.frame(imageSize: .zero, in: bounds)
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
