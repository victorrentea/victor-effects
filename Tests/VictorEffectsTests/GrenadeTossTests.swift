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

/// 💥 The glass where it fell: after the shake, a quarter of the screen broken.
final class GrenadeCrackTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testTheGlassBreaksOnlyOnceTheShakeIsOver() {
        XCTAssertGreaterThanOrEqual(GrenadeToss.crackAt, GrenadeToss.blastAt + BombShake.seconds)
        XCTAssertGreaterThanOrEqual(GrenadeToss.totalDuration,
                                    GrenadeToss.crackAt + GrenadeToss.crackHold + GrenadeToss.crackFade)
    }

    /// The share of the screen inside a disc, sampled finer than the code does.
    private func coverage(_ c: CGPoint, _ r: CGFloat) -> CGFloat {
        var inside = 0, n = 200
        for i in 0..<n { for j in 0..<n {
            let p = CGPoint(x: (CGFloat(i) + 0.5) / CGFloat(n) * screen.width, y: (CGFloat(j) + 0.5) / CGFloat(n) * screen.height)
            if hypot(p.x - c.x, p.y - c.y) <= r { inside += 1 }
        } }
        n *= n
        return CGFloat(inside) / CGFloat(n)
    }

    func testAQuarterOfTheScreenBreaksInTheMiddleAndNearAnEdge() {
        for c in [CGPoint(x: 864, y: 558), CGPoint(x: 150, y: 150), CGPoint(x: 1600, y: 900)] {
            let r = GrenadeToss.holeRadius(at: c, in: screen)
            XCTAssertEqual(coverage(c, r), 0.25, accuracy: 0.02, "at \(c)")
        }
        // Near a corner the edge cuts the disc, so it has to be bigger.
        XCTAssertGreaterThan(GrenadeToss.holeRadius(at: CGPoint(x: 150, y: 150), in: screen),
                             GrenadeToss.holeRadius(at: CGPoint(x: 864, y: 558), in: screen))
    }

    func testItBreaksIntoManyPiecesThatFitTheHole() {
        let c = CGPoint(x: 864, y: 558)
        let r = GrenadeToss.holeRadius(at: c, in: screen)
        let crack = GrenadeToss.crack(at: c, holeRadius: r, seed: 42)
        XCTAssertEqual(crack.shards.count, GrenadeToss.crackSlices * 4)
        XCTAssertTrue(crack.hole.boundingBoxOfPath.contains(c))
        for shard in crack.shards {
            XCTAssertTrue(crack.hole.boundingBoxOfPath.insetBy(dx: -1, dy: -1).contains(shard.path.boundingBoxOfPath))
        }
        let reach = r * GrenadeToss.webReach * 1.1
        XCTAssertTrue(CGRect(x: c.x - reach, y: c.y - reach, width: 2 * reach, height: 2 * reach)
            .contains(crack.lines.boundingBoxOfPath))
    }

    func testShardsFlyOutThenFall() {
        let p = CGPoint(x: 500, y: 500), v = CGVector(dx: 800, dy: 400)
        let early = GrenadeToss.shardPosition(from: p, velocity: v, at: 0.1)
        XCTAssertGreaterThan(early.x, p.x); XCTAssertGreaterThan(early.y, p.y)
        XCTAssertLessThan(GrenadeToss.shardPosition(from: p, velocity: v, at: GrenadeToss.shardFlight).y, 0,
                          "by the end of its flight a shard has left through the bottom")
    }

    func testTwoPressesBreakDifferentlyButOneSeedTheSame() {
        let c = CGPoint(x: 800, y: 500)
        let a = GrenadeToss.crack(at: c, holeRadius: 300, seed: 1).lines
        XCTAssertEqual(a, GrenadeToss.crack(at: c, holeRadius: 300, seed: 1).lines)
        XCTAssertNotEqual(a, GrenadeToss.crack(at: c, holeRadius: 300, seed: 2).lines)
    }

    func testTheShardsAreCutWithOrWithoutAPhotograph() {
        let c = CGPoint(x: 800, y: 500)
        let crack = GrenadeToss.crack(at: c, holeRadius: 300, seed: 7)
        XCTAssertEqual(GrenadeToss.shardImages(crack, shot: nil, bounds: screen, scale: 1).count, crack.shards.count)
    }
}

/// 💣 The Counter-Strike blast is played through a variable (one of three at
/// random), which `StopSilencesTheSoundTests` cannot follow — so this pins the
/// two stops naming the list by hand.
final class GrenadeBoomStopsTests: XCTestCase {
    func testBothStopsSilenceTheCounterStrikeBlast() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let swift = try String(contentsOf: root.appendingPathComponent("Sources/VictorEffects/EmojiAnimator.swift"),
                               encoding: .utf8)
        func body(_ marker: String) throws -> String {
            let start = try XCTUnwrap(swift.range(of: marker))
            let end = try XCTUnwrap(swift.range(of: "\n    }\n", range: start.upperBound..<swift.endIndex))
            return String(swift[start.lowerBound..<end.lowerBound])
        }
        XCTAssertTrue(try body("func stopEffect(named name: String)").contains("Self.grenadeCSBooms"))
        XCTAssertTrue(try body("func stopAllActiveEffects()").contains("Self.grenadeCSBooms"))
    }
}
