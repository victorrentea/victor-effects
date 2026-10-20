import XCTest
@testable import VictorEffects

/// 🙏 Several clicks plant several men and ONE hymn lasts until the last of
/// them is done (2026-10-20) — the schedule that decides when it fades.
final class PrayChoirTests: XCTestCase {
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

    func testTheOldestMakesRoomBeyondTheCap() {
        var choir = PrayChoir()
        for i in 0...PrayChoir.maxPrayers { choir.plant(at: .zero, nowMs: Double(i)) }
        XCTAssertEqual(choir.prayers.count, PrayChoir.maxPrayers)
        XCTAssertEqual(choir.prayers.first?.sinceMs, 1)
    }
}
