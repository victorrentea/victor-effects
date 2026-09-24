import XCTest
@testable import VictorEffects

final class CoffeeFlightTests: XCTestCase {

    // MARK: - The chimney

    func testChimneyStartsAtTheCupAndEndsAtTheTop() {
        let start = CGPoint(x: 100, y: 80)
        let pts = CoffeeFlight.chimney(from: start, toY: 1200, amplitude: 30, swings: 2, phase: 1.1)
        XCTAssertEqual(pts.first!.x, start.x, accuracy: 0.001)
        XCTAssertEqual(pts.first!.y, start.y, accuracy: 0.001)
        XCTAssertEqual(pts.last!.y, 1200, accuracy: 0.001)
    }

    func testChimneyGoesStraightUpWithinItsSway() {
        // No drift: every point stays inside ±amplitude of the spawn column,
        // and the climb is monotonic — a cup never comes back down.
        let start = CGPoint(x: 100, y: 80)
        let pts = CoffeeFlight.chimney(from: start, toY: 1200, amplitude: 30, swings: 2.5, phase: 0.4)
        for p in pts { XCTAssertLessThanOrEqual(abs(p.x - start.x), 30.001) }
        for (a, b) in zip(pts, pts.dropFirst()) { XCTAssertGreaterThan(b.y, a.y) }
    }

    func testChimneyActuallySwaysBothWays() {
        let start = CGPoint(x: 100, y: 80)
        let xs = CoffeeFlight.chimney(from: start, toY: 1200, amplitude: 30, swings: 2, phase: 0).map { $0.x - start.x }
        XCTAssertGreaterThan(xs.max()!, 20)
        XCTAssertLessThan(xs.min()!, -20)
    }

    func testChimneyLeavesTheSpawnPointCleanly() {
        // The sway ramps in: the first few points hug the column even with a
        // phase that would otherwise throw the cup sideways at birth.
        let start = CGPoint(x: 100, y: 80)
        let pts = CoffeeFlight.chimney(from: start, toY: 1200, amplitude: 40, swings: 2, phase: .pi / 2, steps: 48)
        XCTAssertLessThan(abs(pts[1].x - start.x), 5)
    }

    func testChimneyWithNoAmplitudeIsAVerticalLine() {
        let pts = CoffeeFlight.chimney(from: CGPoint(x: 50, y: 0), toY: 100, amplitude: 0, swings: 3, steps: 4)
        for p in pts { XCTAssertEqual(p.x, 50, accuracy: 0.001) }
        XCTAssertEqual(pts[2].y, 50, accuracy: 0.001)
    }

    func testRiseDurationIsConstantSpeedWithinItsClamps() {
        let short = CoffeeFlight.riseDuration(from: 80, toY: 900)
        let tall = CoffeeFlight.riseDuration(from: 80, toY: 1300)
        XCTAssertLessThan(short, tall)
        XCTAssertEqual(CoffeeFlight.riseDuration(from: 80, toY: 80), 3.5, accuracy: 0.001)
        XCTAssertEqual(CoffeeFlight.riseDuration(from: 0, toY: 9000), 7.0, accuracy: 0.001)
    }

    func testFadeStartsOnlyAsTheCupApproachesTheTop() {
        XCTAssertGreaterThan(CoffeeFlight.fadeStartFraction, 0.5)
        XCTAssertLessThan(CoffeeFlight.fadeStartFraction, 1)
    }

    func testClampKeepsPointsOnTheProjector() {
        let b = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(CoffeeFlight.clamp(CGPoint(x: -500, y: 5000), in: b, margin: 60),
                       CGPoint(x: 60, y: 1020))
        XCTAssertEqual(CoffeeFlight.clamp(CGPoint(x: 900, y: 500), in: b, margin: 60),
                       CGPoint(x: 900, y: 500))
    }
}
