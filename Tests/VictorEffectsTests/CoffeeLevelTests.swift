import AppKit
import QuartzCore
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

    /// Nearly full, the coffee reaches the rim all round: no ring of white
    /// china between the liquid and the cup (2026-09-30 — Victor saw one
    /// just before the cup popped: the liquid image carried a transparent
    /// point of padding the china ellipse did not).
    func testANearlyFullCupHasNoWhiteRingRoundTheCoffee() throws {
        let shape = try XCTUnwrap(CoffeeInterior.measure())
        let box: CGFloat = 91, scale = 4
        let w = Int(box) * scale
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: w, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let glyph = CATextLayer()
        glyph.string = "☕"
        glyph.fontSize = 78
        glyph.alignmentMode = .center
        glyph.frame = CGRect(x: 0, y: 0, width: box, height: box)
        glyph.contentsScale = CGFloat(scale)
        let level = CoffeeLevelLayer(shape: shape, contentsScale: CGFloat(scale))
        glyph.addSublayer(level.layer)
        level.set(fill: 0.999)
        glyph.render(in: ctx)
        let px = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)

        // Every pixel inside the coffee's ellipse, bar half a point of edge
        // anti-aliasing, is liquid, not china.
        let e = shape.rect.insetBy(dx: 0.5, dy: 0.5)
        var light = 0
        for row in 0..<w {
            for col in 0..<w {
                let x = (CGFloat(col) + 0.5) / CGFloat(scale), y = box - (CGFloat(row) + 0.5) / CGFloat(scale)
                let dx = (x - e.midX) / (e.width / 2), dy = (y - e.midY) / (e.height / 2)
                guard dx * dx + dy * dy <= 1 else { continue }
                let i = row * w * 4 + col * 4
                if Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) > 450 { light += 1 }
            }
        }
        XCTAssertEqual(light, 0, "china showing inside the coffee of a nearly full cup")
    }
}
