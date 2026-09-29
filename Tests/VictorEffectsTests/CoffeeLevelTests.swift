import XCTest
@testable import VictorEffects

/// The cup rises empty and the pot fills it — the geometry of the level,
/// tested without a screen.
final class CoffeeLevelTests: XCTestCase {

    /// The coffee is found in the upper half of ☕ and is a wide, flat ellipse.
    func testTheCoffeeIsFoundInTheGlyph() throws {
        let shape = try XCTUnwrap(CoffeeInterior.measure())
        XCTAssertGreaterThan(shape.rect.midY, 91 / 2, "the coffee is above the saucer")
        XCTAssertGreaterThan(shape.rect.width, shape.rect.height * 2, "seen from above: flat")
        XCTAssertGreaterThan(shape.coffee.width, 0)
    }

    /// A glyph with no coffee has no level to paint.
    func testAnEmojiWithoutCoffeeHasNoLevel() {
        XCTAssertNil(CoffeeInterior.measure(emoji: " "))
    }

    /// Full is the glyph's own coffee, exactly where it was.
    func testAFullCupIsTheGlyphsOwnCoffee() {
        let size = CGSize(width: 46, height: 15)
        XCTAssertEqual(CoffeeInterior.liquidFrame(in: size, fill: 1), CGRect(origin: .zero, size: size))
    }

    /// Pouring widens the surface and lifts it, never the other way round.
    func testTheLevelRisesAndWidensAsItFills() {
        let size = CGSize(width: 46, height: 15)
        var last = CoffeeInterior.liquidFrame(in: size, fill: 0)
        for i in 1...10 {
            let now = CoffeeInterior.liquidFrame(in: size, fill: CGFloat(i) / 10)
            XCTAssertGreaterThan(now.midY, last.midY)
            XCTAssertGreaterThan(now.width, last.width)
            last = now
        }
        XCTAssertEqual(CoffeeInterior.surfaceDrop(rectHeight: 15, box: 91, fill: 1), 0)
        XCTAssertGreaterThan(CoffeeInterior.surfaceDrop(rectHeight: 15, box: 91, fill: 0), 0)
    }
}
