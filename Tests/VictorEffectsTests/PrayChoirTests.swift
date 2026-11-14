import XCTest
@testable import VictorEffects

/// 🙏 Several clicks plant several men and ONE hymn lasts until the last of
/// them is done (2026-10-20) — the schedule that decides when it fades.
final class PrayChoirTests: XCTestCase {
    func testWithNoClickItLastsExactlyTheTile() {
        var choir = PrayChoir()
        choir.hold(untilMs: 20_840)
        XCTAssertEqual(choir.endMs, 20_840)
    }

    func testAClickNearTheEndStretchesItToThatManEnd() {
        var choir = PrayChoir()
        choir.hold(untilMs: 20_840)
        choir.plant(at: .zero, nowMs: 20_000)
        XCTAssertEqual(choir.endMs, 20_000 + PrayController.singMs)
    }

    func testAnEarlyClickNeverShortensTheTile() {
        var choir = PrayChoir()
        choir.hold(untilMs: 20_840)
        choir.plant(at: .zero, nowMs: 1000)
        XCTAssertEqual(choir.endMs, 20_840)
        choir.expire(nowMs: 15_000)
        XCTAssertEqual(choir.endMs, 20_840)
    }

    private let sing = PrayController.singMs

    func testOneClickSingsForOneMan() {
        var choir = PrayChoir()
        choir.plant(at: CGPoint(x: 10, y: 10), nowMs: 1000)
        XCTAssertEqual(choir.endMs, 1000 + sing)
        XCTAssertEqual(choir.fadeStartMs, 1000 + sing - PrayController.hymnFadeMs)
    }

    func testALaterClickStretchesTheHymnInsteadOfRestartingIt() {
        var choir = PrayChoir()
        choir.plant(at: .zero, nowMs: 0)
        choir.plant(at: CGPoint(x: 300, y: 0), nowMs: 5000)
        XCTAssertEqual(choir.prayers.count, 2)
        XCTAssertEqual(choir.endMs, 5000 + sing)
    }

    func testEachManLeavesWhenHisOwnHymnIsOver() {
        var choir = PrayChoir()
        choir.plant(at: .zero, nowMs: 0)
        choir.plant(at: CGPoint(x: 300, y: 0), nowMs: 5000)
        choir.expire(nowMs: sing + 1)
        XCTAssertEqual(choir.prayers.map(\.sinceMs), [5000])
        choir.expire(nowMs: 5000 + sing + 1)
        XCTAssertTrue(choir.prayers.isEmpty)
        XCTAssertNil(choir.endMs)
    }

    func testTwentyMenPrayTogether() {
        var choir = PrayChoir()
        for i in 0..<20 { choir.plant(at: .zero, nowMs: Double(i)) }
        XCTAssertEqual(choir.prayers.count, 20)
        XCTAssertEqual(choir.prayers.first?.sinceMs, 0, "the first man is still there when the twentieth arrives")
    }

    func testTheOldestMakesRoomBeyondTheCap() {
        var choir = PrayChoir()
        for i in 0...PrayChoir.maxPrayers { choir.plant(at: .zero, nowMs: Double(i)) }
        XCTAssertEqual(choir.prayers.count, PrayChoir.maxPrayers)
        XCTAssertEqual(choir.prayers.first?.sinceMs, 1)
    }
}

/// 🙏 The wheel sizes the hands, and the man planted from them (2026-11-14).
final class PrayScaleTests: XCTestCase {
    func testItComesUpAtTheSizeItAlwaysHad() {
        XCTAssertEqual(PrayScale().value, 1)
    }

    func testScrollingUpStopsAtThreeTimes() {
        var scale = PrayScale()
        scale.step(1)
        XCTAssertEqual(scale.value, PrayScale.stepFactor, accuracy: 0.0001)
        scale.step(100)
        XCTAssertEqual(scale.value, 3)
    }

    func testScrollingDownNeverGoesBelowTheOriginalSize() {
        var scale = PrayScale(value: 2)
        scale.step(-100)
        XCTAssertEqual(scale.value, 1)
    }

    func testAWheelClickIsOneNotchWhateverItsAcceleration() {
        var scale = PrayScale()
        XCTAssertEqual(scale.notches(precise: false, deltaY: 7), 1)
        XCTAssertEqual(scale.notches(precise: false, deltaY: -0.1), -1)
        XCTAssertEqual(scale.notches(precise: false, deltaY: 0), 0)
    }

    func testTrackpadPointsAddUpToNotches() {
        var scale = PrayScale()
        XCTAssertEqual(scale.notches(precise: true, deltaY: 7), 0)
        XCTAssertEqual(scale.notches(precise: true, deltaY: 7), 1)
        XCTAssertEqual(scale.notches(precise: true, deltaY: -40), -3, "2 points were left over: -38")
    }

    func testAManKeepsTheSizeOfTheHandsHeWasPlantedFrom() {
        var choir = PrayChoir()
        choir.plant(at: .zero, scale: 1, nowMs: 0)
        choir.plant(at: .zero, scale: 3, nowMs: 10)
        XCTAssertEqual(choir.prayers.map(\.scale), [1, 3])
    }
}

/// 🙏 What the wheel does to the PICTURE: `PrayView` drawn into a bitmap, with
/// a plain red rectangle for the cut-out, and the painted box measured.
final class PrayViewScaleTests: XCTestCase {
    private let pointer = CGPoint(x: 700, y: 600)

    /// The box of everything painted, in view points (y down).
    private func paintedBox(scale: CGFloat, planted: Bool) throws -> CGRect {
        let view = PrayView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1200))
        let figure = NSImage(size: NSSize(width: 265, height: 324))
        figure.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 265, height: 324).fill()
        figure.unlockFocus()
        view.figure = figure
        view.at = pointer
        view.nowMs = 0                       // the breathing is at exactly 1
        if planted {
            // 1 s in: all of him is there, and the ray has not started yet.
            view.prayers = [PrayChoir.Prayer(at: pointer, sinceMs: -1000, scale: scale)]
            view.handsAlpha = 0
        } else {
            view.scale = scale
        }
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let k = CGFloat(rep.pixelsHigh) / view.bounds.height
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThan(maxX, -1, "nothing was painted")
        return CGRect(x: CGFloat(minX) / k, y: CGFloat(minY) / k,
                      width: CGFloat(maxX - minX + 1) / k, height: CGFloat(maxY - minY + 1) / k)
    }

    func testThePointersHandsGrowThreefoldAboutThePointer() throws {
        let small = try paintedBox(scale: 1, planted: false)
        let big = try paintedBox(scale: 3, planted: false)
        XCTAssertEqual(big.height / small.height, 3, accuracy: 0.1)
        XCTAssertEqual(big.width / small.width, 3, accuracy: 0.1)
        XCTAssertEqual(small.midY, pointer.y, accuracy: 3)
        XCTAssertEqual(big.midY, pointer.y, accuracy: 5)
        XCTAssertEqual(big.midX, pointer.x, accuracy: 5)
    }

    func testAManPlantedFromBigHandsIsAsBigAsThey() throws {
        let small = try paintedBox(scale: 1, planted: true)
        let big = try paintedBox(scale: 3, planted: true)
        XCTAssertEqual(small.height, 260, accuracy: 3)
        XCTAssertEqual(big.height, 780, accuracy: 6)
        // His hands are where they were clicked, whatever his size.
        XCTAssertEqual(small.minY + small.height * 0.53, pointer.y, accuracy: 3)
        XCTAssertEqual(big.minY + big.height * 0.53, pointer.y, accuracy: 5)
    }
}
