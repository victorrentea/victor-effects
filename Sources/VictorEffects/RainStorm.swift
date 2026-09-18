import AppKit
import CoreImage
import ImageIO
import QuartzCore

/// ⛈️ The storm that rolls in on tile #20: seven clouds slide in from the two
/// sides onto the top edge, the desktop goes dark under them, and it rains for
/// the length of the clip.
///
/// Everything here is either a **pure function of the overlay bounds** (where
/// each cloud starts, where it stops) or a **cached drawing** (the cloud
/// sprites, the rain streak) — the same bargain as `WazzupCorner` and
/// `TvStatic`, so the layout can be tested without a screen and the press costs
/// no rendering after the first one.
///
/// **The clouds are photographs** (`Resources/clouds/cloud-0…6.png`), cut out of
/// two public-domain skies — see that folder's `CREDITS.md`. The drawn ones they
/// replaced are still here as [cloudImage]'s fallback and are still what a
/// missing sprite gets: a seeded pile of lobes with a gradient and a blur, good
/// enough that nobody in a room would have called it wrong, and visibly not a
/// photograph once a real cumulus is beside it.
///
/// Finding the photographs was most of the work, and the reason is worth
/// writing down: the matte is keyed off the SKY, so a picture only works if its
/// sky is a saturated, even blue right up to the cloud's edge. Almost every
/// cloud photograph is hazy near its subject — pale blue against white cloud is
/// no key at all — and a scored sweep of ~50 public-domain candidates produced
/// exactly three usable ones. Hence three cumulus FORMS across seven sprites,
/// mirrored and re-cropped, arranged so no two neighbours in the band share a
/// form and a mirror never sits beside its original.
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

    /// The clouds do not arrive together — that reads as one image cut in half.
    /// Index → its head start, interleaved so the band closes from both sides
    /// at once rather than sweeping across.
    static let cloudDelays: [Double] = [0.00, 0.34, 0.14, 0.46, 0.22, 0.52, 0.08]

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

    /// **Seven, not four** (Victor, 2026-09-19: *"be more, smaller, and a bit
    /// higher"*). Four clouds at nearly half the screen each made a ceiling
    /// a third of the way down the desktop — plenty of weather, but it ate the
    /// demo underneath, and at that size the seven lobes of one cloud read as
    /// individual bubbles. Smaller clouds also mean more *edges* along the
    /// band's base, which is where an overcast sky actually looks ragged.
    static let cloudCount = 7

    /// Each cloud is about a third of the screen wide, so consecutive ones
    /// overlap by more than half their width and the band is continuous rather
    /// than seven separate blobs in a row. It went up from 0.28 when the drawn
    /// clouds became photographs: a drawn one was a solid slab of alpha and
    /// butted cleanly against its neighbour, while a CUT-OUT has a ragged
    /// silhouette that feathers to nothing at its own edges — two of those
    /// meeting leave a notch of bright desktop between them unless they overlap
    /// much harder.
    static let cloudWidthFraction: CGFloat = 0.34
    /// Height ÷ width. **This is the sprite files' own aspect** (1200 × 780), not
    /// a free parameter: the photographs are cut to it, base-anchored, so the
    /// box never squashes a cloud. Change one and the other has to follow.
    static let cloudAspect: CGFloat = 0.65

    /// Where the clouds come to rest, as fractions of the screen width. The
    /// outermost two deliberately hang off the edges: a cloud that stops neatly
    /// inside the frame reads as a sticker, one that is cut by the screen edge
    /// reads as part of a sky that continues past it.
    static let cloudCentres: [CGFloat] = [0.04, 0.20, 0.36, 0.52, 0.68, 0.84, 1.00]

    /// How far each cloud's top is pushed above the top edge, as a fraction of
    /// its own height, and how far its base is dropped below the others. Both
    /// are what keep the band from looking like seven things aligned on a ruler
    /// — and together with the smaller clouds they are what "a bit higher" is:
    /// the band now hangs about 23 % of the way down instead of a third.
    static let cloudOverhang: [CGFloat] = [0.46, 0.42, 0.50, 0.44, 0.48, 0.40, 0.45]
    static let cloudDip: [CGFloat] = [0.00, 0.07, 0.03, 0.09, 0.02, 0.08, 0.05]

    // MARK: - The drift that never stops

    /// **A cloud that parks is a picture; a cloud that keeps breathing is
    /// weather.** Once its slide lands, each cloud drifts on for the rest of the
    /// clip — a slow sideways sway with a little rise and fall under it,
    /// additive on top of its resting position so it never fights the slide that
    /// put it there.
    ///
    /// Every cloud gets its OWN period, and the periods are deliberately not
    /// multiples of each other: seven clouds breathing in step is a single
    /// object wobbling, which is more obviously artificial than not moving at
    /// all. The amplitudes are small on purpose — this is meant to be noticed
    /// only if you look.
    struct Drift {
        let dx: CGFloat
        let dy: CGFloat
        /// One leg of the sway; it autoreverses, so a full cycle is twice this.
        let seconds: Double
    }

    /// Sideways sway as a fraction of the screen width, per cloud.
    static let driftX: [CGFloat] = [0.020, -0.014, 0.016, -0.022, 0.013, -0.018, 0.024]
    /// Rise and fall as a fraction of the screen height, per cloud.
    static let driftY: [CGFloat] = [-0.006, 0.009, 0.005, -0.008, 0.007, -0.005, 0.004]
    /// Seconds per leg. Co-prime-ish so the band never resynchronises.
    static let driftSeconds: [Double] = [7.0, 9.5, 8.3, 11.0, 6.7, 10.4, 12.1]

    static func drift(for index: Int, in bounds: CGRect) -> Drift {
        let i = index % cloudCount
        return Drift(dx: bounds.width * driftX[i],
                     dy: bounds.height * driftY[i],
                     seconds: driftSeconds[i])
    }

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
            // The left half comes from the left, the right half from the right —
            // shortest travel, and it is what makes the band close from both
            // sides at once. With an odd count the extra one comes from the left.
            let fromLeft = 2 * i < cloudCount
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
        // The photograph, when there is one. Cached under the same key as the
        // drawing it replaces, so the caller never learns which it got — and,
        // unlike the drawing, it is one bitmap whatever size it is asked for:
        // the layer scales it, which is what `contentsGravity` is for.
        if let photo = cloudPhoto(index: index) {
            spriteCache[key] = photo
            return photo
        }
        return drawnCloud(index: index, size: size, scale: scale).map {
            spriteCache[key] = $0
            return $0
        }
    }

    /// The fallback: a cloud built out of nothing but numbers, at exactly the
    /// size asked for. Kept as its own entry point so it can be tested even on a
    /// machine where the sprites are present, and so the reason it still exists
    /// stays visible — a missing PNG must cost a worse cloud, never no storm.
    static func drawnCloud(index: Int, size: CGSize, scale: CGFloat) -> CGImage? {
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
        return blur(sharp, radius: px.width * blurFraction) ?? sharp
    }

    /// The cut-out sprite for this cloud, or nil if the bundle has none — in
    /// which case [cloudImage] draws one instead. A storm with drawn clouds is a
    /// worse storm; a storm that refuses to run because a PNG is missing is no
    /// storm at all.
    static func cloudPhoto(index: Int) -> CGImage? {
        guard let url = Bundle.module.url(forResource: "cloud-\(index % cloudCount)",
                                          withExtension: "png",
                                          subdirectory: "Resources/clouds"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    /// Slack around the sprite, as a fraction of its width, so the blur has
    /// somewhere to go. **Photographic sprites carry their own margin** (they are
    /// trimmed to their cloud and then placed in a fixed box), so this applies to
    /// the drawn fallback; the caller insets by it either way, which costs a
    /// photograph 6 % of transparent edge and nothing else.
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
    /// White and nearly opaque at the head (the BOTTOM of the image — the drop
    /// falls head first), transparent at the tail, so a drop looks like it is
    /// moving even in a still frame. Drawn once per scale and stretched to each
    /// drop's own length by its layer.
    static func dropImage(scale: CGFloat) -> CGImage? {
        let key = "drop@\(Int(scale * 100))"
        if let cached = spriteCache[key] { return cached }
        let w = max(2, Int(3 * scale)), h = max(8, Int(48 * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                        colorComponents: [0.86, 0.91, 1.0, 0.95,
                                                          0.86, 0.91, 1.0, 0.0],
                                        locations: [0, 1], count: 2) else { return nil }
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(h)),
                               options: [])
        guard let image = ctx.makeImage() else { return nil }
        spriteCache[key] = image
        return image
    }

    /// Drops released per second at full downpour, and how often the spawner
    /// wakes up. One timer dropping a handful of layers per tick rather than
    /// 3 600 pre-scheduled work items for the length of the clip.
    static let dropsPerSecond: Double = 330
    static let dropSpawnHz: Double = 30

    /// How far a drop leans while it falls, as a fraction of the distance it
    /// covers — **negative is to the left**, which is the way this storm blows
    /// (Victor, 2026-09-19: *"fall down… and perhaps slightly diagonally to left
    /// a bit"*). 6 % is about 3.4°: enough to read as weather with a wind in it,
    /// far short of the sideways drift this replaced.
    static let dropLean: CGFloat = -0.06

    /// Points per second, far drop → near drop. Real rain is several times
    /// this; at real speed the streaks smear into continuous lines and stop
    /// reading as individual drops.
    static let dropSpeedFar: CGFloat = 900
    static let dropSpeedNear: CGFloat = 2000

    /// One drop's whole flight, in overlay coordinates (**bottom-origin, y up**).
    ///
    /// This is deliberately a pair of POINTS and not an angle. The emitter this
    /// replaced expressed the same thing as `emissionLongitude`, whose zero and
    /// whose sign are a convention rather than a coordinate — and it came out
    /// sideways on screen: a dense band of streaks sliding LEFT under the cloud
    /// base instead of rain reaching the floor. A start and an end cannot be
    /// misread, cannot flip with a layer's geometry, and can be asserted in a
    /// test that never opens a window.
    struct Drop {
        /// Centre of the streak when it is born, and when it is spent.
        let start: CGPoint
        let end: CGPoint
        let size: CGSize
        let seconds: Double
        let opacity: Float
        /// The streak's own tilt, so it lies ALONG its path. A vertical sprite
        /// travelling at an angle reads as a drop sliding sideways, which is
        /// half of what was wrong with the emitter.
        let angle: CGFloat
    }

    /// `depth` 0 = far (small, slow, faint), 1 = near (big, fast, bright) — the
    /// same one-number-carries-everything trick the snow uses, so a drop can
    /// never read as a contradiction. `x` is where it enters, in points.
    static func drop(in bounds: CGRect, lineY: CGFloat, depth: CGFloat, atX x: CGFloat) -> Drop {
        let length = 18 + depth * 46
        let width = 1.1 + depth * 1.7
        let speed = dropSpeedFar + depth * (dropSpeedNear - dropSpeedFar)

        // Born just inside the cloud base and spent just past the bottom edge,
        // so neither end of the streak is ever seen appearing or stopping.
        let startY = lineY + length
        let endY = -length
        let fall = startY - endY
        let drift = fall * dropLean

        return Drop(start: CGPoint(x: x, y: startY),
                    end: CGPoint(x: x + drift, y: endY),
                    size: CGSize(width: width, height: length),
                    seconds: Double(fall / speed),
                    opacity: Float(0.28 + depth * 0.52),
                    angle: atan2(drift, fall))
    }

    /// A random drop for this frame's spawn. The entry span reaches past the
    /// **upwind** edge by as much as the lean will carry a drop across, so the
    /// far side of the screen is not left visibly drier than the near side.
    static func randomDrop(in bounds: CGRect) -> Drop {
        let lineY = rainLineY(in: bounds)
        let reach = abs(dropLean) * (lineY + bounds.height * 0.1)
        let lo = dropLean < 0 ? -bounds.width * 0.02 : -reach
        let hi = dropLean < 0 ? bounds.width + reach : bounds.width * 1.02
        return drop(in: bounds, lineY: lineY,
                    depth: CGFloat.random(in: 0...1),
                    atX: CGFloat.random(in: lo...hi))
    }
}
