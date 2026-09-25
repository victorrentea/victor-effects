import XCTest
@testable import VictorEffects

final class CoffeePotTests: XCTestCase {
    /// The tip is found on the glyph itself: on its far left, ABOVE the middle
    /// — the old hand-set offset assumed below, and the stream left the pot
    /// ~30 pt away from its tip.
    func testSpoutIsFoundInTheUpperLeftOfTheGlyph() {
        let g = CoffeePot.measure(size: 252)
        XCTAssertLessThan(g.spout.x, 0.25)
        XCTAssertGreaterThan(g.spout.y, 0.55)
        XCTAssertLessThan(g.spout.y, 0.8)
        XCTAssertGreaterThan(g.spout.y, g.belly.y, "the spout rises above the belly")
        XCTAssertEqual(g.belly.x, 0.5, accuracy: 0.1)
    }

    /// A different box scales the same glyph: the unit tip does not move.
    func testSpoutIsTheSameAtAnySize() {
        let a = CoffeePot.measure(size: 252), b = CoffeePot.measure(size: 168)
        XCTAssertEqual(a.spout.x, b.spout.x, accuracy: 0.02)
        XCTAssertEqual(a.spout.y, b.spout.y, accuracy: 0.02)
    }

    private let range: ClosedRange<CGFloat> = 0.35...1.25
    private let spoutAngle = CoffeePot.fallback.spoutAngle   // up-left, ~158°

    /// Turned by the lean, the spout points AT the cup (when the lean is in range).
    func testTheLeanPointsTheSpoutAtTheCup() {
        let spout = CGPoint(x: 500, y: 500)
        let cup = CGPoint(x: 500 - 60, y: 500 - 30)   // down-left of the tip
        let tilt = CoffeePot.aimTilt(spout: spout, cup: cup, spoutAngle: spoutAngle, range: range)
        XCTAssertTrue(range.contains(tilt))
        // Compare directions, not raw angles: they may differ by a turn.
        let pointed = spoutAngle + tilt, wanted = atan2(CGFloat(-30), CGFloat(-60))
        XCTAssertEqual(cos(pointed), cos(wanted), accuracy: 0.001)
        XCTAssertEqual(sin(pointed), sin(wanted), accuracy: 0.001)
    }

    /// The lower the cup sits under the tip, the harder the pot bends.
    func testALowerCupBendsThePotFurther() {
        let spout = CGPoint(x: 500, y: 500)
        let shallow = CoffeePot.aimTilt(spout: spout, cup: CGPoint(x: 440, y: 490),
                                        spoutAngle: spoutAngle, range: range)
        let steep = CoffeePot.aimTilt(spout: spout, cup: CGPoint(x: 460, y: 440),
                                      spoutAngle: spoutAngle, range: range)
        XCTAssertGreaterThan(steep, shallow)
    }

    /// Straight below, under the belly, behind the pot, or right at the tip:
    /// the pot never stands on its lid or leans back — full forward lean.
    func testCupsThePotCannotPointAtGetTheFullLean() {
        let spout = CGPoint(x: 500, y: 500)
        for cup in [CGPoint(x: 500, y: 380), CGPoint(x: 560, y: 450),
                    CGPoint(x: 580, y: 560), CGPoint(x: 503, y: 498)] {
            XCTAssertEqual(CoffeePot.aimTilt(spout: spout, cup: cup, spoutAngle: spoutAngle, range: range),
                           range.upperBound, "cup at \(cup)")
        }
    }

    /// A cup level with (or above) the tip still gets a visible lean.
    func testALevelCupGetsTheLeastLean() {
        let tilt = CoffeePot.aimTilt(spout: CGPoint(x: 500, y: 500), cup: CGPoint(x: 400, y: 520),
                                     spoutAngle: spoutAngle, range: range)
        XCTAssertEqual(tilt, range.lowerBound)
    }

    func testEaseMovesPartWayAndNeverOvershoots() {
        let t = CoffeePot.ease(0.2, toward: 1.2, dt: 1.0 / 60)
        XCTAssertGreaterThan(t, 0.2)
        XCTAssertLessThan(t, 1.2)
        XCTAssertEqual(CoffeePot.ease(0.2, toward: 1.2, dt: 5), 1.2, accuracy: 1e-9)
    }
}
