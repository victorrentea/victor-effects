import AppKit
import CoreImage
import QuartzCore

/// ⛈️ The storm that rolls in on tile #20: four clouds slide in from the two
/// sides onto the top edge, the desktop goes dark under them, and it rains for
/// the length of the clip.
///
/// Everything here is either a **pure function of the overlay bounds** (where
/// each cloud starts, where it stops) or a **cached drawing** (the cloud
/// sprites, the rain streak) — the same bargain as `WazzupCorner` and
/// `TvStatic`, so the layout can be tested without a screen and the press costs
/// no rendering after the first one.
///
/// **The clouds are drawn, not photographed.** A cut-out photo would have to be
/// licensed to sit in a public repo, and it would arrive at one resolution for
/// a band that is 46 % of whatever screen the overlay lands on. Drawing them is
/// also what buys four clouds that are visibly *different* from each other out
/// of one function: the silhouette is a seeded pile of lobes, so cloud #3 is not
/// cloud #1 shifted sideways, which is the tell that gives a repeated sprite
/// away when two of them overlap along the same edge.
enum RainStorm {

    // MARK: - The clip

    /// The tile's own audio (rain, with six rolls of thunder in it). The visual
    /// lasts exactly as long as this plays.
    static let soundName = "20_storm.mp3"

    /// Measured 18.90 s. Only used when `soundsDir` has no copy to ask.
    static let fallbackDuration: Double = 18.9

    /// Where the thunder rolls sit inside the clip, in seconds — measured off
    /// the file with a 50 ms RMS envelope, keeping the four loudest and
    /// dropping two that sat inside another's tail.
    ///
    /// The lightning is fired from the **press** path, which is a different HTTP
    /// request from the one that starts the audio, so these land within a
    /// couple hundred ms of the sound rather than on its exact sample. That is
    /// affordable *here* and would not be for the FBI knock or the heartbeat:
    /// every roll in this recording swells over ~300 ms, and a flash inside a
    /// swell reads as the flash that caused it. It is also what keeps the tile
    /// working when the tablet plays the clip through its own speaker and the
    /// Mac never sees a `/sound/play` at all.
    static let thunderOnsets: [Double] = [2.70, 5.45, 9.40, 14.45]

    // MARK: - Timeline

    /// How long a cloud takes to cross from off-screen to its resting place.
    /// Slow enough to read as weather arriving rather than as a wipe.
    static let cloudSlideSeconds: Double = 2.3

    /// The four clouds do not arrive together — that reads as one image cut in
    /// half. Index → its head start, so the outer pair leads and the inner pair
    /// closes the gap behind it.
    static let cloudDelays: [Double] = [0.00, 0.30, 0.15, 0.45]

    /// The desktop dims to this, over [darkenSeconds]. Not black: what is being
    /// darkened is a live demo, and the room still has to be able to read it —
    /// the same trade `TvStatic.defaultAlpha` makes.
    ///
    /// The ramp has to be **over before the first roll of thunder** — a screen
    /// still visibly darkening when the lightning goes off reads as the flash
    /// dimming the desktop, which is backwards. `RainStormTests` holds it there.
    static let darkenOpacity: Float = 0.62
    static let darkenSeconds: Double = 2.4

    /// Rain does not start until there is something for it to fall out of: the
    /// first cloud is most of the way across by here, and the drops ramp up to
    /// full over [rainRampSeconds] instead of switching on.
    static let rainLeadIn: Double = 1.5
    static let rainRampSeconds: Double = 2.6

    /// The whole storm fades out together at the end of the clip — clouds,
    /// darkness and rain — rather than the clouds sliding back out. A retreat
    /// would cost another 2.3 s after the sound has already stopped.
    static let fadeOutSeconds: Double = 1.4

    /// One lightning flash: a stutter, not a fade. Real lightning is two or
    /// three strokes a few tens of ms apart, and a single smooth ramp up and
    /// down looks like someone turning a lamp on.
    static let flashSeconds: Double = 0.55
    static let flashOpacities: [Float] = [0, 0.55, 0.08, 0.38, 0.05, 0]
    static let flashKeyTimes: [NSNumber] = [0, 0.04, 0.12, 0.2, 0.34, 1.0]

