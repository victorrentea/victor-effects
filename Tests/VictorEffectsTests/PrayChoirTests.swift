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
