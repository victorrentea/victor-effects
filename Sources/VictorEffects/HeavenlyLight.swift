import AppKit
import QuartzCore

/// 😇 The light that comes down on tile #61, Bocelli's Hallelujah (2026-10-22,
/// Victor: *"să fie lumină, îngeri … să se coboare lumină pe ecran, să văd încă
/// translucent, dar să fie emoție de îngerească"*).
///
/// Four things, all of them see-through — the slide under them has to stay
/// readable, it is the demo being blessed, not replaced:
///
///   1. a warm glow pouring down from the top edge,
///   2. a fan of soft god-rays out of a point above the screen, breathing and
///      swaying slowly,
///   3. golden motes drifting down through them,
///   4. three 👼 gliding down into the light, hovering, and rising back to
///      heaven as the song ends.
///
/// The glow and the rays arrive as one piece, sliding DOWN from above the top
/// edge while they fade in: that is the "light coming down". A reveal mask
/// would read the same, but a mask over rays that sway is an offscreen pass on
/// every frame for the length of the song; a slide costs nothing.
///
/// Like `RainStorm`, everything here is a pure function of the bounds or a
/// cached drawing, so the layout is testable without a screen and a press
/// renders no bitmap after the first.
enum HeavenlyLight {

    // MARK: - The clip

    static let soundName = "61_hallelujah.mp3"

    /// Measured 17.1 s (the clip ends in a 2.5 s fade-out, before the final climax). Only used when `soundsDir` has no copy to ask.
    static let fallbackDuration: Double = 17.1

    // MARK: - Timeline

    /// The light slides down from above and fades in over this long.
    static let descendSeconds: Double = 3.6
    /// How far above its resting place the light starts, in screen heights.
    static let descendFrom: CGFloat = 0.55
    /// The whole thing fades away over this long when the song is over.
    static let fadeOutSeconds: Double = 1.6
    /// The angels start back up this long before the end of the clip, so they
    /// are visibly leaving while the last "Hallelujah" is still sounding.
    static let ascendLead: Double = 2.4

    // MARK: - Glow

    /// Alpha of the glow at the very top edge. The brightest thing on screen,
    /// and still see-through: text right under the menu bar stays legible.
    static let glowTopAlpha: CGFloat = 0.42
    /// Warm white, a touch of gold — not pure white, which reads as a flash.
    static let lightColor = (r: CGFloat(1.0), g: CGFloat(0.92), b: CGFloat(0.66))

    // MARK: - Rays

    struct Ray: Equatable {
        /// Rotation around the source, radians; 0 is straight down.
        let angle: CGFloat
        let width: CGFloat
        let length: CGFloat
        /// Resting opacity; the breathing dips below it and comes back.
        let opacity: Float
        /// One breath, seconds (autoreversed).
        let breathSeconds: Double
        /// One sway to the side and back, radians and seconds.
        let sway: CGFloat
        let swaySeconds: Double
    }

    static let rayCount = 9

