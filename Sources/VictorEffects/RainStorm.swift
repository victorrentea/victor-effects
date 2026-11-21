import AppKit
import CoreImage
import ImageIO
import QuartzCore

/// ⛈️ The storm that rolls in on tile #20: seven fluffy clouds slide in from the
/// sides and the top onto the top edge, and cartoon raindrops fall out of them
/// for the length of the clip. Cheerful on purpose (Victor, 2026-11-20): no
/// gloom, white clouds, blue teardrops.
///
/// Everything here is either a **pure function of the overlay bounds** (where
/// each cloud starts, where it stops) or a **cached drawing** (the cloud
/// sprites, the rain streak) — the same bargain as `WazzupCorner` and
/// `TvStatic`, so the layout can be tested without a screen and the press costs
/// no rendering after the first one.
///
/// **The clouds are fluffy cartoon puffs, drawn, white with a pastel-blue
/// shade** (Victor, 2026-11-20: *"fun and joyful, not dark and evil"*). From
/// September to November they were photographed cumulus graded down to
/// storm-grey, and in a room they read as menace rather than weather; the
/// story of those, and why finding them was hard, is in git history and in
/// `docs/overlay-effects.md` under ⛈️ Storm.
enum RainStorm {

    // MARK: - The clip

    /// The tile's own audio: steady rain, **no thunder** since 2026-11-20 (Victor:
    /// *"fără tunete, doar ploaie"*). The visual lasts exactly as long as this
    /// plays.
    static let soundName = "20_storm.mp3"

    /// Measured 18.90 s. Only used when `soundsDir` has no copy to ask.
    static let fallbackDuration: Double = 18.9

    /// The clip plays at this fraction of the tablet's volume (Victor,
    /// 2026-10-03: the rain was too loud next to the other tiles). A gain in
    /// code rather than a re-encoded mp3: the asset lives in the tablet's repo.
    static let soundGain: Float = 0.5

    // MARK: - Timeline

    /// How long a cloud takes to cross from off-screen to its resting place.
    /// Slow enough to read as weather arriving rather than as a wipe.
    static let cloudSlideSeconds: Double = 2.3

    /// The clouds do not arrive together — that reads as one image cut in half.
    /// Index → its head start, interleaved so the band closes from both sides
    /// at once rather than sweeping across.
    static let cloudDelays: [Double] = [0.00, 0.34, 0.14, 0.46, 0.22, 0.52, 0.08]

    // No gloom since 2026-11-20 (Victor: *"drop the darkening too, keep it
    // cheerful"*): the desktop stays as bright as it was, so the clouds and
    // drops are drawn to read on a light slide AND a dark editor.
    /// Rain does not start until there is something for it to fall out of: the
    /// first cloud is most of the way across by here, and the drops ramp up to
    /// full over [rainRampSeconds] instead of switching on.
    static let rainLeadIn: Double = 1.5
    static let rainRampSeconds: Double = 2.6

    /// The whole shower fades out together at the end of the clip — clouds
    /// and rain — rather than the clouds sliding back out. A retreat
    /// would cost another 2.3 s after the sound has already stopped.
    static let fadeOutSeconds: Double = 1.4

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
    /// Height ÷ width of a cloud's box. The puffs are laid out in units of the
    /// WIDTH and kept under this height ([lobes]), so changing it reshapes the
    /// band and a test then says whether every puff still fits.
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

    /// Which edge a cloud comes in over.
    ///
    /// **Not just the two sides** (Victor, 2026-09-19: *"norii sa vina si de sus
    /// si din laterale"*). Seven clouds all sliding horizontally read as a
    /// curtain being drawn; some of them dropping straight down out of the top
    /// is what makes it read as a sky closing over. The inner ones are the ones
    /// that fall, which is also the shorter journey for them — from the side
    /// they had to cross most of the screen to reach the middle.
    enum Entry {
        case left, right, top

        var isSide: Bool { self != .top }
    }

    /// One cloud's entrance: where it ends up, where it comes from, and when.
    struct Arrival {
        let rest: CGRect
        let start: CGRect
        let from: Entry
        let delay: Double

