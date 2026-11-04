import AppKit
import CoreGraphics
import Metal
import QuartzCore
import XCTest
@testable import VictorEffects

final class TsunamiTests: XCTestCase {

    private let screen = CGSize(width: 1728, height: 1117)

    /// The sweep's edge sits behind the water on every row — the frontmost
    /// row exactly `margin` behind the lip, a trailing row as far behind as
    /// its water trails — from the top row down to the bottom one.
    func testTheSweptEdgeRidesBehindTheWaterOnEveryRow() {
        let frame = try! XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let sprite = Tsunami.Sprite(frames: [frame], front: [0.5, 1.0])
        let edge = sprite.edge(size: CGSize(width: 200, height: 100), margin: 4)
        XCTAssertEqual(edge.map(\.x), [-104, -4])
        XCTAssertEqual(edge.map(\.y), [75, 25])
    }

    /// The old screen survives exactly where the water has not reached, row by
    /// row, even where the edge is concave — the one polygon through the edge
    /// came out with a diagonal wedge already swept.
    func testTheAheadMaskKeepsTheOldScreenRightOfTheEdgeOnEveryRow() {
        // Three rows, top to bottom: crest far back, a hollow further back, sea ahead.
        let edge = [CGPoint(x: -300, y: 150), CGPoint(x: -500, y: 90), CGPoint(x: -20, y: 30)]
        let path = Tsunami.aheadPath(edge: edge, width: 800, height: 180)
        for (pt, row) in zip(edge, ["crest", "hollow", "sea"]) {
            XCTAssertTrue(path.contains(CGPoint(x: pt.x + 5, y: pt.y)), "\(row): just ahead of the water is still the old screen")
            XCTAssertFalse(path.contains(CGPoint(x: pt.x - 5, y: pt.y)), "\(row): just behind it is swept")
        }
        // The wedge's spot: high up, between the hollow's edge and the crest's.
        XCTAssertFalse(path.contains(CGPoint(x: -400, y: 160)))
        XCTAssertTrue(path.contains(CGPoint(x: 790, y: 179)), "ahead reaches the screen's top right")
        XCTAssertTrue(path.contains(CGPoint(x: 790, y: 1)), "and its bottom right")
    }

    /// Self-termination: the effect ends with the clip, but never before the
    /// wave has crossed, left and dried.
    func testLivesForTheClipButNeverCutsTheWaveShort() {
        XCTAssertEqual(Tsunami.totalDuration(clip: 7.3), 7.3)
        XCTAssertGreaterThanOrEqual(Tsunami.totalDuration(clip: 1),
                                    Tsunami.frontEnters + Tsunami.frontCrosses * Double(1 + Tsunami.bodyShare))
    }

    /// `/compact` comes up only after the water has left, and its three blinks
    /// are over as the dark starts to fade, on the real clip and on a short one.
    func testThePromptLivesBetweenTheWaveAndTheFade() {
        let waveGone = Tsunami.frontEnters + Tsunami.frontCrosses + Tsunami.spriteExit
        for clip in [7.3, 1] {
            let total = Tsunami.totalDuration(clip: clip)
            let w = Tsunami.promptWindow(waveGone: waveGone, total: total)
            XCTAssertGreaterThan(w.start, waveGone)
            XCTAssertEqual(w.end, total - Tsunami.fadeOut, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual((w.end - w.start) / Double(Tsunami.cursorBlinks), 0.5,
                                        "a blink faster than this reads as a flicker")
        }
    }

    /// Rendered, because a layer tree only tells what was asked for: nothing on
    /// the glass before its time, the cursor lit, dark, lit again at the instants
    /// the track says, dead centre, and the whole prompt leaving with the dark.
    /// Leaves `tsunami-compact.png` in the temp directory to look at.
    func testTheCommandIsThereDeadCentreAndItsCursorBlinks() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let w = 1440, h = 900, total = 7.3
        let red = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        red.setFillColor(CGColor(red: 0.8, green: 0, blue: 0, alpha: 1))
        red.fill(CGRect(x: 0, y: 0, width: 4, height: 4))

        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: w, height: h)
        root.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor // the desktop the fade gives back
        root.actions = ["sublayers": NSNull()]
        let clock0 = CACurrentMediaTime()
        root.addSublayer(Tsunami.makeLayer(in: root.bounds, prepared: .init(shot: try XCTUnwrap(red.makeImage())),
                                           clock0: clock0, total: total, scale: 2))
        // Renderer first: a tree committed before it exists never reaches it.
        let renderer = OffscreenRenderer(device: device, root: root, width: w, height: h)
        CATransaction.flush()

        func frame(_ t: Double) -> (bytes: [UInt8], box: (minX: Int, maxX: Int, count: Int)) {
            let bytes = renderer.render(at: clock0 + t)
            var minX = w, maxX = 0, count = 0
            for y in (h / 2 - 80)..<(h / 2 + 80) {
                for x in (w / 2 - 260)..<(w / 2 + 260) {
                    let i = (y * w + x) * 4
                    if bytes[i] > 200, bytes[i + 1] > 200, bytes[i + 2] > 200 {
                        count += 1; minX = min(minX, x); maxX = max(maxX, x)
                    }
                }
            }
            return (bytes, (minX, maxX, count))
        }