    /// Where every ray comes from: above the top edge, a little off centre so
    /// the fan does not look drawn with a compass.
    static func source(in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.midX + bounds.width * 0.06, y: bounds.maxY + bounds.height * 0.35)
    }

    /// The fan, seeded: the same screen always gets the same light, so a
    /// rehearsal shows what the room will see.
    static func rays(in bounds: CGRect) -> [Ray] {
        var rng = SplitMix(seed: 61)
        let spread: CGFloat = 0.62            // ±35°
        return (0..<rayCount).map { i in
            let t = CGFloat(i) / CGFloat(rayCount - 1) * 2 - 1     // -1…1
            let jitter = CGFloat(rng.next(in: -0.06...0.06))
            return Ray(
                angle: t * spread + jitter,
                width: bounds.width * CGFloat(rng.next(in: 0.05...0.13)),
                length: bounds.height * 1.9,
                opacity: Float(rng.next(in: 0.26...0.42)),
                breathSeconds: rng.next(in: 2.4...4.2),
                sway: CGFloat(rng.next(in: 0.015...0.035)),
                swaySeconds: rng.next(in: 5.5...9.0))
        }
    }

    // MARK: - Angels

    struct Angel: Equatable {
        let rest: CGPoint
        let size: CGFloat
        let delay: Double
        let bob: CGFloat
        let bobSeconds: Double
    }

    /// Three, the middle one higher and larger. They rest in the top third:
    /// lower and they sit on the code being shown.
    static func angels(in bounds: CGRect) -> [Angel] {
        let h = bounds.height, w = bounds.width
        return [
            Angel(rest: CGPoint(x: bounds.minX + w * 0.20, y: bounds.maxY - h * 0.26),
                  size: h * 0.10, delay: 1.4, bob: h * 0.012, bobSeconds: 2.3),
            Angel(rest: CGPoint(x: bounds.midX, y: bounds.maxY - h * 0.17),
                  size: h * 0.13, delay: 0.8, bob: h * 0.015, bobSeconds: 2.8),
            Angel(rest: CGPoint(x: bounds.minX + w * 0.80, y: bounds.maxY - h * 0.28),
                  size: h * 0.10, delay: 2.0, bob: h * 0.012, bobSeconds: 2.5),
        ]
    }

    static let angelSlideSeconds: Double = 4.2
    /// Angels are see-through too, just less than the light.
    static let angelOpacity: Float = 0.88

    // MARK: - Sprites

    private static var spriteCache: [String: CGImage] = [:]

    /// One ray, drawn once and stretched by every beam: soft on both sides
    /// (a gaussian across), brightest where it enters the screen and gone
    /// before the floor. Pixel by pixel rather than with gradients, because
    /// the falloff wanted is a product of two curves.
    static func raySprite() -> CGImage? {
        if let cached = spriteCache["ray"] { return cached }
        let w = 64, h = 256
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let c = lightColor
        for y in 0..<h {
            // Row 0 is the TOP of the image (CGImage rows run top-down).
            let v = Double(y) / Double(h - 1)
            let along = pow(max(0, 1 - v / 0.92), 1.6)
            for x in 0..<w {
                let u = (Double(x) / Double(w - 1)) * 2 - 1
                let across = exp(-u * u * 3.2) - exp(-3.2)
                let a = max(0, min(1, along * across / (1 - exp(-3.2))))
                let i = (y * w + x) * 4
                px[i]     = UInt8(Double(c.r) * a * 255)
                px[i + 1] = UInt8(Double(c.g) * a * 255)
                px[i + 2] = UInt8(Double(c.b) * a * 255)
                px[i + 3] = UInt8(a * 255)
            }
        }
        let image = px.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        spriteCache["ray"] = image
        return image
    }

    /// A soft round mote of light for the emitter.
    static func moteSprite() -> CGImage? {
        if let cached = spriteCache["mote"] { return cached }
        let s = 32
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                        colorComponents: [1.0, 0.98, 0.88, 1.0,
                                                          1.0, 0.88, 0.50, 0.55,
                                                          1.0, 0.85, 0.40, 0.0],
                                        locations: [0, 0.3, 1], count: 3) else { return nil }
        let mid = CGPoint(x: CGFloat(s) / 2, y: CGFloat(s) / 2)
        ctx.drawRadialGradient(gradient, startCenter: mid, startRadius: 0,
                               endCenter: mid, endRadius: CGFloat(s) / 2, options: [])
        let image = ctx.makeImage()
        spriteCache["mote"] = image
        return image
    }

    /// 👼 as a bitmap, so the layer can scale and fade it without re-laying
    /// out text every frame.
    static func angelSprite(points: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "angel@\(Int(points * scale))"
        if let cached = spriteCache[key] { return cached }
        let px = Int(ceil(points * scale))
        guard px > 0,
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let text = NSAttributedString(string: "👼", attributes: [.font: NSFont.systemFont(ofSize: CGFloat(px) * 0.82)])
        let size = text.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        text.draw(at: CGPoint(x: (CGFloat(px) - size.width) / 2, y: (CGFloat(px) - size.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        let image = ctx.makeImage()
        spriteCache[key] = image
        return image
    }

    /// The halo behind each angel.
    static func haloSprite() -> CGImage? {
        if let cached = spriteCache["halo"] { return cached }
        let s = 128
        let c = lightColor
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                        colorComponents: [c.r, c.g, c.b, 0.75,
                                                          c.r, c.g, c.b, 0.25,
                                                          c.r, c.g, c.b, 0.0],
                                        locations: [0, 0.45, 1], count: 3) else { return nil }
        let mid = CGPoint(x: CGFloat(s) / 2, y: CGFloat(s) / 2)
        ctx.drawRadialGradient(gradient, startCenter: mid, startRadius: 0,
                               endCenter: mid, endRadius: CGFloat(s) / 2, options: [])
        let image = ctx.makeImage()
        spriteCache["halo"] = image
        return image
    }

    // MARK: - Seeded randomness

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func next(in range: ClosedRange<Double>) -> Double {
            range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
        }
    }
}
