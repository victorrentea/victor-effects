import XCTest
@testable import VictorEffects

/// 🎅 The hat must never change Clawd himself: same scale, same spot, only
/// more picture above and to the right. And it alternates.
final class PeekSantaHatTests: XCTestCase {

    private let icon = CGSize(width: 461, height: 363)   // claude-icon.png
    private let hat = CGSize(width: 230, height: 205)    // santa-hat.png
    private let pad: CGFloat = 7                          // ringWidth(forHeight: 363)
    private let plain = CGRect(x: 100, y: 400, width: 475, height: 377)

    private var hatted: CGRect {
        PeekSantaHat.frame(plainFrame: plain, icon: icon, hat: hat, pad: pad)
    }
    private var scale: CGFloat { plain.height / (icon.height + 2 * pad) }

    func testTheBodyKeepsItsScale() {
        let c = PeekSantaHat.canvas(icon: icon, hat: hat)
        XCTAssertEqual(hatted.height / (c.height + 2 * pad), scale, accuracy: 1e-9)
        XCTAssertEqual(hatted.width / (c.width + 2 * pad), scale, accuracy: 1e-9)
    }

    func testTheBodyStaysWhereItWas() {
        XCTAssertEqual(hatted.minX, plain.minX, accuracy: 1e-9, "the hat never reaches left of the head")
        XCTAssertEqual(hatted.minY, plain.minY, accuracy: 1e-9, "the feet stay put: the hat does not hang below them")
        XCTAssertEqual(hatted.maxY - plain.maxY, -PeekSantaHat.origin.y * scale, accuracy: 1e-9,
                       "the picture grows upwards by exactly the hat's overhang")
    }

    func testTheHatSitsOnTheRightCorner() {
        let headRight: CGFloat = 418
        XCTAssertLessThan(PeekSantaHat.origin.x, headRight, "the brim starts on the head")
        XCTAssertGreaterThan(PeekSantaHat.origin.x + hat.width, headRight + 40,
                             "the pompom hangs past the head, over the right hand")
        XCTAssertGreaterThanOrEqual(hat.width, (headRight - 43) / 3, "at least a third of the head")
    }

    func testEveryOtherEntrance() {
        XCTAssertTrue(PeekSantaHat.wears(stored: nil), "the first entrance shows it")
        var stored: Bool? = nil
        var seen: [Bool] = []
        for _ in 0..<4 {
            let wears = PeekSantaHat.wears(stored: stored)
            seen.append(wears)
            stored = !wears
        }
        XCTAssertEqual(seen, [true, false, true, false])
    }

    func testTheHatIsInTheBundle() throws {
        // Through the app's own loader: the test target has a bundle of its own.
        let image = try XCTUnwrap(EmojiAnimator.bundledPNG(PeekSantaHat.resource))
        XCTAssertEqual(CGSize(width: image.width, height: image.height), hat)
    }
}
