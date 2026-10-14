import AppKit
import Metal
import QuartzCore
import XCTest
@testable import VictorEffects

/// 🎆❄️ What the heavy full-screen effects cost the GPU, measured offscreen
/// through `CARenderer` — the render engine the window server uses, shadows,
/// offscreen passes and all — without touching a display that may be on a
/// projector.
///
/// Each effect is played in real time on a Retina-sized target (2× the overlay
/// screen's points) and every frame is timed from `beginFrame` to the GPU
/// finishing. The numbers are printed, and a frame from the busiest moment is
/// left in `$TMPDIR` (`<effect>-frame.png`) to look at.
///
/// The asserted budget is loose on purpose — the build machine is busy with
/// everything else running on it — but it sits well below what the versions
/// before 2026-10-14 cost (a blurred `shadow` on every streak, dot and flake,
/// re-rendered offscreen on every frame): fireworks 39 ms a frame on average
/// with a p95 of 178 ms, snow 27 ms. Since: ~4 ms and ~3 ms.
final class EffectsRenderCostTests: XCTestCase {

    /// Mean milliseconds per frame. A 120 Hz display has 8.3.
    static let budget = 12.0

    func testFireworksRenderCost() throws {
        let r = try measure(seconds: 4.5, snapshotAt: 3.1, name: "fireworks") { $0.showFireworks(playSound: false) }
        XCTAssertLessThan(r.mean, Self.budget, "fireworks mean frame")
    }

    func testSnowRenderCost() throws {
        let r = try measure(seconds: 6, snapshotAt: 5.5, name: "snow") { $0.showSnow() }
        XCTAssertLessThan(r.mean, Self.budget, "snow mean frame")
    }

    private func measure(seconds: Double, snapshotAt: Double, name: String,
                         _ start: (EmojiAnimator) -> Void) throws -> (mean: Double, p95: Double) {
        guard let screen = Screens.overlayScreen() else { throw XCTSkip("no overlay screen") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let pts = screen.frame.size
        let scale: CGFloat = 2
        let w = Int(pts.width * scale), h = Int(pts.height * scale)

        // Pixel-sized root scaling a point-sized host, as a Retina window does.
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: w, height: h)
        root.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor   // a white-ish slide
        root.actions = ["sublayers": NSNull()]
        let host = CALayer()
        host.anchorPoint = .zero
        host.bounds = CGRect(origin: .zero, size: pts)
        host.position = .zero
        host.transform = CATransform3DMakeScale(scale, scale, 1)
        host.actions = ["sublayers": NSNull()]
        root.addSublayer(host)

        let animator = EmojiAnimator(hostLayer: host)
        defer { animator.stopAllActiveEffects() }

        let renderer = OffscreenRenderer(device: device, root: root, width: w, height: h)
        start(animator)
        let t0 = CACurrentMediaTime()
        var frames: [Double] = []
        var snapped = false
        while CACurrentMediaTime() - t0 < seconds {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0 / 120))
            CATransaction.flush()
            let f0 = CACurrentMediaTime()
            renderer.renderTimed(at: f0)
            frames.append((CACurrentMediaTime() - f0) * 1000)
            if !snapped, f0 - t0 >= snapshotAt {
                snapped = true
                let bytes = renderer.render(at: CACurrentMediaTime())
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-frame.png")
                renderer.writePNG(bytes, crop: CGRect(x: 0, y: 0, width: w, height: h), to: url)
                print("📸 \(name) frame: \(url.path)")
            }
        }
        let sorted = frames.sorted()
        let mean = frames.reduce(0, +) / Double(frames.count)
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        print(String(format: "⏱️ %@ @ %dx%d: %d frames in %.1fs, mean %.2f ms, p95 %.2f ms, worst %.2f ms",
                     name, w, h, frames.count, seconds, mean, p95, sorted.last!))
        return (mean, p95)
    }
}

extension OffscreenRenderer {
    /// A frame drawn and waited for on the GPU, with no read-back.
    func renderTimed(at time: CFTimeInterval) {
        renderer.beginFrame(atTime: time, timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let cb = queue.makeCommandBuffer()!
        cb.commit()
        cb.waitUntilCompleted()
    }
}
