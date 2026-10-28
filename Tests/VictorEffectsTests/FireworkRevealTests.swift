import AppKit
import XCTest
@testable import VictorEffects

/// The ring that reveals a drawn firework burst (`FireworkReveal`) — the
/// timing the per-line `strokeEnd`/`strokeStart` animations used to have.
final class FireworkRevealTests: XCTestCase {

    func testStopsAreAlwaysInOrderAndInsideTheMask() {
        for step in 0...200 {
            let stops = FireworkReveal.locations(at: Double(step) / 200, reach: 0.9).map(\.doubleValue)
            XCTAssertEqual(stops, stops.sorted(), "t=\(step)/200")
            XCTAssertGreaterThanOrEqual(stops.first!, 0)
            XCTAssertLessThanOrEqual(stops.last!, 1)
        }
    }

    func testHeadsReachFullLengthAtADrawFractionAndStayThere() {
        XCTAssertEqual(FireworkReveal.head(0), 0)
        XCTAssertLessThan(FireworkReveal.head(FireworkReveal.drawFraction / 2), 1)
        XCTAssertEqual(FireworkReveal.head(FireworkReveal.drawFraction), 1, accuracy: 1e-9)
        XCTAssertEqual(FireworkReveal.head(0.8), 1)
    }

    func testTailsWaitThenCatchUpWithTheHeadsAtTheEnd() {
        XCTAssertEqual(FireworkReveal.tail(FireworkReveal.tailStart), 0)
        XCTAssertGreaterThan(FireworkReveal.tail(0.5), 0)
        XCTAssertEqual(FireworkReveal.tail(1), 1, accuracy: 1e-9)
        let end = FireworkReveal.locations(at: 1, reach: 0.9).map(\.doubleValue)
        XCTAssertEqual(end[1], end[2], accuracy: 1e-9, "the ring has closed: nothing of the lines is left")
    }

    /// What a burst hands the window server in one commit (Instruments,
    /// Animation Hitches, 2026-10-28): a picture at 1×, in the render server's
    /// own BGRA layout, so applying the commit fits inside a 120 Hz frame.
    func testBurstPictureIsSmallAndInTheRenderServersLayout() throws {
        let palette: [NSColor] = [.red, .white]
        let streaks = (0..<8).map { i in
            EmojiAnimator.FireworkStreak(control: CGPoint(x: 100, y: CGFloat(i) * 10), end: CGPoint(x: 120, y: 0),
                                         color: palette[i % 2], width: 3, hasTip: false)
        }
        let picture = try XCTUnwrap(EmojiAnimator.fireworkPicture(
            streaks, palette: palette, half: 450, glowBlur: 8, scale: EmojiAnimator.fireworkPictureScale))
        XCTAssertEqual(picture.width, 900, "a big burst's ~900 pt square, at 1×")
        XCTAssertEqual(picture.alphaInfo, .premultipliedFirst)
        XCTAssertEqual(picture.bitmapInfo.intersection(.byteOrderMask), .byteOrder32Little)
    }
}
