import XCTest
@testable import VictorEffects

/// 💣 The grenade's throw (`GrenadeToss.pose`): it has to come IN from the
/// corner, stay on the glass for the whole arc, and go off in the middle.
final class GrenadeTossTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testItStartsJustPastTheBottomLeftCorner() {
        let p = GrenadeToss.pose(at: 0, in: screen).position
        XCTAssertLessThan(p.x, screen.minX)
        XCTAssertLessThan(p.y, screen.minY)
        XCTAssertEqual(GrenadeToss.pose(at: 0, in: screen).scale, GrenadeToss.startScale)
    }

    func testItIsOnScreenWellBeforeTheShoutEnds() {
        let p = GrenadeToss.pose(at: 0.2, in: screen).position
        XCTAssertTrue(screen.contains(p), "\(p) should be on the glass 0.2 s in")
    }

    func testTheArcNeverLeavesThroughTheTop() {
        let h = GrenadeToss.restHeight(in: screen)
        for i in 0...145 {
            let pose = GrenadeToss.pose(at: Double(i) / 100, in: screen)
            XCTAssertLessThan(pose.position.y + h * pose.scale / 2, screen.maxY, "t=\(Double(i) / 100)")
        }
    }

    func testItBlowsUpLyingStillInTheMiddle() {
        let atBlast = GrenadeToss.pose(at: GrenadeToss.blastAt, in: screen)
        XCTAssertEqual(atBlast.position.x, screen.midX, accuracy: 3)
        XCTAssertEqual(atBlast.position.y, screen.midY, accuracy: 0.001)
        XCTAssertEqual(atBlast.scale, 1)
        let resting = GrenadeToss.pose(at: GrenadeToss.bounce2End + 0.01, in: screen)
        XCTAssertEqual(resting.position, GrenadeToss.restPoint(in: screen))
    }

    func testTheBlastComesAfterTheShout() {
        // The words of 87_grenade.mp3 end ~1.2 s in; the clip is 1.51 s.
        XCTAssertGreaterThan(GrenadeToss.blastAt, 1.2)
        XCTAssertLessThan(GrenadeToss.blastAt, 1.6)
    }

    func testThePathIsContinuousAcrossThePhases() {
        for t in [GrenadeToss.flight, GrenadeToss.bounce1End, GrenadeToss.bounce2End] {
            let a = GrenadeToss.pose(at: t - 0.0005, in: screen), b = GrenadeToss.pose(at: t + 0.0005, in: screen)
            XCTAssertLessThan(hypot(a.position.x - b.position.x, a.position.y - b.position.y), 4, "jump at \(t)")
            XCTAssertEqual(a.angle, b.angle, accuracy: 0.05, "spin jump at \(t)")
        }
    }

    func testTheSpritesDraw() {
        XCTAssertNotNil(GrenadeToss.grenadeImage(height: 120, scale: 2))
        XCTAssertNotNil(GrenadeToss.fireDisc)
        XCTAssertNotNil(GrenadeToss.smokeDisc)
        XCTAssertGreaterThan(GrenadeToss.makeBlast(at: CGPoint(x: 500, y: 400), in: screen).sublayers?.count ?? 0, 10)
    }
}
