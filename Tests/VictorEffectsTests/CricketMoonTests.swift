import XCTest
@testable import VictorEffects

/// 🦗 The arithmetic of tile 12's run, without a screen. What it promises the room:
/// bottom-left, the picture's own proportions, and gone when the sound is.
final class CricketMoonTests: XCTestCase {
    private let video = CGSize(width: 884, height: 646)
    private let macBook = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testItSitsFlushInTheBottomLeftCorner() {
        let f = CricketMoon.frame(in: macBook, video: video)
        XCTAssertEqual(f.minX, 0)
        XCTAssertEqual(f.minY, 0, "the crop ends under the feet: he stands on the screen's edge")
    }

    func testOnTheBrushStrokeTheStrokeTakesTheCornerAndHeStandsInsideIt() {
        let placed = CricketMoon.onBackdrop(in: macBook)
        XCTAssertEqual(placed.backdrop.origin, macBook.origin)
        XCTAssertEqual(placed.backdrop.height, macBook.height * CricketMoon.backdropHeightShare, accuracy: 0.01)
        XCTAssertTrue(placed.backdrop.contains(placed.video), "the film stands on the stroke")
        XCTAssertEqual(placed.video.width / placed.video.height, video.width / video.height, accuracy: 0.01,
                       "the film keeps its proportions")
    }

    func testTheStrokeStaysACornerOnANarrowDisplayToo() {
        let portrait = CGRect(x: 0, y: 0, width: 800, height: 1280)
        let placed = CricketMoon.onBackdrop(in: portrait)
        XCTAssertEqual(placed.backdrop.width, portrait.width * CricketMoon.backdropWidthCap, accuracy: 0.01)
    }

    func testTheCornerIsAlsoTheCornerOfAnOverlayThatDoesNotStartAtZero() {
        let f = CricketMoon.frame(in: CGRect(x: 40, y: 30, width: 1512, height: 982), video: video)
        XCTAssertEqual(f.origin, CGPoint(x: 40, y: 30))
    }

    func testTheHeightIsAShareOfTheScreenAndTheProportionsAreKept() {
        let f = CricketMoon.frame(in: macBook, video: video)
        XCTAssertEqual(f.height, macBook.height * CricketMoon.heightShare, accuracy: 0.01)
        XCTAssertEqual(f.width / f.height, video.width / video.height, accuracy: 0.001)
    }

    func testANarrowDisplayCapsTheWidthSoItStaysACorner() {
        let portrait = CGRect(x: 0, y: 0, width: 800, height: 1400)
        let f = CricketMoon.frame(in: portrait, video: video)
        XCTAssertEqual(f.width, portrait.width * CricketMoon.widthCap, accuracy: 0.01)
        XCTAssertEqual(f.width / f.height, video.width / video.height, accuracy: 0.001)
    }

    func testAnUnreadableVideoSizeDrawsNothingRatherThanDividingByZero() {
        XCTAssertEqual(CricketMoon.frame(in: macBook, video: .zero), .zero)
    }

    func testTheRunLastsAsLongAsTheSoundIsHeard() {
        XCTAssertEqual(CricketMoon.life(clip: 9.406, video: 9.458), 9.406)
        XCTAssertEqual(CricketMoon.life(clip: 12, video: 9.458), 12, "a longer clip holds the last frame")
    }

    func testWithoutAClipTheVideoStillEndsTheRun() {
        XCTAssertEqual(CricketMoon.life(clip: nil, video: 9.458), 9.458)
        XCTAssertEqual(CricketMoon.life(clip: 0, video: 9.458), 9.458)
    }

    func testTheFadeLandsOnTheEndsOfTheClip() {
        let k = CricketMoon.fadeKeyTimes(life: 10)
        XCTAssertEqual(k[0], 0)
        XCTAssertEqual(k[1], CricketMoon.fadeIn / 10, accuracy: 1e-9)
        XCTAssertEqual(k[2], 1 - CricketMoon.fadeOut / 10, accuracy: 1e-9)
        XCTAssertEqual(k[3], 1)
    }

    func testTheKeyTimesStayInOrderOnARunShorterThanItsFades() {
        for life in [0.0, 0.1, 0.4, 0.6] {
            let k = CricketMoon.fadeKeyTimes(life: life)
            XCTAssertEqual(k, k.sorted(), "CAKeyframeAnimation drops keyTimes that go backwards")
            XCTAssertEqual(k.first, 0)
            XCTAssertEqual(k.last, 1)
        }
    }

    func testThePressStartsItAndAStoppedSoundTakesItOff() {
        XCTAssertEqual(SoundEffectMap.pressEffect(for: CricketMoon.sound), CricketMoon.effectName)
        XCTAssertEqual(SoundEffectMap.stopEffect(for: CricketMoon.sound), CricketMoon.effectName + "/stop")
        XCTAssertEqual(EffectsCatalog.effectName(forAsset: CricketMoon.sound), CricketMoon.effectName)
    }

    func testItsStopIsAStopWordSoASuspendStillLetsItThrough() {
        XCTAssertTrue(EffectsEngine.isStopWord(CricketMoon.effectName + "/stop"))
        XCTAssertFalse(EffectsEngine.isStopWord(CricketMoon.effectName))
    }
}
