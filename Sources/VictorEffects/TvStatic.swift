import AppKit
import QuartzCore

/// 📺 TV white noise — the "purici" an analogue set shows with no signal. Used
/// as the 💀 game-over backdrop, under the GAME OVER picture and under the CRT
/// shutdown that closes over it.
///
/// Cheap on purpose, because it runs under an effect that must not drop frames:
/// a handful of noise bitmaps are rendered ONCE at a quarter of the screen's
/// resolution and then cycled on a `CAKeyframeAnimation` over `contents` with
/// `calculationMode = .discrete` — so the animation swaps a cached CGImage per
/// tick and nothing is generated while the effect is on screen. Blowing the
/// quarter-size bitmap back up with `magnificationFilter = .nearest` is what
/// makes the grain read as television static rather than as grey mush: the
/// pixels stay square and hard-edged, which is exactly what the real thing looks
/// like on any screen bigger than a phone.
///
/// **Translucent by design** (`defaultAlpha`): the tile is a gag played over
/// whatever is being demoed, and the desktop has to stay readable through it.
enum TvStatic {

    /// Frames in the loop. Fewer than ~4 and the eye catches the repeat; more
    /// than ~6 buys nothing at this frame rate.
    static let frameCount = 6
    /// Frames per second. Real static is faster, but above ~20 fps the grain
    /// averages out into flat grey — 16 keeps it boiling and visibly random.
    static let fps: Double = 16
    /// Enough to read as a switched-off set, sheer enough to keep the desktop
    /// legible underneath.
    static let defaultAlpha: Float = 0.55
    /// The noise is rendered at 1/4 the screen's size and scaled back up. The
    /// chunkier pixel is the look, and it is 16× less memory and drawing.
    static let downscale: CGFloat = 4

    /// One frame of black-and-white noise, `width`×`height` pixels. Binary
    /// black/white rather than random greys: mid-greys average into a flat wash
    /// once the layer is translucent, and the speckle is the whole point.
    static func noiseImage(width: Int, height: Int,
                           random: (() -> UInt8)? = nil) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let roll = random ?? { UInt8.random(in: 0...1) == 0 ? 0 : 255 }
        var pixels = [UInt8](repeating: 0, count: width * height)
        for i in 0..<pixels.count { pixels[i] = roll() }
        let space = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// The frames for a given screen size, rendered once and kept. A press must
    /// be instant: the picture has to be up on the same frame as the sound.
    private static var cache: [String: [CGImage]] = [:]

    static func frames(for size: CGSize) -> [CGImage] {
        let w = max(1, Int(size.width / downscale))
        let h = max(1, Int(size.height / downscale))
        let key = "\(w)x\(h)"
        if let cached = cache[key] { return cached }
        let built = (0..<frameCount).compactMap { _ in noiseImage(width: w, height: h) }
        cache[key] = built
        return built
    }

    /// A full-bounds layer showing looping static. Returns nil only if the noise
    /// could not be rendered, which leaves the caller's backdrop simply absent
    /// rather than crashing an effect mid-press.
    static func makeLayer(in bounds: CGRect, alpha: Float = defaultAlpha) -> CALayer? {
        let images = frames(for: bounds.size)
        guard let first = images.first else { return nil }

        let layer = CALayer()
        layer.frame = bounds
        layer.contents = first
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest   // square pixels = static, not mush
        layer.minificationFilter = .nearest
        layer.opacity = alpha

        guard images.count > 1 else { return layer }
        let flicker = CAKeyframeAnimation(keyPath: "contents")
        flicker.values = images
        flicker.calculationMode = .discrete     // swap frames, never cross-fade them
        flicker.duration = Double(images.count) / fps
        flicker.repeatCount = .infinity
        flicker.isRemovedOnCompletion = false
        layer.add(flicker, forKey: "tvStatic")
        return layer
    }
}
