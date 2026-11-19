import XCTest
@testable import VictorEffects

/// 🪲 ⌘⌃9: the beetle's route and timing, without a screen.
final class BugWalkTests: XCTestCase {
    /// The Retina in points, as the overlay sees it.
    private let retina = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    func testItStartsLowOnTheRightAndEndsUpOnTheLeft() {
        var rng = Seeded(state: 7)
        for _ in 0..<200 {
            let r = BugWalk.route(in: retina, using: &rng)
            // y up: the start box is in the lower third, the end box above the middle.
            XCTAssertGreaterThan(r.start.x, retina.width * 0.68)
            XCTAssertLessThan(r.start.y, retina.height * 0.32)
            XCTAssertLessThan(r.end.x, retina.width * 0.37)
            XCTAssertGreaterThan(r.end.y, retina.height * 0.55)
        }
    }

    func testTheWholeWalkStaysOnTheScreen() {
        var rng = Seeded(state: 42)
        for _ in 0..<200 {
            let r = BugWalk.route(in: retina, using: &rng)
            for i in 0...40 {
                let p = BugWalk.point(on: r, at: CGFloat(i) / 40)
                XCTAssertTrue(retina.contains(p), "\(p) left the screen")
            }
        }
    }

    func testTheCurveBeginsAndEndsOnItsPoints() {
        let r = BugWalk.Route(start: CGPoint(x: 10, y: 20), control: CGPoint(x: 300, y: 400), end: CGPoint(x: 90, y: 70))
        XCTAssertEqual(BugWalk.point(on: r, at: 0), r.start)
        XCTAssertEqual(BugWalk.point(on: r, at: 1), r.end)
    }

    func testLengthOfAStraightLineIsItsDistance() {
        let r = BugWalk.Route(start: .zero, control: CGPoint(x: 150, y: 0), end: CGPoint(x: 300, y: 0))
        XCTAssertEqual(BugWalk.length(of: r), 300, accuracy: 0.5)
    }

    func testTheWalkTakesSecondsNotAnInstantNorForever() {
        var rng = Seeded(state: 3)
        for _ in 0..<100 {
            let d = BugWalk.walkDuration(BugWalk.route(in: retina, using: &rng))
            XCTAssertGreaterThanOrEqual(d, BugWalk.minWalk)
            XCTAssertLessThanOrEqual(d, BugWalk.maxWalk)
        }
        let tiny = BugWalk.Route(start: .zero, control: .zero, end: CGPoint(x: 1, y: 0))
        XCTAssertEqual(BugWalk.walkDuration(tiny), BugWalk.minWalk)
    }

    func testSizeKeepsTheSpriteAspect() {
        let s = BugWalk.size(in: retina, sprite: CGSize(width: 199, height: 204))
        XCTAssertEqual(s.height, retina.height * BugWalk.heightShare, accuracy: 0.001)
        XCTAssertEqual(s.width / s.height, 199.0 / 204.0, accuracy: 0.001)
        XCTAssertEqual(BugWalk.size(in: retina, sprite: .zero), .zero)
    }

    func testTheStripIsCutIntoThirteenFrames() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 13 * 10, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let strip = try XCTUnwrap(ctx.makeImage())
        let frames = BugWalk.frames(from: strip)
        XCTAssertEqual(frames.count, 13)
        XCTAssertEqual(frames.first?.width, 10)
        XCTAssertEqual(frames.first?.height, 12)
    }
}
