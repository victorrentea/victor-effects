import XCTest
@testable import VictorEffects

/// The stream ends on the coffee, and the pop is small unless the screen is
/// flooded — the pure halves of both, tested without a screen.
final class CoffeeSurfaceTests: XCTestCase {

    /// The coffee is found in the glyph, a little above the box's centre (the
    /// cup's rim is in the upper half of ☕; the saucer fills the lower one).
    func testTheSurfaceIsFoundJustAboveTheMiddleOfTheCup() {
        let lift = CoffeeSurface.measure()
        XCTAssertGreaterThan(lift, 0.0, "the coffee sits above the box's centre")
        XCTAssertLessThan(lift, 0.2, "…but inside the cup, not up in the steam")
        XCTAssertEqual(lift, CoffeeSurface.fallback, accuracy: 0.04,
                       "the glyph moved: look at it before trusting the new number")
    }

    /// A glyph with no coffee in it measures nothing and falls back.
    func testAnEmojiWithoutCoffeeFallsBack() {
        XCTAssertEqual(CoffeeSurface.measure(emoji: " "), CoffeeSurface.fallback)
    }

    /// The glyph grows about its centre, so the surface climbs as it swells.
    func testTheSurfaceRisesAsTheCupSwells() {
        let small = CoffeeSurface.surfaceY(centerY: 300, box: 91, scale: 1.3, lift: 0.055)
        let full = CoffeeSurface.surfaceY(centerY: 300, box: 91, scale: 1.3 * 1.7, lift: 0.055)
        XCTAssertGreaterThan(small, 300)
        XCTAssertGreaterThan(full, small)
    }

    /// Dropped from higher, a drop needs longer; shot upward, longer still.
    /// Falling `h` from rest takes √(2h/g).
    func testFallTimeFollowsTheParabola() {
        XCTAssertEqual(CoffeePot.fallTime(drop: 700, speed: 0, angle: 0, gravity: 1400), 1.0, accuracy: 1e-9)
        let down = CoffeePot.fallTime(drop: 100, speed: 90, angle: -.pi / 2, gravity: 1400)
        let flat = CoffeePot.fallTime(drop: 100, speed: 90, angle: 0, gravity: 1400)
        let up = CoffeePot.fallTime(drop: 100, speed: 90, angle: .pi / 2, gravity: 1400)
        XCTAssertLessThan(down, flat)
        XCTAssertLessThan(flat, up)
        XCTAssertLessThan(CoffeePot.fallTime(drop: 50, speed: 90, angle: 0, gravity: 1400), flat)
    }

    // MARK: - How big the pop is

    /// One cup, or a few: the quiet dissolve, in big chunks.
    func testAFewCalmCupsPopSmall() {
        for n in 1...CoffeeBurst.quietCups {
            let s = CoffeeBurst.size(armed: false, intensity: 0, cupsOnScreen: n)
            XCTAssertEqual(s.violence, 1.0, "\(n) cups")
            XCTAssertEqual(s.grid, CoffeeBurst.calmGrid)
        }
    }

    /// A crowd that built up without a salvo pops harder, up to a cap.
    func testACrowdOnScreenPopsBigger() {
        let few = CoffeeBurst.size(armed: false, intensity: 0, cupsOnScreen: 3).violence
        let some = CoffeeBurst.size(armed: false, intensity: 0, cupsOnScreen: 6).violence
        let flood = CoffeeBurst.size(armed: false, intensity: 0, cupsOnScreen: CoffeeBurst.floodCups).violence
        let more = CoffeeBurst.size(armed: false, intensity: 0, cupsOnScreen: 40).violence
        XCTAssertLessThan(few, some)
        XCTAssertLessThan(some, flood)
        XCTAssertEqual(flood, CoffeeBurst.calmViolence.upperBound)
        XCTAssertEqual(more, flood, "capped")
    }

    /// A salvo is the big one — bigger than any calm pop, whatever is on screen.
    func testASalvoBurstsBiggerThanAnyCalmPop() {
        let calmMax = CoffeeBurst.size(armed: false, intensity: 0, cupsOnScreen: 99)
        let salvo = CoffeeBurst.size(armed: true, intensity: 0, cupsOnScreen: 1)
        XCTAssertGreaterThan(salvo.violence, calmMax.violence)
        XCTAssertGreaterThan(salvo.grid, calmMax.grid)
        XCTAssertEqual(CoffeeBurst.size(armed: true, intensity: 1, cupsOnScreen: 1).violence,
                       CoffeeBurst.stormViolence.upperBound)
    }
}
