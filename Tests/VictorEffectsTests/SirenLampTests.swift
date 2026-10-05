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

    func testTheBaseSitsOnTheBottomEdge_theSpillBelowItIsOffScreen() {
        let f = SirenLamp.frame(imageSize: lampSize, in: bounds)
        XCTAssertEqual(f.minY + f.height * SirenLamp.belowBaseFraction, 0, accuracy: 0.001)
        XCTAssertLessThan(f.minY, 0)
    }

    func testGrownBeyondTheSizeThatFitsTheBoxVictorDrew() {
        let f = SirenLamp.frame(imageSize: lampSize, in: bounds)
        // On the retina the box is wider than the lamp's aspect: height binds.
        XCTAssertEqual(f.height, H * SirenLamp.boxHeight * SirenLamp.growth, accuracy: 0.5)
        XCTAssertEqual(f.width / f.height, lampSize.width / lampSize.height, accuracy: 0.001)
    }

    func testItSitsALittleLeftOfTheBoxsCentreWithTheBaseStillOnScreen() {
        let f = SirenLamp.frame(imageSize: lampSize, in: bounds)
        let boxMid = W * (SirenLamp.boxLeft + SirenLamp.boxRight) / 2
        XCTAssertEqual(f.midX, boxMid - W * SirenLamp.nudgeLeft, accuracy: 0.5)
        // The grey base starts at column 135 of 424: it must stay on the glass
        // even if the glow to its left does not.
        XCTAssertGreaterThan(f.minX + f.width * 135 / 424, 0)
    }

    func testOneTurnPerWail_eightWailsFillTheSirenClip() {
        // Tuned on 02_siren.mp3 (5.17 s, eight bursts) and kept on #63: the
        // air horn has no beat, so the lamp spins at a real siren's tempo.
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
