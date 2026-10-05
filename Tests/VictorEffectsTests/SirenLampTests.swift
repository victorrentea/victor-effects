import XCTest
@testable import VictorEffects

/// The retina overlay the other corner effects are measured on — 1512 × 982
/// points, bottom-origin.
private let W: CGFloat = 1512
private let H: CGFloat = 982
private let bounds = CGRect(x: 0, y: 0, width: W, height: H)

/// `siren_lamp.png` is 424 × 301 after cropping the transparent margin.
private let lampSize = CGSize(width: 424, height: 301)

final class SirenLampTests: XCTestCase {

    func testTheLampStandsOnTheBottomEdge() {
        XCTAssertEqual(SirenLamp.frame(imageSize: lampSize, in: bounds).minY, 0)
    }

    func testTheLampStaysInsideTheBoxVictorDrew() {
        let f = SirenLamp.frame(imageSize: lampSize, in: bounds)
        XCTAssertGreaterThanOrEqual(f.minX, W * SirenLamp.boxLeft - 0.5)
        XCTAssertLessThanOrEqual(f.maxX, W * SirenLamp.boxRight + 0.5)
        XCTAssertLessThanOrEqual(f.maxY, H * SirenLamp.boxHeight + 0.5)
    }

    func testAspectFitKeepsTheLampsShapeAndFillsOneSideOfTheBox() {
        let f = SirenLamp.frame(imageSize: lampSize, in: bounds)
        XCTAssertEqual(f.width / f.height, lampSize.width / lampSize.height, accuracy: 0.001)
        // On the retina the box is wider than the lamp's aspect: height binds.
        XCTAssertEqual(f.height, H * SirenLamp.boxHeight, accuracy: 0.5)
    }

    func testTheLampIsCentredAcrossItsBox() {
        let f = SirenLamp.frame(imageSize: lampSize, in: bounds)
        XCTAssertEqual(f.midX, W * (SirenLamp.boxLeft + SirenLamp.boxRight) / 2, accuracy: 0.5)
    }

    func testOneTurnPerWail_eightWailsFillTheSirenClip() {
        // 02_siren.mp3 is 5.17 s and holds eight bursts; the tablet loops it,
        // so a lamp at any other tempo slides out of step within a few seconds.
        XCTAssertEqual(SirenLamp.period * 8, 5.175, accuracy: 0.01)
    }

    func testTheFlashFrameLandsOnTheLoudHalfOfEachWail() {
        // Last of four frames = beam at the room; each burst is loud ~0–0.4 s.
        let flashStart = (SirenLamp.period * 0.75 - SirenLamp.phase)
        let flashEnd = SirenLamp.period - SirenLamp.phase
        XCTAssertGreaterThanOrEqual(flashStart, 0)
        XCTAssertLessThanOrEqual(flashEnd, 0.4)
    }
}
