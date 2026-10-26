import XCTest
@testable import VictorEffects

final class SmallDogBarkTests: XCTestCase {

    func testPressesRotateThroughTheDogsThatArePresent() {
        let start = SmallDogBark.nextIndex
        let dogs = ["1", "2", "3"]
        let picked = (0..<4).compactMap { _ in SmallDogBark.next(of: dogs) }
        XCTAssertEqual(picked, (start..<start + 4).map { dogs[$0 % 3] })
    }

    func testOneDogDroppedInBarksEveryTimeAndNoneMeansNothing() {
        XCTAssertEqual(SmallDogBark.next(of: ["only"]), "only")
        XCTAssertEqual(SmallDogBark.next(of: ["only"]), "only")
        XCTAssertNil(SmallDogBark.next(of: [String]()))
    }

    func testTheDogStandsOnTheBottomEdgeFourPercentInFromTheRight() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let f = SmallDogBark.frame(imageSize: CGSize(width: 407, height: 540), in: screen)
        XCTAssertEqual(f.minY, 0)
        XCTAssertEqual(f.height, 1117 * 0.48, accuracy: 0.001)
        XCTAssertEqual(f.width / f.height, 407.0 / 540.0, accuracy: 0.001)
        XCTAssertEqual(screen.maxX - f.maxX, 1728 * 0.04, accuracy: 0.001)
    }
}