        // The drawn wave: gone at 0.35 + 2.5 × 1.714, so the prompt is up from
        // about 4.73 and each of the three on/off pairs takes about 0.56 s.
        let window = Tsunami.promptWindow(waveGone: Tsunami.frontEnters + Tsunami.frontCrosses * Double(1 + Tsunami.bodyShare * 1.7),
                                          total: total)
        let step = (window.end - window.start) / Double(2 * Tsunami.cursorBlinks)
        XCTAssertEqual(frame(0.2).box.count, 0, "nothing before the wave")
        for n in 0..<Tsunami.cursorBlinks {
            let lit = frame(window.start + (Double(2 * n) + 0.5) * step).box
            let dark = frame(window.start + (Double(2 * n) + 1.5) * step).box
            XCTAssertGreaterThan(dark.count, 500, "blink \(n + 1): the text stays while the cursor is off")
            XCTAssertGreaterThan(lit.count, dark.count + 1000, "blink \(n + 1): the cursor is a solid block")
            XCTAssertEqual((lit.minX + lit.maxX) / 2, w / 2, accuracy: 6, "blink \(n + 1): text and cursor are centred")
        }
        let afterBlinks = frame(window.end + 0.05).box
        XCTAssertGreaterThan(afterBlinks.count, 1500, "the cursor stays lit as the fade starts")
        XCTAssertEqual(frame(total - 0.1).box.count, 0, "gone with the dark")

        let lit = frame(window.start + 0.5 * step).bytes
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tsunami-compact.png")
        renderer.writePNG(lit, crop: CGRect(x: 0, y: 0, width: w, height: h), to: url)
        print("🌊 /compact frame: \(url.path)")
    }

    /// Exactly three times dark, lit first, on the even grid discrete mode wants.
    func testTheCursorGoesDarkThreeTimes() {
        let track = Tsunami.cursorTrack(blinks: Tsunami.cursorBlinks)
        XCTAssertEqual(track.values, [1, 0, 1, 0, 1, 0])
        XCTAssertEqual(track.keyTimes.count, track.values.count + 1)
        XCTAssertEqual(track.keyTimes.first, 0)
        XCTAssertEqual(track.keyTimes.last, 1)
    }

    /// The filmed wave's front, read off its frames: the rightmost pixel each
    /// row has opaque in most frames, and the sky rows above take the crest's.
    func testFrontProfileFollowsTheWaterAndFillsTheSky() {
        // 4×3, top to bottom: sky, crest reaching x=1, sea reaching x=3.
        let a: [UInt8] = [0, 0, 0, 0,
                          255, 255, 0, 0,
                          255, 255, 255, 255]
        XCTAssertEqual(Tsunami.frontProfile(alpha: [a, a], width: 4, height: 3), [0.5, 0.5, 1])
        // A splash in one frame of three is not the front.
        var splash = a; splash[7] = 255
        XCTAssertEqual(Tsunami.frontProfile(alpha: [a, a, splash], width: 4, height: 3)[1], 0.5)
    }

    /// Where the sweep edge sits: as far as the water reaches in its shortest
    /// frame, and the hollow under the curl counts as not reached — else what
    /// the wave leaves shows through the barrel (Victor, 2026-11-03).
    func testSweepProfileStopsAtTheHollowAndAtTheShortestFrame() {
        // 10 wide, top to bottom: sky, curl (back face 0-2, hollow 3-6, lip 7-8),
        // sea reaching 9, sea with a one-pixel fleck of foam texture at 4.
        let o: UInt8 = 255
        let a: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                          o, o, o, 0, 0, 0, 0, o, o, 0,
                          o, o, o, o, o, o, o, o, o, 0,
                          o, o, o, o, 0, o, o, o, o, o]
        XCTAssertEqual(Tsunami.sweepProfile(alpha: [a], width: 10, height: 4, minHole: 3), [0.3, 0.3, 0.9, 1])
        // The sea breathes: one frame's is shorter, and that frame decides.
        var short = a; short[27] = 0; short[28] = 0
        XCTAssertEqual(Tsunami.sweepProfile(alpha: [a, short], width: 10, height: 4, minHole: 3)[2], 0.7)
        // The edge follows the sweep, not the front.
        let frame = try! XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let sprite = Tsunami.Sprite(frames: [frame], front: [0.9, 1.0], sweep: [0.3, 1.0])
        XCTAssertEqual(sprite.edge(size: CGSize(width: 100, height: 100), margin: 0).map(\.x), [-70, 0])
    }

    /// A speck of spray left of the crest is not where the water ends: the old
    /// screen stayed up above the crest because of it (Victor, 2026-11-04).
    func testASpeckOfSprayDoesNotHoldTheSweepBack() {
        let o: UInt8 = 255
        let row: [UInt8] = [o, 0, 0, 0, 0, o, o, o, o, 0]
        XCTAssertEqual(Tsunami.sweepProfile(alpha: [row], width: 10, height: 1, minHole: 3), [0.9])
    }

    /// The crest's rows go by the front, the hollow's stay on the sweep.
    func testTheCrestIsSweptByTheFront() {
        let sweep = [CGFloat](repeating: 0.1, count: 100), front = [CGFloat](repeating: 0.8, count: 100)
        let swept = Tsunami.crestSwept(sweep: sweep, front: front)
        XCTAssertEqual(swept[0], 0.8)
        XCTAssertEqual(swept[Int(Tsunami.crestShare * 100) - 1], 0.8)
        XCTAssertEqual(swept[Int(Tsunami.crestShare * 100)], 0.1)
    }
}
