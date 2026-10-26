import XCTest
@testable import VictorEffects

final class SmallDogBarkTests: XCTestCase {

    func testTheDogStandsOnTheBottomEdgeFourPercentInFromTheLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let f = SmallDogBark.frame(imageSize: CGSize(width: 407, height: 605), in: screen)
        XCTAssertEqual(f.minY, 0)
        XCTAssertEqual(f.minX, 1728 * 0.04, accuracy: 0.001)
        XCTAssertEqual(f.width / f.height, 407.0 / 605.0, accuracy: 0.001)
    }

    /// The headroom is for the jump, not a smaller dog: at rest he is still
    /// 48 % of the screen's height.
    func testTheDogAtRestKeepsItsHeightUnderTheJumpHeadroom() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let f = SmallDogBark.frame(imageSize: CGSize(width: 407, height: 605), in: screen)
        XCTAssertEqual(f.height / (1 + SmallDogBark.jumpHeadroom), 1117 * 0.48, accuracy: 0.001)
    }
}
