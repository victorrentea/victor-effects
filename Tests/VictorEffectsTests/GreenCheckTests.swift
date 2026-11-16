import XCTest
import AppKit
import Metal
import QuartzCore
@testable import VictorEffects

/// ✅ Tile #57: the green tick. The geometry is pure, so the promises Victor
/// made about it are checked headlessly — it fills the screen, and the pen
/// travels left to right — and then it is RENDERED offscreen
/// (`OffscreenRenderer`, no display touched) mid-swipe and finished. Leaves
/// `green-check-<t>.png` in `$TMPDIR` to look at.
final class GreenCheckTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testItFillsTheVisibleDesktopAndStaysOnIt() {
        let box = GreenCheck.box(in: bounds, topInset: 38)
        XCTAssertGreaterThan(box.height, (bounds.height - 38) * 0.8, "big: on the whole screen")
        XCTAssertEqual(box.midX, bounds.midX, accuracy: 0.5)
        XCTAssertEqual(box.midY, (bounds.height - 38) / 2, accuracy: 0.5, "centred under the menu bar")
        let half = GreenCheck.brush * box.height / 2 * 1.1   // fullest brush, waver included
        let visible = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 38)
        let line = GreenCheck.centreline(in: box)
        for p in line.down + line.up {
            XCTAssertTrue(visible.contains(CGRect(x: p.x - half, y: p.y - half, width: 2 * half, height: 2 * half)),
                          "the ink, brush width included, stays on the visible desktop (\(p))")
        }
        let ys = (line.down + line.up).map(\.y)
        XCTAssertGreaterThan(ys.max()! - ys.min()! + 2 * half, visible.height * 0.85, "the ink itself, not just its box")
    }

    func testThePenTravelsLeftToRightDownThenUp() {
        let line = GreenCheck.centreline(in: GreenCheck.box(in: bounds, topInset: 38))
        let pen = line.down + line.up.dropFirst()
        for (a, b) in zip(pen, pen.dropFirst()) {
            XCTAssertGreaterThan(b.x, a.x, "a swipe from left to right never doubles back")
        }
        XCTAssertLessThan(line.down.last!.y, line.down.first!.y, "the short stroke goes down")
        XCTAssertGreaterThan(line.up.last!.y, line.down.first!.y, "the long one ends above where the pen started")
        XCTAssertGreaterThan(GreenCheck.length(line.up), GreenCheck.length(line.down) * 1.7, "a tick, not a V")
    }

    func testItIsOverInsideTwoAndAHalfSeconds() {
        XCTAssertLessThan(GreenCheck.drawDuration, 0.6, "inside the chime's attack")
        XCTAssertLessThan(GreenCheck.totalDuration, 2.5)
    }

    func testRenderedTheSwipeUncoversItFromTheLeft() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let w = Int(bounds.width), h = Int(bounds.height)
        let root = CALayer()
        root.frame = bounds
        root.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
        root.actions = ["sublayers": NSNull()]
        let t0 = CACurrentMediaTime() + 0.05
        CATransaction.begin()
        root.addSublayer(GreenCheck.makeLayer(in: bounds, topInset: 38, scale: 1, now: t0))
        CATransaction.commit()
        CATransaction.flush()

        let renderer = OffscreenRenderer(device: device, root: root, width: w, height: h)
        // BGRA, row 0 at the bottom. Green pixels left and right of the corner.
        let cornerX = Int(GreenCheck.centreline(in: GreenCheck.box(in: bounds, topInset: 38)).up[0].x)
        func green(_ px: [UInt8]) -> (left: Int, right: Int) {
            var l = 0, r = 0
            for y in stride(from: 0, to: h, by: 3) {
                for x in stride(from: 0, to: w, by: 3) {
                    let i = (y * w + x) * 4
                    let b = Int(px[i]), g = Int(px[i + 1]), red = Int(px[i + 2])
                    if g > 150 && g - red > 70 && g - b > 70 { if x < cornerX - 80 { l += 1 } else if x > cornerX + 80 { r += 1 } }
                }
            }
            return (l, r)
        }
        var counts: [Double: (left: Int, right: Int)] = [:]
        var shots = [0.14, 0.30, 1.0, 2.15]
        while let next = shots.first {
            CATransaction.flush()
            let now = CACurrentMediaTime()
            let px = renderer.render(at: now)
            if now - t0 >= next {
                shots.removeFirst()
                counts[next] = green(px)
                renderer.writePNG(px, crop: bounds, to: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("green-check-\(next).png"))
            }
            Thread.sleep(forTimeInterval: 1.0 / 60)
        }
        XCTAssertGreaterThan(counts[0.14]!.left, 300, "the short stroke is being laid down")
        XCTAssertEqual(counts[0.14]!.right, 0, "…and nothing right of the corner yet")
        XCTAssertGreaterThan(counts[1.0]!.left, 1500)
        XCTAssertGreaterThan(counts[1.0]!.right, counts[1.0]!.left, "finished: the long stroke is most of the ink")
        XCTAssertLessThan(counts[2.15]!.right, counts[1.0]!.right / 4, "and it has all but faded by the end")
    }
}
