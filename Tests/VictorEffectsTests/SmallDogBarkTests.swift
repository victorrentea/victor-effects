import XCTest
@testable import VictorEffects

final class SmallDogBarkTests: XCTestCase {

    func testTheDogStandsOnTheBottomEdgeFourPercentInFromTheLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let f = SmallDogBark.frame(imageSize: CGSize(width: 407, height: 540), in: screen)
        XCTAssertEqual(f.minY, 0)
        XCTAssertEqual(f.minX, 1728 * 0.04, accuracy: 0.001)
        XCTAssertEqual(f.height, 1117 * 0.48, accuracy: 0.001)
        XCTAssertEqual(f.width / f.height, 407.0 / 540.0, accuracy: 0.001)
    }

    /// He is on the ground between barks and in the air during each one —
    /// highest on the loudest — and back down before the clip ends.
    func testTheJumpFollowsTheBarks() {
        let curve = SmallDogBark.jumpCurve(duration: 5.06)
        func lift(at t: Double) -> Double {
            curve.lift[curve.times.firstIndex { $0 >= t - 1e-9 }!]
        }
        XCTAssertEqual(curve.times.count, curve.lift.count)
        XCTAssertEqual(curve.times.last!, 5.06, accuracy: 1e-9)
        XCTAssertEqual(lift(at: 0), 0)
        XCTAssertEqual(lift(at: 2.0), 0, "silence between 1.24 s and 2.62 s")
        XCTAssertEqual(curve.lift.last!, 0)
        for bark in SmallDogBark.barks {
            XCTAssertGreaterThan(lift(at: (bark.start + bark.end) / 2), 0, "airborne on the bark at \(bark.start)")
        }
        XCTAssertEqual(curve.lift.max()!, 1.0, accuracy: 0.05, "the loudest bark is the full jump")
        XCTAssertLessThanOrEqual(curve.lift.max()!, 1.0)
    }

    /// Slow enough to watch: the shortest bark (1.06–1.08 s) still keeps him
    /// in the air for `minAirtime`, not for its own 40 ms.
    func testEvenTheShortestBarkIsAFullSlowHop() {
        let curve = SmallDogBark.jumpCurve(duration: 5.06)
        let airborne = zip(curve.times, curve.lift).filter { $0.0 > 0.95 && $0.0 < 1.4 && $0.1 > 0 }
        XCTAssertGreaterThanOrEqual(airborne.count, Int(SmallDogBark.minAirtime / 0.02) - 2)
        XCTAssertGreaterThanOrEqual(SmallDogBark.minAirtime, 0.4)
    }

    func testBarksAreInOrderInsideTheClip() {
        let barks = SmallDogBark.barks
        XCTAssertEqual(barks.count, 10)
        XCTAssertEqual(barks.map(\.start), barks.map(\.start).sorted())
        XCTAssertTrue(barks.allSatisfy { $0.start < $0.end && $0.end < 5.05 && $0.strength <= 1 })
    }
}
