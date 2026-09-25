import AppKit
import Metal
import QuartzCore
import XCTest
@testable import VictorEffects

/// The pour, RENDERED — offscreen, through `CARenderer`, which draws emitters
/// and masks exactly as the window server does, without touching a display
/// (the overlay screen may be on a projector). The stream is a particle
/// emitter, so "it ends at the coffee" is only true or false in pixels: the
/// frame is drawn twice at the same instant, with and without the stream, and
/// every pixel the stream adds must sit ABOVE the cup's coffee surface.
///
/// Each run leaves `coffee-pour.png` in the temp directory (the path is
/// printed) — open it to see the pot, the stream and the cup.
final class CoffeePourRenderTests: XCTestCase {

    func testTheStreamEndsAtTheCoffeeSurface() throws {
        guard let screen = Screens.overlayScreen() else { throw XCTSkip("no overlay screen") }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let w = Int(screen.frame.width), h = Int(screen.frame.height)

        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: w, height: h)
        root.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
        // As the overlay's own root behaves: an NSView-backed layer has no
        // implicit actions. A bare CALayer fades its WHOLE tree on every
        // sublayer added (the "sublayers" transition), which ghosts whatever
        // is moving — a frame the room never sees.
        root.actions = ["sublayers": NSNull()]
        let animator = EmojiAnimator(hostLayer: root)
        animator.potHidesPointer = false
        defer { animator.stopAllActiveEffects() }

        animator.spawnEmoji("☕")
        let carrier = try XCTUnwrap(root.sublayers?.last, "the cup's carrier")
        let cup = carrier.position
        // The spout above the coffee, inside the cup's hit box. (The spout
        // pours down-LEFT at full lean, so a tip over the cup's left rim
        // lands on the rim — the clip still holds there, but this is the
        // picture worth looking at.)
        let tipLocal = CGPoint(x: cup.x + 6, y: cup.y + 72)
        let tipGlobal = CGPoint(x: tipLocal.x + screen.frame.minX, y: tipLocal.y + screen.frame.minY)

        let renderer = OffscreenRenderer(device: device, root: root, width: w, height: h)
        // Pour for ~0.5 s of real time (a cup fills in 1.2 s, so it does not
        // pop mid-test), drawing along the way so the particles are simulated.
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 0.5 {
            _ = animator.tickCoffeePour(cursorGlobalPoint: tipGlobal)
            CATransaction.flush()
            renderer.render(at: CACurrentMediaTime())
            Thread.sleep(forTimeInterval: 1.0 / 60)
        }
        let stream = try XCTUnwrap(root.sublayers?.compactMap { $0 as? CAEmitterLayer }.first, "the stream")
        let clip = try XCTUnwrap(stream.mask, "the stream is clipped")
        let surface = clip.frame.minY

        // The surface is inside the cup: above its centre, below its rim.
        XCTAssertGreaterThan(surface, carrier.position.y)
        XCTAssertLessThan(surface, carrier.position.y + 91 * 0.25 * 1.7)

        let t = CACurrentMediaTime()
        let with = renderer.render(at: t)
        stream.isHidden = true
        CATransaction.flush()
        let without = renderer.render(at: t)
        stream.isHidden = false

        var streamPixels = 0, belowSurface = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let d = abs(Int(with[i]) - Int(without[i])) + abs(Int(with[i + 1]) - Int(without[i + 1]))
                    + abs(Int(with[i + 2]) - Int(without[i + 2]))
                guard d > 24 else { continue }
                streamPixels += 1
                // Texture row y is layer y (bottom-up); a pixel's centre is y + 0.5.
                if CGFloat(y) + 0.5 < surface - 1 { belowSurface += 1 }
            }
        }
        XCTAssertGreaterThan(streamPixels, 50, "the pot is pouring something")
        XCTAssertEqual(belowSurface, 0, "stream pixels below the coffee surface at y=\(surface)")

        // For the eye: the region around the cup and the pot, right way up.
        let crop = CGRect(x: max(0, cup.x - 260), y: max(0, cup.y - 110), width: 520, height: 420)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coffee-pour.png")
        renderer.writePNG(with, crop: crop, to: url)
        print("☕ pour frame: \(url.path)")
    }
}

/// Draws a layer tree into a Metal texture and reads it back as BGRA bytes,
/// row 0 at the BOTTOM (layer space).
struct OffscreenRenderer {
    let device: MTLDevice
    let texture: MTLTexture
    let renderer: CARenderer
    let queue: MTLCommandQueue
    let width: Int, height: Int

    init(device: MTLDevice, root: CALayer, width: Int, height: Int) {
        self.device = device
        self.width = width
        self.height = height
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                            height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        texture = device.makeTexture(descriptor: desc)!
        queue = device.makeCommandQueue()!
        // The renderer's own queue, so the read-back blit is ordered after the
        // frame: on a second queue it can overtake it, and the bytes come back
        // half one frame, half the one before (a ghost of whatever moved).
        renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = root.bounds
    }

    @discardableResult
    func render(at time: CFTimeInterval) -> [UInt8] {
        renderer.beginFrame(atTime: time, timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let cb = queue.makeCommandBuffer()!
        let blit = cb.makeBlitCommandEncoder()!
        blit.synchronize(resource: texture)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    func writePNG(_ bytes: [UInt8], crop: CGRect, to url: URL) {
        let cw = Int(crop.width), ch = Int(crop.height), cx = Int(crop.minX), cy = Int(crop.minY)
        var out = [UInt8](repeating: 0, count: cw * ch * 4)
        for row in 0..<ch {
            let srcY = cy + (ch - 1 - row)          // flip: PNG row 0 is the top
            guard srcY >= 0, srcY < height else { continue }
            for x in 0..<cw where cx + x < width {
                let s = (srcY * width + cx + x) * 4, d = (row * cw + x) * 4
                out[d] = bytes[s]; out[d + 1] = bytes[s + 1]; out[d + 2] = bytes[s + 2]; out[d + 3] = bytes[s + 3]
            }
        }
        let ctx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)!
        guard let img = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
