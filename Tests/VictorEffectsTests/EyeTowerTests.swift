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

    /// 2026-11-27: the slit was taller than the almond and poked out above and
    /// below it whenever it looked aside, where the almond is thinner.
    func testTheSlitFitsTheAlmondWhereverItLooks() {
        let eye = EyeTower.eyeCenter(in: retina)
        let size = EyeTower.eyeSize(in: retina)
        let w = size.height * 0.30
        let almond = EyeTower.almond(in: CGRect(x: -size.width / 2, y: -size.height / 2,
                                                width: size.width, height: size.height))
        for spot in [CGPoint(x: 0, y: 0), CGPoint(x: retina.maxX, y: 0), CGPoint(x: eye.x, y: 0),
                     CGPoint(x: retina.maxX, y: eye.y - 200), CGPoint(x: 0, y: eye.y - 200)] {
            let o = EyeTower.pupilOffset(eye: eye, eyeSize: size, spot: spot, in: retina)
            let h = EyeTower.pupilHeight(eyeSize: size, offset: o, pupilWidth: w)
            XCTAssertGreaterThan(h, size.height * 0.35, "the slit all but vanished looking at \(spot)")
            for dx in [-w / 4, 0, w / 4] {
                for dy in [-h / 2, h / 2] {
                    let p = CGPoint(x: o.x + dx, y: o.y + dy)
                    XCTAssertTrue(almond.contains(p), "the slit pokes out at \(p) looking at \(spot)")
                }
            }
        }
    }

    /// 2026-11-27: the first coverage reader asked for an alpha-only bitmap
    /// with a colour space, got nil, read every block as empty — and the
    /// tower fell as nothing.
    func testTheRealTowerBreaksIntoMasonry() throws {
        let url = try XCTUnwrap(EffectsResources.url("eye-tower", "png"))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let coverage = EyeTower.alphaCoverage(img)
        XCTAssertGreaterThan(coverage(CGRect(x: 0.3, y: 0, width: 0.4, height: 0.2)), 0.5, "the foot is solid stone")
        XCTAssertLessThan(coverage(CGRect(x: 0, y: 0.9, width: 0.1, height: 0.1)), 0.1, "the sky beside the horns is empty")
        var rng = SystemRandomNumberGenerator()
        let pieces = EyeTower.pieces(cols: 6, rows: 16, coverage: coverage, using: &rng)
        XCTAssertGreaterThan(pieces.count, 40)
        XCTAssertLessThan(pieces.count, 6 * 16 + 16)
        // The foot gives first, the top follows.
        let low = pieces.filter { $0.unit.midY < 0.2 }.map { $0.delay }.max() ?? 0
        let high = pieces.filter { $0.unit.midY > 0.8 }.map { $0.delay }.min() ?? 0
        XCTAssertLessThan(low, high)
    }

    func testAClickCountsOnTheTowerAndNotBesideIt() {
        let hit = EyeTower.towerHitRect(in: retina)
        let t = EyeTower.towerFrame(in: retina)
        XCTAssertTrue(hit.contains(CGPoint(x: t.midX, y: t.minY + t.height * 0.3)))
        XCTAssertTrue(hit.contains(EyeTower.eyeCenter(in: retina)))
        XCTAssertFalse(hit.contains(CGPoint(x: retina.midX, y: retina.midY)))
    }

    func testTheSpritesDrawAndTheTowerShips() {
        XCTAssertNotNil(EyeTower.eyeSprite())
        XCTAssertNotNil(EyeTower.pupilSprite())
        XCTAssertNotNil(EyeTower.beamSprite())
        XCTAssertNotNil(EyeTower.flameSprite())
        XCTAssertNotNil(EyeTower.darknessSprite(k: EyeTower.darknessScale(in: retina)))
        XCTAssertNotNil(EffectsResources.url("eye-tower", "png"))
    }
}
