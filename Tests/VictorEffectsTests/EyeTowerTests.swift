import XCTest
import CoreGraphics
@testable import VictorEffects

/// 👁️ ⌘⌃7: the Eye of the Tower's layout and the light's moves, without a screen.
final class EyeTowerTests: XCTestCase {
    private let retina = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testTheTowerStandsInVictorsBoxAndTheEyeOnItsTop() {
        let box = EyeTower.scaled(EyeTower.towerBox, in: retina)
        let t = EyeTower.towerFrame(in: retina)
        XCTAssertEqual(t.midX, box.midX, accuracy: 0.5)
        XCTAssertEqual(t.minY, retina.minY, accuracy: 0.5, "it rises out of the bottom edge")
        XCTAssertEqual(t.maxY, box.maxY, accuracy: 0.5)
        XCTAssertTrue(retina.contains(t))
        let eye = EyeTower.eyeCenter(in: retina)
        XCTAssertGreaterThan(eye.y, box.maxY - box.height * 0.05)
        XCTAssertLessThan(eye.y, retina.maxY)
        XCTAssertGreaterThan(eye.x, box.minX)
        XCTAssertLessThan(eye.x, box.maxX)
    }

    func testSearchingStaysOnTheStripAlongTheBottom() {
        var rng = SystemRandomNumberGenerator()
        let strip = EyeTower.scaled(EyeTower.lightBox, in: retina)
        XCTAssertLessThan(strip.maxY, retina.height * 0.2)
        var p = CGPoint(x: strip.midX, y: strip.midY)
        for _ in 0..<300 {
            let q = EyeTower.nextWaypoint(from: p, in: retina, using: &rng)
            XCTAssertTrue(strip.contains(q))
            p = q
        }
    }

    func testASearchStepSettlesOnItsTargetWithoutOvershooting() {
        let target = CGPoint(x: 1400, y: 60)
        var p = CGPoint(x: 700, y: 100)
        var steps = 0
        while p != target && steps < 600 {
            let next = EyeTower.searchStep(from: p, to: target, dt: 1.0 / 60)
            XCTAssertLessThanOrEqual(hypot(target.x - next.x, target.y - next.y),
                                     hypot(target.x - p.x, target.y - p.y))
            p = next; steps += 1
        }
        XCTAssertEqual(p, target)
        XCTAssertLessThan(Double(steps) / 60, 3.0, "a sweep across the strip should take seconds, not more")
    }

    func testFollowingClosesTheGapTheSameAtAnyFrameRate() {
        let from = CGPoint(x: 0, y: 0), to = CGPoint(x: 1000, y: 0)
        var a = from, b = from
        for _ in 0..<60 { a = EyeTower.followStep(from: a, to: to, dt: 1.0 / 60) }
        for _ in 0..<30 { b = EyeTower.followStep(from: b, to: to, dt: 1.0 / 30) }
        XCTAssertEqual(a.x, b.x, accuracy: 0.5)
        XCTAssertGreaterThan(a.x, 990)
    }

    func testItFollowsOnlyAMovingPointerBelowTheEye() {
        let eye = EyeTower.eyeCenter(in: retina)
        let size = EyeTower.eyeSize(in: retina)
        let below = CGPoint(x: 900, y: 300)
        XCTAssertTrue(EyeTower.follows(pointer: below, eye: eye, eyeSize: size, sinceMoved: 0.1))
        XCTAssertFalse(EyeTower.follows(pointer: below, eye: eye, eyeSize: size, sinceMoved: EyeTower.followGrace + 0.1))
        XCTAssertFalse(EyeTower.follows(pointer: CGPoint(x: 900, y: eye.y + 10), eye: eye, eyeSize: size, sinceMoved: 0))
        XCTAssertFalse(EyeTower.follows(pointer: nil, eye: eye, eyeSize: size, sinceMoved: 0))
    }

    func testTheDarkCoversTheScreenWhereverTheSpotGoes() {
        let k = EyeTower.darknessScale(in: retina)
        let s = EyeTower.spotSize(in: retina)
        let half = CGSize(width: s.width * k / 2, height: s.height * k / 2)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: retina.maxX, y: retina.maxY),
                       CGPoint(x: 0, y: retina.maxY), CGPoint(x: retina.maxX, y: 0)] {
            let dark = CGRect(x: corner.x - half.width, y: corner.y - half.height,
                              width: half.width * 2, height: half.height * 2)
            XCTAssertTrue(dark.contains(retina), "dark at \(corner) misses part of the screen")
        }
    }

    func testTheBeamHangsFromTheEyeAndItsFootLandsOnTheSpot() {
        let eye = EyeTower.eyeCenter(in: retina)
        let s = EyeTower.spotSize(in: retina)
        for spot in [CGPoint(x: 1400, y: 60), CGPoint(x: eye.x, y: 40), CGPoint(x: 100, y: 300)] {
            let b = EyeTower.beam(eye: eye, spot: spot, spotSize: s)
            // A layer hung by its top turns its "down" (0, -1) by `angle`.
            let reach = b.length / EyeTower.beamOvershoot
            let foot = CGPoint(x: eye.x + sin(b.angle) * reach, y: eye.y - cos(b.angle) * reach)
            XCTAssertEqual(foot.x, spot.x, accuracy: 0.5)
            XCTAssertEqual(foot.y, spot.y, accuracy: 0.5)
        }
    }

    func testThePupilStaysInsideTheEye() {
        let eye = EyeTower.eyeCenter(in: retina)
        let size = EyeTower.eyeSize(in: retina)
        for spot in [CGPoint(x: 0, y: 0), CGPoint(x: 1728, y: 0), CGPoint(x: 864, y: 1117)] {
            let o = EyeTower.pupilOffset(eye: eye, eyeSize: size, spot: spot, in: retina)
            XCTAssertLessThanOrEqual(abs(o.x), size.width * 0.25)
            XCTAssertLessThanOrEqual(abs(o.y), size.height * 0.15)
        }
    }

    func testTheSpritesDrawAndTheTowerShips() {
        XCTAssertNotNil(EyeTower.eyeSprite())
        XCTAssertNotNil(EyeTower.pupilSprite())
        XCTAssertNotNil(EyeTower.beamSprite())
        XCTAssertNotNil(EyeTower.darknessSprite(k: EyeTower.darknessScale(in: retina)))
        XCTAssertNotNil(EffectsResources.url("eye-tower", "png"))
    }
}
