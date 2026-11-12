import XCTest
@testable import VictorEffects

/// 💣 The grenade's throw (`GrenadeToss.pose`): it has to come IN from a
/// bottom corner, stay on the glass for the whole arc, and go off where the
/// pointer was at the press.
final class GrenadeTossTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private var middle: CGPoint { CGPoint(x: screen.midX, y: screen.midY) }

    /// A spread of pointers: the middle, the four quadrants, hard against each edge.
    private var pointers: [CGPoint] {
        [middle, CGPoint(x: 300, y: 250), CGPoint(x: 1500, y: 900), CGPoint(x: 200, y: 1000),
         CGPoint(x: 1600, y: 150), CGPoint(x: 0, y: 0), CGPoint(x: 1728, y: 1117),
         CGPoint(x: 864, y: 1116), CGPoint(x: 1, y: 560)]
    }

    func testItLandsWhereThePointerWas() {
        let p = CGPoint(x: 1200, y: 700)
        let target = GrenadeToss.target(pointer: p, in: screen)
        XCTAssertEqual(target, p)
        let atBlast = GrenadeToss.pose(at: GrenadeToss.blastAt, to: target, in: screen)
        XCTAssertEqual(atBlast.position.x, p.x, accuracy: 3)
        XCTAssertEqual(atBlast.position.y, p.y, accuracy: 0.001)
        XCTAssertEqual(GrenadeToss.pose(at: GrenadeToss.bounce2End + 0.01, to: target, in: screen).position, p)
    }

    func testAPointerOnAnotherDisplayAimsAtTheMiddle() {
        XCTAssertEqual(GrenadeToss.target(pointer: CGPoint(x: -400, y: 300), in: screen), middle)
        XCTAssertEqual(GrenadeToss.target(pointer: nil, in: screen), middle)
    }

    func testAPointerOnTheEdgeIsPulledInsideTheGlass() {
        let t = GrenadeToss.target(pointer: CGPoint(x: 1, y: 1116), in: screen)
        XCTAssertGreaterThan(t.x, GrenadeToss.restHeight(in: screen) - 1)
        XCTAssertLessThan(t.y, screen.maxY - GrenadeToss.restHeight(in: screen))
    }

    func testItIsThrownFromTheBottomCornerOnTheFarSide() {
        let right = GrenadeToss.startPoint(toward: CGPoint(x: 1500, y: 600), in: screen)
        XCTAssertLessThan(right.x, screen.minX)
        XCTAssertLessThan(right.y, screen.minY)
        let left = GrenadeToss.startPoint(toward: CGPoint(x: 200, y: 600), in: screen)
        XCTAssertGreaterThan(left.x, screen.maxX)
        XCTAssertLessThan(left.y, screen.minY)
        XCTAssertEqual(GrenadeToss.pose(at: 0, to: middle, in: screen).scale, GrenadeToss.startScale)
    }

    func testItIsOnScreenWellBeforeTheShoutEnds() {
        for p in pointers {
            let target = GrenadeToss.target(pointer: p, in: screen)
            let at = GrenadeToss.pose(at: 0.2, to: target, in: screen).position
            XCTAssertTrue(screen.contains(at), "\(at) should be on the glass 0.2 s in, aiming at \(p)")
        }
    }

    func testTheArcNeverLeavesThroughTheTop() {
        let h = GrenadeToss.restHeight(in: screen)
        for p in pointers {
            let target = GrenadeToss.target(pointer: p, in: screen)
            for i in 0...145 {
                let pose = GrenadeToss.pose(at: Double(i) / 100, to: target, in: screen)
                XCTAssertLessThan(pose.position.y + h * pose.scale / 2, screen.maxY + 1,
                                  "t=\(Double(i) / 100), aiming at \(p)")
            }
        }
    }

    func testTheBlastComesAfterTheShout() {
        // The words of 87_grenade.mp3 end ~1.2 s in; the clip is 1.51 s.
        XCTAssertGreaterThan(GrenadeToss.blastAt, 1.2)
        XCTAssertLessThan(GrenadeToss.blastAt, 1.6)
    }

    func testThePathIsContinuousAcrossThePhases() {
        for p in [middle, CGPoint(x: 300, y: 250)] {
            for t in [GrenadeToss.flight, GrenadeToss.bounce1End, GrenadeToss.bounce2End] {
                let a = GrenadeToss.pose(at: t - 0.0005, to: p, in: screen)
                let b = GrenadeToss.pose(at: t + 0.0005, to: p, in: screen)
                XCTAssertLessThan(hypot(a.position.x - b.position.x, a.position.y - b.position.y), 4, "jump at \(t)")
                XCTAssertEqual(a.angle, b.angle, accuracy: 0.05, "spin jump at \(t)")
            }
        }
    }

    func testTheSpritesDraw() {
        XCTAssertNotNil(GrenadeToss.grenadeImage(height: 120, scale: 2))
        XCTAssertNotNil(GrenadeToss.fireDisc)
        XCTAssertNotNil(GrenadeToss.smokeDisc)
        XCTAssertGreaterThan(GrenadeToss.makeBlast(at: CGPoint(x: 500, y: 400), in: screen).sublayers?.count ?? 0, 10)
    }
}