    // MARK: - The cloud band

    static let cloudCount = 4

    /// Each cloud is nearly half the screen wide, so four of them overlap into
    /// one continuous ceiling instead of four separate blobs in a row.
    static let cloudWidthFraction: CGFloat = 0.44
    static let cloudAspect: CGFloat = 0.58        // height ÷ width

    /// Where the clouds come to rest, as fractions of the screen width. The
    /// outer two deliberately hang off the edges: a cloud that stops neatly
    /// inside the frame reads as a sticker, one that is cut by the screen edge
    /// reads as part of a sky that continues past it.
    static let cloudCentres: [CGFloat] = [0.08, 0.36, 0.64, 0.92]

    /// How far each cloud's top is pushed above the top edge, as a fraction of
    /// its own height, and how far its base is dropped below the others. Both
    /// are what keep the band from looking like four things aligned on a ruler.
    static let cloudOverhang: [CGFloat] = [0.34, 0.24, 0.38, 0.26]
    static let cloudDip: [CGFloat] = [0.00, 0.09, 0.03, 0.12]

    /// One cloud's entrance: where it ends up, where it comes from, and when.
    struct Arrival {
        let rest: CGRect
        let start: CGRect
        let fromLeft: Bool
        let delay: Double
    }

    /// The four entrances, in overlay coordinates (**bottom-origin, y up**, like
    /// every other layer this app hangs on the panel).
    ///
    /// Two clouds come from the left and two from the right, and each one starts
    /// *fully* off-screen — its trailing edge exactly on the screen edge, not a
    /// corner still poking in.
    static func arrivals(in bounds: CGRect) -> [Arrival] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let w = bounds.width * cloudWidthFraction
        let h = w * cloudAspect
        return (0..<cloudCount).map { i in
            let cx = bounds.width * cloudCentres[i]
            let top = bounds.height + h * cloudOverhang[i] - h * cloudDip[i]
            let rest = CGRect(x: cx - w / 2, y: top - h, width: w, height: h)
            let fromLeft = i < cloudCount / 2
            let start = fromLeft
                ? rest.offsetBy(dx: -rest.maxX, dy: 0)
                : rest.offsetBy(dx: bounds.width - rest.minX, dy: 0)
            return Arrival(rest: rest, start: start, fromLeft: fromLeft, delay: cloudDelays[i])
        }
    }

    /// The line the rain falls out of: the **lowest** cloud base in the band, so
    /// no drop is ever born in clear sky above a cloud that is still covering
    /// it. Falls back to the top edge when there are no clouds to ask.
    static func rainLineY(in bounds: CGRect) -> CGFloat {
        arrivals(in: bounds).map { $0.rest.minY }.min() ?? bounds.height
    }

    // MARK: - Drawing a cloud

    /// A deterministic little generator, so the four silhouettes differ from
    /// each other but never from one press to the next: the sprite cache below
    /// is keyed on the index, and a cloud that re-rendered differently on a
    /// re-press would pop.
    private struct Seeded {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }
        mutating func next() -> Double {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Double(state % 1_000_000) / 1_000_000
        }
        mutating func next(_ range: ClosedRange<Double>) -> Double {
            range.lowerBound + next() * (range.upperBound - range.lowerBound)
        }
    }

    /// Lobes of one cloud. **Every number is in units of the cloud's WIDTH**,
    /// including the vertical ones, so a lobe is a true circle on screen rather
    /// than an ellipse squashed by the box's aspect — the whole point of the
    /// pile is that it reads as billows. `y` is measured up from the cloud's
    /// base, and no lobe reaches past [cloudAspect] (the box's height in those
    /// same units), which is what keeps the sprite inside its own frame.
    ///
    /// Returned rather than drawn so the shape can be inspected in a test.
    static func lobes(seed: Int) -> [(centre: CGPoint, radius: CGFloat)] {
        var rng = Seeded(UInt64(seed) &+ 11)
        let count = 7
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            // Fat in the middle, tapering to the ends — a cumulus silhouette,
            // not a row of equal bubbles.
            let bulge = 1 - abs(t - 0.5) * 1.3
            let r = (0.085 + 0.145 * bulge) * rng.next(0.85...1.15)
            // Placed by its OWN radius rather than on a fixed span: the end
            // lobes are the small ones, and spacing them evenly hung them off
            // the side of the sprite — where the blur canvas cuts them into a
            // straight vertical edge, the one thing that gives a drawn cloud
            // away. The jitter is what [spritePadding] has to cover.
            let x = r + (1 - 2 * r) * t + rng.next(-0.03...0.03)
            let y = r * 0.75 + 0.10
            return (CGPoint(x: x, y: y), CGFloat(r))
        }
    }

    /// A lobe's centre and radius in the sprite's own pixels.
    private static func lobeRects(seed: Int, in rect: CGRect) -> [(centre: CGPoint, radius: CGFloat)] {
        let u = rect.width
        return lobes(seed: seed).map { lobe in
            (CGPoint(x: rect.minX + lobe.centre.x * u, y: rect.minY + lobe.centre.y * u), lobe.radius * u)
        }
    }

    /// The silhouette: the lobes plus a flat-ish slab that closes their bases
    /// into one mass. Without the slab the gaps between lobes show as notches
    /// along the bottom, which reads as a caterpillar rather than as a cloud.
    static func silhouette(seed: Int, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let base = CGRect(x: rect.minX + rect.width * 0.07,
                          y: rect.minY,
                          width: rect.width * 0.86,
                          height: rect.width * 0.17)
        path.addRoundedRect(in: base, cornerWidth: base.height * 0.45, cornerHeight: base.height * 0.45)
        for lobe in lobeRects(seed: seed, in: rect) {
            path.addEllipse(in: CGRect(x: lobe.centre.x - lobe.radius, y: lobe.centre.y - lobe.radius,
                                       width: lobe.radius * 2, height: lobe.radius * 2))
        }
        return path
    }

    /// Rendered sprites, keyed `index@WxH`. A press has to be instant; the first
    /// one pays for the blur and every later one is a dictionary hit.
    private static var spriteCache: [String: CGImage] = [:]

    /// One storm cloud, `size` points at `scale`, transparent outside the
    /// silhouette.
    ///
    /// Three passes make it read as weather rather than as a grey shape: a
    /// vertical gradient (slate at the top, near-black at the base — a cloud
    /// heavy enough to rain is lit from above and dark underneath), a soft
    /// highlight per lobe so the mass has volume, and a **Gaussian blur over
    /// the whole thing** so the outline is vapour and not a cut edge. The blur
    /// is why the canvas carries [spritePadding] of slack on every side: a blur
    /// clipped at the bitmap edge puts a hard line exactly where the softness
    /// was supposed to be.
    static func cloudImage(index: Int, size: CGSize, scale: CGFloat) -> CGImage? {
        let key = "\(index)@\(Int(size.width * scale))x\(Int(size.height * scale))"
        if let cached = spriteCache[key] { return cached }
        guard size.width > 1, size.height > 1 else { return nil }

        let px = CGSize(width: size.width * scale, height: size.height * scale)
        let pad = px.width * spritePadding
        let canvas = CGSize(width: px.width + pad * 2, height: px.height + pad * 2)
        guard let ctx = CGContext(data: nil,
                                  width: Int(canvas.width), height: Int(canvas.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let body = CGRect(x: pad, y: pad, width: px.width, height: px.height)
        let path = silhouette(seed: index, in: body)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        // Slate above, storm-belly below.
        let space = CGColorSpaceCreateDeviceRGB()
        let stops: [CGFloat] = [
            0.13, 0.15, 0.18, 1,   // base
            0.26, 0.29, 0.34, 1,
            0.44, 0.48, 0.54, 1,
            0.56, 0.60, 0.66, 1,   // top
        ]
        if let gradient = CGGradient(colorSpace: space, colorComponents: stops,
                                     locations: [0, 0.34, 0.74, 1], count: 4) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: body.minY),
                                   end: CGPoint(x: 0, y: body.maxY),
                                   options: [])
        }

        // Volume: a soft light on the upper-left shoulder of every lobe.
        for lobe in lobeRects(seed: index, in: body) {
            let r = lobe.radius
            let highlight = CGPoint(x: lobe.centre.x - r * 0.22, y: lobe.centre.y + r * 0.34)
            if let glow = CGGradient(colorSpace: space,
                                     colorComponents: [1, 1, 1, 0.17, 1, 1, 1, 0],
                                     locations: [0, 1], count: 2) {
                ctx.drawRadialGradient(glow, startCenter: highlight, startRadius: 0,
                                       endCenter: highlight, endRadius: r * 1.15, options: [])
            }
        }
        ctx.restoreGState()

        guard let sharp = ctx.makeImage() else { return nil }
        let blurred = blur(sharp, radius: px.width * blurFraction) ?? sharp
        spriteCache[key] = blurred
        return blurred
    }

    /// Slack around the sprite, as a fraction of its width, so the blur has
    /// somewhere to go.
    static let spritePadding: CGFloat = 0.06
    /// Blur radius, as a fraction of the sprite's width. Enough to turn the
    /// outline into vapour, not so much that the lobes melt into one pillow.
    static let blurFraction: CGFloat = 0.007

    private static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        // Crop back to the original extent: CIGaussianBlur grows the image, and
        // a layer given the grown one would scale the cloud down to fit.
        return CIContext().createCGImage(output, from: input.extent)
    }

    // MARK: - Rain

    /// One drop, as a streak: rain read from across a room is lines, not dots.
    /// White and nearly opaque at the head, transparent at the tail, so a drop
    /// looks like it is moving even in a still frame.
    static func dropImage(scale: CGFloat) -> CGImage? {
        let key = "drop@\(Int(scale * 100))"
        if let cached = spriteCache[key] { return cached }
        let w = max(2, Int(2 * scale)), h = max(8, Int(26 * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                        colorComponents: [0.82, 0.88, 1.0, 0.95,
                                                          0.82, 0.88, 1.0, 0.0],
                                        locations: [0, 1], count: 2) else { return nil }
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(h)),
                               options: [])
        guard let image = ctx.makeImage() else { return nil }
        spriteCache[key] = image
        return image
    }

    /// Drops per second at full downpour. Tuned on a 1512-point-wide retina:
    /// dense enough to be unmistakably rain, sparse enough that the demo behind
    /// it is still legible.
    static let dropsPerSecond: Float = 900
    /// Points per second. Real rain is far faster; at real speed the streaks
    /// blur into vertical lines and stop reading as individual drops.
    static let dropSpeed: CGFloat = 1500

    /// The emitter, positioned on the cloud base and wide enough to keep raining
    /// while the wind pushes the drops sideways.
    static func rainLayer(in bounds: CGRect, scale: CGFloat) -> CAEmitterLayer? {
        guard let drop = dropImage(scale: scale) else { return nil }
        let lineY = rainLineY(in: bounds)

        let cell = CAEmitterCell()
        cell.contents = drop
        cell.birthRate = dropsPerSecond
        // Long enough to clear the tallest screen from the cloud base, whatever
        // the wind does to the path.
        cell.lifetime = Float(bounds.height / dropSpeed) * 1.6 + 0.4
        cell.velocity = dropSpeed
        cell.velocityRange = dropSpeed * 0.22
        // Straight down is 90° in emitter space; the offset is the wind.
        cell.emissionLongitude = -.pi / 2 + 0.10
        cell.emissionRange = 0.06
        cell.scale = 1.0
        cell.scaleRange = 0.45
        cell.alphaRange = 0.35
        cell.alphaSpeed = -0.25

        let layer = CAEmitterLayer()
        layer.frame = bounds
        layer.emitterShape = .line
        layer.emitterMode = .surface
        layer.emitterPosition = CGPoint(x: bounds.midX, y: lineY)
        layer.emitterSize = CGSize(width: bounds.width * 1.35, height: 1)
        layer.emitterCells = [cell]
        layer.renderMode = .additive
        // The layer's own birthRate is a MULTIPLIER over the cell's, and it is
        // left at 1 on purpose: the caller ramps it from 0 with a `.backwards`
        // animation, so the sky is dry until there are clouds to rain out of and
        // the downpour then builds instead of switching on. Parking the model
        // value at 0 here would mean a storm that stops raining the moment that
        // animation is removed.
        return layer
    }
}
