import XCTest
@testable import VictorEffects

final class CoffeeFlightTests: XCTestCase {

    // MARK: - Calm approach

    func testApproachStartsAtTheCupAndLandsOnTheCursor() {
        let start = CGPoint(x: 100, y: 80)
        let target = CGPoint(x: 1400, y: 620)
        let pts = CoffeeFlight.approach(from: start, to: target)
        XCTAssertEqual(pts.first!.x, start.x, accuracy: 0.001)
        XCTAssertEqual(pts.first!.y, start.y, accuracy: 0.001)
        XCTAssertEqual(pts.last!.x, target.x, accuracy: 0.001)
        XCTAssertEqual(pts.last!.y, target.y, accuracy: 0.001)
    }

    func testApproachClimbsItsOwnColumnBeforeLeaningAcross() {
        // The whole point of the shared control point: at the halfway mark the cup
        // has gained more of its height than of its sideways distance, whichever
        // way the cursor lies. That is what makes every lane look like one lane.
        let start = CGPoint(x: 100, y: 80)
        for target in [CGPoint(x: 1500, y: 700), CGPoint(x: 700, y: 900), CGPoint(x: 1800, y: 300)] {
            let mid = CoffeeFlight.approach(from: start, to: target, steps: 32)[16]
            let gainedY = (mid.y - start.y) / (target.y - start.y)
            let gainedX = (mid.x - start.x) / (target.x - start.x)
            XCTAssertGreaterThan(gainedY, gainedX, "target \(target)")
        }
    }

    func testApproachIsTheSameShapeForEveryCup() {
        // Two cups born at the same spot with the same cursor must be identical —
        // no per-cup randomness left anywhere in the calm lane.
        let a = CoffeeFlight.approach(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 900, y: 500))
        let b = CoffeeFlight.approach(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 900, y: 500))
        XCTAssertEqual(a, b)
    }

    func testApproachDurationIsConstantSpeedWithinItsClamps() {
        let start = CGPoint(x: 100, y: 80)
        let near = CoffeeFlight.approachDuration(from: start, to: CGPoint(x: 400, y: 300))
        let far = CoffeeFlight.approachDuration(from: start, to: CGPoint(x: 1500, y: 800))
        XCTAssertLessThan(near, far)
        // Clamped at both ends: a cup born under the cursor still takes a moment,
        // and one crossing two screens does not crawl.
        XCTAssertEqual(CoffeeFlight.approachDuration(from: start, to: start), 1.5, accuracy: 0.001)
        XCTAssertEqual(CoffeeFlight.approachDuration(from: .zero, to: CGPoint(x: 9000, y: 0)), 4.0, accuracy: 0.001)
    }

    // MARK: - Storm sweep

    func testSweepStartsAndEndsOnItsMarks() {
        // Tapered amplitude: the wave must not push the cup off the point it is
        // about to detonate on.
        let start = CGPoint(x: 200, y: 80)
        let target = CGPoint(x: 960, y: 540)
        let pts = CoffeeFlight.sweep(from: start, to: target, amplitude: 300, swings: 3, phase: 1.1)
        XCTAssertEqual(pts.first!.x, start.x, accuracy: 0.001)
        XCTAssertEqual(pts.first!.y, start.y, accuracy: 0.001)
        XCTAssertEqual(pts.last!.x, target.x, accuracy: 0.001)
        XCTAssertEqual(pts.last!.y, target.y, accuracy: 0.001)
    }

    func testSweepActuallyWaves() {
        let start = CGPoint(x: 200, y: 80)
        let target = CGPoint(x: 960, y: 540)
        let pts = CoffeeFlight.sweep(from: start, to: target, amplitude: 300, swings: 3)
        // Distance from the straight run, signed by which side of it we are on.
        let dx = target.x - start.x, dy = target.y - start.y
        let len = hypot(dx, dy)
        let side = pts.map { p -> CGFloat in
            ((p.x - start.x) * dy - (p.y - start.y) * dx) / len
        }
        XCTAssertGreaterThan(side.max()!, 50)
        XCTAssertLessThan(side.min()!, -50)
    }

    func testSweepWithNoAmplitudeIsAStraightLine() {
        let pts = CoffeeFlight.sweep(from: .zero, to: CGPoint(x: 100, y: 100), amplitude: 0, swings: 3, steps: 4)
        XCTAssertEqual(pts[2].x, 50, accuracy: 0.001)
        XCTAssertEqual(pts[2].y, 50, accuracy: 0.001)
    }

    // MARK: - Blast scatter

    func testBlastPointsScatterAroundTheCentreAndStayInTheSpread() {
        let centre = CGPoint(x: 960, y: 540)
        let spread = CGSize(width: 300, height: 200)
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for i in 0..<64 {
            let a = CGFloat(i) / 64 * 2 * .pi
            let p = CoffeeFlight.blastPoint(center: centre, spread: spread, angle: a, unitRadius: 1)
            XCTAssertLessThanOrEqual(abs(p.x - centre.x), spread.width + 0.001)
            XCTAssertLessThanOrEqual(abs(p.y - centre.y), spread.height + 0.001)
            xs.append(p.x); ys.append(p.y)
        }
        // Really scattered, not all in one spot.
        XCTAssertGreaterThan(xs.max()! - xs.min()!, spread.width)
        XCTAssertGreaterThan(ys.max()! - ys.min()!, spread.height)
    }

    func testBlastPointAtZeroRadiusIsTheCentre() {
        let centre = CGPoint(x: 960, y: 540)
        let p = CoffeeFlight.blastPoint(center: centre, spread: CGSize(width: 300, height: 200),
                                        angle: 2.0, unitRadius: 0)
        XCTAssertEqual(p.x, centre.x, accuracy: 0.001)
        XCTAssertEqual(p.y, centre.y, accuracy: 0.001)
    }

    func testClampKeepsCupsOnTheProjector() {
        let b = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(CoffeeFlight.clamp(CGPoint(x: -500, y: 5000), in: b, margin: 60),
                       CGPoint(x: 60, y: 1020))
        XCTAssertEqual(CoffeeFlight.clamp(CGPoint(x: 900, y: 500), in: b, margin: 60),
                       CGPoint(x: 900, y: 500))
    }
}
