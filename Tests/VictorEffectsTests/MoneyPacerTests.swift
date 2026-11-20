import XCTest
@testable import VictorEffects

final class MoneyPacerTests: XCTestCase {
    func testAPressAfterTheGapStrikesAtOnce() {
        var p = MoneyPacer()
        XCTAssertEqual(p.slot(at: 10), 0)
        XCTAssertEqual(p.slot(at: 11), 0)
    }

    func testQuickPressesAreSpacedNotStacked() throws {
        var p = MoneyPacer()
        XCTAssertEqual(p.slot(at: 10), 0)
        XCTAssertEqual(try XCTUnwrap(p.slot(at: 10.05)), 0.20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(p.slot(at: 10.10)), 0.40, accuracy: 1e-9)
    }

    func testAFullQueueDropsThePressInsteadOfGrowingATail() throws {
        var p = MoneyPacer()
        _ = p.slot(at: 10)          // strikes now
        _ = p.slot(at: 10)          // +0.25
        _ = p.slot(at: 10)          // +0.50 = maxWait
        XCTAssertNil(p.slot(at: 10), "a fourth ching in the same instant would wait 0.75 s")
        XCTAssertEqual(try XCTUnwrap(p.slot(at: 10.3)), 0.45, accuracy: 1e-9, "the dropped press did not take a slot")
    }

    func testThePoolNeverRestartsACopyThatStillRings() {
        // The ching is 1.38 s: struck every 0.25 s, six are sounding at once.
        XCTAssertEqual(MoneyPacer.poolSize(clip: 1.38), 7)
        XCTAssertGreaterThan(Double(MoneyPacer.poolSize(clip: 1.38) - 1) * MoneyPacer.minGap, 1.38)
        XCTAssertEqual(MoneyPacer.poolSize(clip: 0.1), 2)
    }
}