        /// The property that actually matters at the call site: a cloud coming
        /// over the top is animated on `position.y`, everything else on
        /// `position.x`.
        var isVertical: Bool { from == .top }
    }

    /// Which edge each cloud enters over, by index. Interleaved so a falling
    /// cloud always has a sliding one beside it: three in a row dropping
    /// together is a different wrong thing from a curtain, but still one thing
    /// happening seven times.
    static let cloudEntries: [Entry] = [.left, .top, .left, .top, .right, .top, .right]

    /// The seven entrances, in overlay coordinates (**bottom-origin, y up**, like
    /// every other layer this app hangs on the panel).
    ///
    /// Each cloud starts *fully* outside the screen on its own edge — trailing
    /// edge exactly on that edge, not a corner still poking in — and travels in
    /// one axis only. A cloud that arrived diagonally would be the only thing on
    /// screen moving in two directions at once.
    static func arrivals(in bounds: CGRect) -> [Arrival] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let w = bounds.width * cloudWidthFraction
        let h = w * cloudAspect
        return (0..<cloudCount).map { i in
            let cx = bounds.width * cloudCentres[i]
            let top = bounds.height + h * cloudOverhang[i] - h * cloudDip[i]
            let rest = CGRect(x: cx - w / 2, y: top - h, width: w, height: h)
            let entry = cloudEntries[i]
            let start: CGRect
            switch entry {
            case .left:  start = rest.offsetBy(dx: -rest.maxX, dy: 0)
            case .right: start = rest.offsetBy(dx: bounds.width - rest.minX, dy: 0)
            // Lifted until its BASE is on the top edge of the screen. Its rest
            // frame already pokes above that edge (`cloudOverhang`), so this is
            // a shorter fall than the cloud's own height.
            case .top:   start = rest.offsetBy(dx: 0, dy: bounds.height - rest.minY)
            }
            return Arrival(rest: rest, start: start, from: entry, delay: cloudDelays[i])
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

    /// The puffs of one cloud, **back to front** — the order they are painted
    /// in, so a lower puff always overlaps the one above it and its pale rim is
    /// what draws the line between them. **Every number is in units of the
    /// cloud's WIDTH**, including the vertical ones, so a puff is a true circle
    /// on screen rather than an ellipse squashed by the box's aspect. `y` is
    /// measured up from the cloud's base, and no puff reaches past
    /// [cloudAspect] (the box's height in those same units), which is what keeps
    /// the sprite inside its own frame.
    ///
    /// Four layers: a dome along the top (mostly above the screen edge at rest,
    /// but seen while a top-entry cloud drops in), a fat middle that closes the
    /// mass, a puff on each flank, and a **front row of round bumps along the
    /// base** — the band is seen from below, so its underside IS the cloud, and
    /// a scalloped underside is what reads as fluffy rather than as overcast
    /// (Victor, 2026-11-20: *"fluffy… fun and joyful, not dark and evil"*).
    ///
    /// Returned rather than drawn so the shape can be inspected in a test.
    static func lobes(seed: Int) -> [(centre: CGPoint, radius: CGFloat)] {
        var rng = Seeded(UInt64(seed) &+ 11)
        var out: [(centre: CGPoint, radius: CGFloat)] = []
        func puff(_ x: Double, _ y: Double, _ r: Double) {
            out.append((CGPoint(x: x, y: y), CGFloat(r)))
        }
        let top = Double(cloudAspect) - 0.012
        // The dome: three big puffs touching the top of the box.
        for x in [0.27, 0.51, 0.75] {
            let r = rng.next(0.16...0.19)
            puff(x + rng.next(-0.025...0.025), top - r, r)
        }
        // The middle: what closes the mass, so no daylight between the dome
        // and the front row.
        for x in [0.36, 0.64] {
            let r = rng.next(0.18...0.20)
            puff(x + rng.next(-0.02...0.02), rng.next(0.29...0.33), r)
        }
        // The flanks, low and round — a cloud whose sides are straight is a
        // pillow.
        let leftR = rng.next(0.11...0.13), rightR = rng.next(0.11...0.13)
        puff(0.13 + rng.next(-0.015...0.015), rng.next(0.22...0.27), leftR)
        puff(0.87 + rng.next(-0.015...0.015), rng.next(0.22...0.27), rightR)
        // The front row: bumps along the base of UNEQUAL size, hanging at
        // different depths, so the underside bounces instead of reading as a
        // row of balls.
        for i in 0..<frontRowCount {
            let t = Double(i) / Double(frontRowCount - 1)
            let r = rng.next(0.085...0.135)
            let x = 0.21 + 0.58 * t + rng.next(-0.025...0.025)
            puff(x, r + rng.next(0.01...0.06), r)
        }
        return out
    }

    /// The last this-many puffs of [lobes] are the front row along the base.
    static let frontRowCount = 4

    /// A lobe's centre and radius in the sprite's own pixels.
    private static func lobeRects(seed: Int, in rect: CGRect) -> [(centre: CGPoint, radius: CGFloat)] {
        let u = rect.width
        return lobes(seed: seed).map { lobe in
            (CGPoint(x: rect.minX + lobe.centre.x * u, y: rect.minY + lobe.centre.y * u), lobe.radius * u)
        }
    }

    /// Rendered sprites, keyed `index@WxH`. A press has to be instant; the first
    /// one pays for the blur and every later one is a dictionary hit.
    private static var spriteCache: [String: CGImage] = [:]

    /// One cloud, `size` points at `scale`, transparent outside the puffs.
    static func cloudImage(index: Int, size: CGSize, scale: CGFloat) -> CGImage? {
        let key = "\(index)@\(Int(size.width * scale))x\(Int(size.height * scale))"
        if let cached = spriteCache[key] { return cached }
        return drawnCloud(index: index, size: size, scale: scale).map {
            spriteCache[key] = $0
            return $0
        }
    }

    /// **A fluffy cartoon cloud, not a photograph** (Victor, 2026-11-20:
    /// *"fluffy… fun and joyful, not dark and evil"*). The photographed cumulus
    /// this replaced (Sept 2026) had been graded down to storm-grey to sit under
    /// the gloom, and in a room it read as menace, not weather.
    ///
    /// Painted in two groups, the mass behind and then the front row of bumps
    /// along the base, each the same way: its silhouette (the union of its
    /// puffs) filled pale sky-blue, then every puff again in WHITE, a little
    /// smaller and nudged up, blurred, over it. What the white leaves uncovered
    /// is a soft blue crescent under each bump — light from above, shade
    /// underneath — and because the front row is painted after the mass, its
    /// crescents are what draw the bumps against the cloud behind them. No line
    /// is drawn anywhere; a cartoon cloud with an outline is a sticker. A
    /// whisper of blur at the end softens the outer edge into vapour; the
    /// canvas carries [spritePadding] of slack on every side so that blur is
    /// never clipped into a straight line.
    static func drawnCloud(index: Int, size: CGSize, scale: CGFloat) -> CGImage? {
        guard size.width > 1, size.height > 1 else { return nil }

        let px = CGSize(width: size.width * scale, height: size.height * scale)
        let pad = px.width * spritePadding
        let canvas = CGSize(width: px.width + pad * 2, height: px.height + pad * 2)
        let space = CGColorSpaceCreateDeviceRGB()
        func context() -> CGContext? {
            CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height),
                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx = context(),
              let rim = CGColor(colorSpace: space, components: puffRim),
              let white = CGColor(colorSpace: space, components: puffWhite) else { return nil }

        let body = CGRect(x: pad, y: pad, width: px.width, height: px.height)
        let all = lobeRects(seed: index, in: body)
        let split = max(0, all.count - frontRowCount)

        // A soft blue-grey shadow under the whole cloud, baked into the sprite:
        // with no gloom behind it a white cloud on a white slide would only be
        // its crescents. Dropped a little and blurred, so it reads as the cloud
        // floating rather than as an outline.
        if let shade = context(),
           let shadowColour = CGColor(colorSpace: space, components: cloudShadow) {
            shade.setFillColor(shadowColour)
            let drop = px.width * shadowDropFraction
            for p in all {
                shade.fillEllipse(in: CGRect(x: p.centre.x - p.radius, y: p.centre.y - p.radius - drop,
                                             width: p.radius * 2, height: p.radius * 2))
            }
            if let sharpShade = shade.makeImage() {
                let soft = blur(sharpShade, radius: px.width * shadowBlurFraction) ?? sharpShade
                ctx.draw(soft, in: CGRect(origin: .zero, size: canvas))
            }
        }
        for group in [Array(all[..<split]), Array(all[split...])] where !group.isEmpty {
            let union = CGMutablePath()
            for p in group {
                union.addEllipse(in: CGRect(x: p.centre.x - p.radius, y: p.centre.y - p.radius,
                                            width: p.radius * 2, height: p.radius * 2))
            }
            // The light: each puff in white, smaller and lifted (bitmap y is
            // up, like the layer's), blurred so the crescent it leaves fades in.
            guard let lit = context() else { return nil }
            lit.setFillColor(white)
            for p in group {
                let r = p.radius * lightScale
                let c = CGPoint(x: p.centre.x - p.radius * 0.05, y: p.centre.y + p.radius * lightLift)
                lit.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
            guard let litSharp = lit.makeImage() else { return nil }
            let litSoft = blur(litSharp, radius: px.width * lightBlurFraction) ?? litSharp

            ctx.saveGState()
            ctx.addPath(union)
            ctx.clip()
            ctx.setFillColor(rim)
            ctx.fill(CGRect(origin: .zero, size: canvas))
            ctx.draw(litSoft, in: CGRect(origin: .zero, size: canvas))
            ctx.restoreGState()
        }

        guard let sharp = ctx.makeImage() else { return nil }
        return blur(sharp, radius: px.width * blurFraction) ?? sharp
    }

    /// How much of a puff the light covers, and how far up it is nudged, as
    /// fractions of the puff's radius: together they set how thick the shaded
    /// crescent under each bump is.
    static let lightScale: CGFloat = 0.93
    static let lightLift: CGFloat = 0.14
    /// The cloud's own shadow: its colour, how far it drops and how soft it is
    /// (fractions of the sprite's width). Faint on purpose — it is there to
    /// lift a white cloud off a white slide, not to make it a thundercloud.
    static let cloudShadow: [CGFloat] = [0.30, 0.42, 0.62, 0.30]
    static let shadowDropFraction: CGFloat = 0.018
    static let shadowBlurFraction: CGFloat = 0.014

    /// The light's own blur, as a fraction of the sprite's width — what makes
    /// the crescent a shade rather than a band.
    static let lightBlurFraction: CGFloat = 0.010

    /// The two colours of a puff: white where the light hits, and the pale,
    /// cheerful sky-blue its shaded rim keeps — a pastel, never grey. Grey is
    /// what made the old clouds look like they were about to hurt someone.
    static let puffWhite: [CGFloat] = [1.00, 1.00, 1.00, 1]
    static let puffRim: [CGFloat] = [0.74, 0.85, 1.00, 1]

    /// Slack around the sprite, as a fraction of its width, so the blur has
    /// somewhere to go.
    static let spritePadding: CGFloat = 0.06
    /// Blur radius, as a fraction of the sprite's width. Just enough to soften
    /// the outer edge — any more and the puffs melt into one pillow, which is
    /// the opposite of fluffy.
    static let blurFraction: CGFloat = 0.0035

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

    /// One **cartoon raindrop** (Victor, 2026-11-20: *"draw some rain drops
    /// cartoon style"*): a teardrop, round at the bottom and pointed at the top
    /// — it falls head first — filled sky-blue, outlined a deeper blue and with
    /// a white glint on the bulb. The outline is what keeps it readable on a
    /// white slide, the light fill on a dark editor; there is no gloom under it
    /// any more to do that job. Drawn once per scale at [dropSpriteSize] and
    /// scaled to each drop's own size by its layer (same aspect, so it never
    /// squashes).
    static func dropImage(scale: CGFloat) -> CGImage? {
        let key = "drop@\(Int(scale * 100))"
        if let cached = spriteCache[key] { return cached }
        let w = dropSpriteSize.width * scale, h = dropSpriteSize.height * scale
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: Int(w), height: Int(h),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let fill = CGGradient(colorSpace: space,
                                    colorComponents: [0.62, 0.84, 1.00, 1,
                                                      0.27, 0.60, 0.98, 1],
                                    locations: [0, 1], count: 2) else { return nil }
        // Bitmap y is up, like the layer's: the bulb sits at the bottom.
        let line = w * 0.08
        let r = (w - line * 2) / 2
        let bulb = CGPoint(x: w / 2, y: line + r)
        let tip = CGPoint(x: w / 2, y: h - line)
        let path = CGMutablePath()
        // From the tip down the right flank, round the bulb, back up the left.
        let a = asin(min(1, r / (tip.y - bulb.y)))          // where the flanks meet the bulb tangentially
        path.move(to: tip)
        path.addArc(center: bulb, radius: r, startAngle: a, endAngle: .pi - a, clockwise: true)
        path.closeSubpath()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(fill, start: CGPoint(x: w * 0.3, y: h), end: CGPoint(x: w * 0.7, y: 0), options: [])
        ctx.restoreGState()

        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.13, 0.40, 0.82, 1])!)
        ctx.setLineWidth(line)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        // The glint: a little white oval up and to the left on the bulb.
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: bulb.x - r * 0.62, y: bulb.y - r * 0.05,
                                   width: r * 0.42, height: r * 0.62))

        guard let image = ctx.makeImage() else { return nil }
        spriteCache[key] = image
        return image
    }

    /// How far above the lowest cloud base a drop's TAIL is born, as a fraction
    /// of a cloud's width. The base is scalloped (front-row bumps end 0.01–0.06
    /// of the width above it) and the clouds hang up to 0.06 of the width higher
    /// than the lowest one (`cloudDip`); 0.16 clears both, into the solid
    /// middle puffs, so every drop slides out from behind a cloud.
    static let dropBirthInset: CGFloat = 0.16

    /// The sprite's own size in points; every drop is this aspect.
    static let dropSpriteSize = CGSize(width: 20, height: 30)

    /// Drops released per second at full rain, and how often the spawner
    /// wakes up. A cartoon shower is SPARSE — each drop is a little character,
    /// and 330 of them a second (the streak rain's count) would be a blue wall.
    static let dropsPerSecond: Double = 60
    static let dropSpawnHz: Double = 20

    /// How far a drop leans while it falls, as a fraction of the distance it
    /// covers — **negative is to the left**, which is the way this storm blows
    /// (Victor, 2026-09-19: *"fall down… and perhaps slightly diagonally to left
    /// a bit"*). 6 % is about 3.4°: enough to read as weather with a wind in it,
    /// far short of the sideways drift this replaced.
    static let dropLean: CGFloat = -0.06

    /// Points per second, far drop → near drop. Cartoon-slow: a drop you can
    /// see the shape of is one that stays in view for a second or so.
    static let dropSpeedFar: CGFloat = 650
    static let dropSpeedNear: CGFloat = 1050

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
        let width = 15 + depth * 15
        let length = width * dropSpriteSize.height / dropSpriteSize.width
        let speed = dropSpeedFar + depth * (dropSpeedNear - dropSpeedFar)

        // Born WHOLLY inside the cloud mass — [dropBirthInset] of a cloud's
        // width above the lowest base, plus half the drop — and spent just past
        // the bottom edge, so neither end is ever seen appearing or stopping.
        // Born on the lowest base itself, a drop under a higher-hanging cloud or
        // between two front-row bumps popped into being in clear sky below it.
        let cloudWidth = bounds.width * cloudWidthFraction
        let startY = lineY + cloudWidth * dropBirthInset + length / 2
        let endY = -length
        let fall = startY - endY
        let drift = fall * dropLean

        return Drop(start: CGPoint(x: x, y: startY),
                    end: CGPoint(x: x + drift, y: endY),
                    size: CGSize(width: width, height: length),
                    seconds: Double(fall / speed),
                    opacity: Float(0.80 + depth * 0.20),
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
