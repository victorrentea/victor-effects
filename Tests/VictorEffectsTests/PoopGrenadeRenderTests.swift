import XCTest
import AppKit
import Metal
import QuartzCore
@testable import VictorEffects

/// 💩 87b, RENDERED offscreen (`OffscreenRenderer`, no display touched): the
/// broken glass with the splatter over it, on a pale slide. After the splats
/// have landed there has to be shit all round the hole, not only in it, and a
/// big 💩 sitting in the black hole itself. Leaves `poop-grenade-<t>.png` in
/// `$TMPDIR` to look at.
final class PoopGrenadeRenderTests: XCTestCase {
    func testShitLandsAllRoundAndA💩SitsInTheHole() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let w = 1440, h = 900
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let root = CALayer()
        root.frame = bounds
        root.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
        root.actions = ["sublayers": NSNull()]

        let c = CGPoint(x: 820, y: 430)
        let seed: UInt64 = 87
        let rh = GrenadeToss.holeRadius(at: c, in: bounds)
        let crack = GrenadeToss.crack(at: c, holeRadius: rh, seed: seed)
        let shards = GrenadeToss.shardImages(crack, shot: nil, bounds: bounds, scale: 1)
        let glass = GrenadeToss.makeCrack(crack, at: c, holeRadius: rh, in: bounds, shards: shards, scale: 1, seed: seed)
        let splatter = GrenadeToss.makePoopSplatter(at: c, holeRadius: rh, in: bounds, scale: 1, seed: seed)
        CATransaction.begin()
        root.addSublayer(glass.under)
        root.addSublayer(glass.over)
        root.addSublayer(splatter)
        CATransaction.commit()
        CATransaction.flush()
        let t0 = CACurrentMediaTime()

        let renderer = OffscreenRenderer(device: device, root: root, width: w, height: h)
        var last: [UInt8] = []
        // Real time, frame by frame, as the coffee test does: CARenderer is
        // only reliable on a clock that moves the way the layers' does.
        var shots = [0.15, 0.6, 1.2, 2.2]
        while let next = shots.first {
            CATransaction.flush()
            let now = CACurrentMediaTime()
            last = renderer.render(at: now)
            if now - t0 >= next {
                shots.removeFirst()
                renderer.writePNG(last, crop: bounds, to: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("poop-grenade-\(next).png"))
            }
            Thread.sleep(forTimeInterval: 1.0 / 60)
        }

        // BGRA, row 0 at the bottom. "Brown": red clearly over blue, dark-ish.
        func isBrown(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            let b = Int(last[i]), g = Int(last[i + 1]), r = Int(last[i + 2])
            return r > 60 && r < 200 && r - b > 40 && g < r && g > b
        }
        var inHole = 0, outside = 0, quadrants = Set<Int>()
        for y in stride(from: 0, to: h, by: 3) {
            for x in stride(from: 0, to: w, by: 3) where isBrown(x, y) {
                let d = hypot(CGFloat(x) - c.x, CGFloat(y) - c.y)
                if d < rh * 0.6 { inHole += 1 } else if d > rh * 1.2 {
                    outside += 1
                    quadrants.insert((x > Int(c.x) ? 1 : 0) + (y > Int(c.y) ? 2 : 0))
                }
            }
        }
        XCTAssertGreaterThan(inHole, 400, "a 💩 sits in the hole")
        XCTAssertGreaterThan(outside, 400, "shit splattered beyond the hole")
        XCTAssertGreaterThanOrEqual(quadrants.count, 3, "…and all round it, not to one side")
    }
}
