import AppKit
import QuartzCore

/// 🛡️ Tile #24, "This is Sparta": a bronze hoplite shield takes the three words
/// as hammer blows, and on the vowel of SPARTA a sun bursts out from behind it, so
/// the shield hangs dark in front of its rays (2026-11-05, Victor: *"să se rotească
/// … niște raze semitransparente în jurul centrului … încearcă să îmi induci o
/// stare de eroism"*). Four designs were prototyped against the clip; this one won.
///
/// **The clip plays whole and the first 3.4 s of it stay empty.** *"Când zice
/// madness nu apare nimic"*: nothing is on the glass until the shield fades in over
/// "THIS". That pre-roll is also what pays for the drawing: the sprites are baked
/// off the main thread after the sound has started, so a press costs the audio
/// nothing, and the desktop is photographed just before it is needed.
///
/// Every number below is a time **in the clip** and every curve is a pure function
/// of it. The whole timeline goes to CoreAnimation as keyframes on one absolute
/// clock, stamped at the moment the sound starts, so the blows cannot pick up
/// main-thread jitter on their way to the words.
enum SpartaShield {

    static let effectName = "sparta"
    static let soundName = "24_this_is_sparta.mp3"
    /// Only used when `soundsDir` has no copy to ask.
    static let fallbackDuration: Double = 9.54

    // MARK: - The clip, as measured

    static let thisBeat: Double = 3.62       // hard onset
    static let isBeat: Double = 4.26         // hard onset
    static let spartaBeat: Double = 4.80     // a soft S: the word starts here, the punch does not
    static let vowelPeak: Double = 5.12      // the swell of SPAR- is over
    static let impact: Double = 6.06         // the loudest onset after the words

    /// The first frame anything draws, and the first with nothing left to draw.
    static let firstVisible: Double = 3.42
    static let lastVisible: Double = 9.4

    /// The photograph has to be in hand before the first blow shakes it.
    static let captureAt: Double = 3.2

    /// The shield fades in rather than flies in, reaching the room around "THIS":
    /// two thirds there on the onset, whole a tenth of a second later.
    static let fadeIn: ClosedRange<Double> = 3.46...3.72
    /// Where the fade starts from, in shield sizes; just enough to land.
    static let arrivalScale: Double = 0.82

    /// The rings are wide soft waves of light. 8.5 and 0.7 are what Victor settled
    /// on by eye. A fainter ring (0.4) stopped reading as a ring at all.
    static let ringThickness: Double = 8.5
    static let ringOpacity: Double = 0.7

    /// The shield's resting radius, as a share of the screen's short side.
    static func radius(in bounds: CGRect) -> CGFloat { min(bounds.width, bounds.height) * 0.21 }

    /// How far the longest ray can reach, at its full length.
    static func rayReach(in bounds: CGRect) -> CGFloat { hypot(bounds.width, bounds.height) * 0.62 }

    // MARK: - Curves

    static func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { min(max(x, a), b) }
    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let u = clamp((x - a) / (b - a), 0, 1)
        return u * u * (3 - 2 * u)
    }
    /// 1 on `t0`, gone after `seconds`.
    static func pulse(_ t0: Double, _ seconds: Double, _ t: Double) -> Double {
        t < t0 ? 0 : max(0, 1 - (t - t0) / seconds)
    }

    /// The sun: nothing before SPAR-, swells on the vowel, flares on the impact,
    /// then dies with the roar. Runs to 1.45 at the flare, hence `sunPeak`.
    static let sunPeak: Double = 1.45
    static func sun(_ t: Double) -> Double {
        var s = smooth(spartaBeat, vowelPeak, t) * 0.85 + 0.15 * smooth(vowelPeak, 5.6, t)
        s += 0.45 * pulse(impact, 0.9, t)
        return s * (t < impact ? 1 : 1 - smooth(7.0, 9.2, t))
    }

    /// The dark bed under the rays: without it, pale gold vanishes on a white slide.
    static let bedPeak: Double = 0.6
    static func bed(_ t: Double) -> Double {
        let b = 0.08 * smooth(firstVisible, thisBeat, t) + 0.25 * smooth(thisBeat, 4.3, t)
            + 0.27 * smooth(spartaBeat, 5.15, t)
        return b * (1 - smooth(7.4, 9.2, t))
    }

    /// The shield's opacity.
    static func shieldAlpha(_ t: Double) -> Double {
        smooth(fadeIn.lowerBound, fadeIn.upperBound, t) * (1 - smooth(7.6, 9.1, t))
    }

    /// The shield's size: lands on "THIS", kicks on each blow, recedes at the end.
    static func shieldScale(_ t: Double) -> Double {
        let land = smooth(fadeIn.lowerBound, thisBeat, t)
        var s = lerp(arrivalScale, 1, land * land)
        if t >= thisBeat {
            let u = (t - thisBeat) / 0.22
            s += 0.09 * sin(min(1, u) * .pi) * max(0, 1 - u)
        }
        s += 0.05 * pulse(isBeat, 0.25, t) + 0.03 * pulse(spartaBeat, 0.25, t) + 0.07 * pulse(impact, 0.35, t)
        return s * lerp(1, 0.55, smooth(7.6, 9.1, t))
    }

    /// Narrowing across the width: the shield tips away from the blow on "IS".
    static func shieldTilt(_ t: Double) -> Double { 1 - 0.04 * pulse(isBeat, 0.3, t) }

    /// The rays' rotation, radians: slow and steady, kicked on by the impact.
    static func spin(_ t: Double) -> Double {
        0.22 * (t - spartaBeat) + (t > impact ? 0.35 * (1 - exp(-(t - impact) * 2.2)) : 0)
    }

    /// The rays' length, 1 at the resting full length.
    static let reachPeak: Double = 1.25
    static func reach(_ t: Double) -> Double {
        lerp(0.35, 1, smooth(spartaBeat, 5.3, t)) * (1 + 0.25 * pulse(impact, 0.8, t))
    }

    /// The photograph of the desktop only moves here. It shows outside of these
    /// windows for no reason, so it does not show: the live desktop stays live.
    static let shakeWindows: [ClosedRange<Double>] = [thisBeat...5.16, impact...6.67]

    private static func shakeOffset(_ t: Double, _ t0: Double, amplitude: Double, _ seconds: Double,
                                    _ frequency: Double) -> CGPoint {
        guard t >= t0, t <= t0 + seconds else { return .zero }
        let d = pow(1 - (t - t0) / seconds, 2)
        return CGPoint(x: sin((t - t0) * frequency) * amplitude * d,
                       y: cos((t - t0) * frequency * 1.3 + 1) * amplitude * 0.6 * d)
    }

    /// Three hammer blows and the impact, in points on a 1728-wide screen.
    static func shake(_ t: Double, width: CGFloat) -> CGPoint {
        let a = shakeOffset(t, thisBeat, amplitude: 16, 0.45, 55)
        let b = shakeOffset(t, isBeat, amplitude: 11, 0.4, 52)
        let c = shakeOffset(t, spartaBeat, amplitude: 7, 0.35, 48)
        let d = shakeOffset(t, impact, amplitude: 22, 0.6, 50)
        let k = width / 1728
        return CGPoint(x: (a.x + b.x + c.x + d.x) * k, y: (a.y + b.y + c.y + d.y) * k)
    }

    /// The desktop's punch on the impact.
    static func zoomPunch(_ t: Double) -> Double {
        let p = pulse(impact, 0.5, t)
        return 1 + 0.035 * p * p
    }

    /// The bright band across the dome, and how it answers the blows.
    static let bandPeak: Double = 0.57
    static func band(_ t: Double) -> Double {
        0.38 * (t < isBeat ? 0.25 : 1) * (1 + 0.5 * pulse(impact, 0.4, t))
    }

    /// The Λ: strikes gold on SPAR-, and stays lit while the sun is up.
    static func lambdaGlow(_ t: Double) -> Double { min(1, 0.9 * pulse(spartaBeat, 0.5, t) + 0.55 * sun(t)) }

    // MARK: - The rays

    struct Ray: Equatable {
        let angle: CGFloat, halfWidth: CGFloat, length: CGFloat
    }

    struct Fan {
        let count: Int, seed: Int
        let widthFactor: CGFloat, alpha: CGFloat
        let color: (r: CGFloat, g: CGFloat, b: CGFloat)
        /// Share of `spin`, so the two fans turn against each other.
        let direction: Double
    }

    /// Broad gold, clockwise; thin white-gold, slower, the other way.
    static let fans = [
        Fan(count: 14, seed: 11, widthFactor: 1, alpha: 0.42, color: (255, 196, 96), direction: 1),
        Fan(count: 22, seed: 77, widthFactor: 0.55, alpha: 0.30, color: (255, 240, 200), direction: -0.6),
    ]

    /// Each fan is drawn as two layers, every other ray, breathing out of step: the
    /// flicker a ray had on its own in the prototype, for two opacities a frame.
    static let fanHalves = 2

    /// The seeded generator of the prototype, double-precision multiply included,
    /// so the app shows the very rays that were approved.
    static func seeded(_ i: Int) -> Double {
        var x = Int32(truncatingIfNeeded: Int64(i) &* 374_761_393 &+ 668_265_263)
        let y = x ^ Int32(bitPattern: UInt32(bitPattern: x) >> 13)
        let m = fmod(Double(y) * 1_274_126_177, 4_294_967_296)
        x = Int32(truncatingIfNeeded: Int64(m))
        return Double(UInt32(bitPattern: x ^ Int32(bitPattern: UInt32(bitPattern: x) >> 16))) / 4_294_967_296
    }

    static func rays(of fan: Fan, reach: CGFloat) -> [Ray] {
        (0..<fan.count).map { i in
            Ray(angle: CGFloat(i) / CGFloat(fan.count) * 2 * .pi + CGFloat(seeded(fan.seed + i)) * 0.25,
                halfWidth: CGFloat(0.035 + seeded(fan.seed + 100 + i) * 0.07) * fan.widthFactor,
                length: reach * CGFloat(0.55 + 0.45 * seeded(fan.seed + 400 + i)))
        }
    }

    /// A half fan's breath: 0.75…1 of its brightness, on its own rhythm.
    static func flicker(half: Int, fan: Int, _ t: Double) -> Double {
        let n = Double(fan * Self.fanHalves + half)
        return 0.875 + 0.125 * sin(t * (3.1 + n * 1.3) + n * 2.1)
    }

    // MARK: - The rings

    struct Ring {
        let t0: Double, seconds: Double
        /// As a multiple of the shield's radius; nil runs to the screen's corners.
        let reach: CGFloat?
        let line: Double
        let color: (r: CGFloat, g: CGFloat, b: CGFloat)
    }

    /// One thrown on each blow, the widest on the impact.
    static let rings = [
        Ring(t0: thisBeat, seconds: 0.55, reach: 2.6, line: 22, color: (255, 210, 140)),
        Ring(t0: isBeat, seconds: 0.5, reach: 2.4, line: 18, color: (255, 220, 160)),
        Ring(t0: spartaBeat, seconds: 0.45, reach: 2.0, line: 12, color: (255, 240, 200)),
        Ring(t0: impact, seconds: 0.8, reach: nil, line: 34, color: (255, 230, 180)),
    ]

    /// Where a ring is `u` of the way through its life: its crest and half its width.
    static func ringShape(_ ring: Ring, u: Double, bounds: CGRect) -> (crest: CGFloat, width: CGFloat) {
        let r = radius(in: bounds)
        let far = ring.reach.map { $0 * r } ?? hypot(bounds.width, bounds.height) * 0.5
        let e = 1 - pow(1 - u, 2.2)
        return (r + (far - r) * CGFloat(e), CGFloat(ring.line * ringThickness * (1 + u * 2)))
    }

    static func ringAlpha(_ ring: Ring, u: Double) -> Double { (1 - u) * (1 - u) * 0.7 * ringOpacity }

    // MARK: - Sprites

    struct Sprites {
        let bed: CGImage
        /// `fanHalves` per fan, gold first.
        let fans: [CGImage]
        let corona: CGImage
        let rings: [CGImage]
        let shadow: CGImage
        let shield: CGImage
        let band: CGImage
        let lambda: CGImage
        let rimBurn: CGImage
        let flash: CGImage
        let dent: CGImage
    }

    /// Everything the effect draws, baked once per press, off the main thread and in
    /// the clip's silent half. Nothing is cached: ~100 MB of rays have no business
    /// staying resident between presses of one tile.
    static func bake(bounds: CGRect, scale: CGFloat) -> Sprites? {
        let r = radius(in: bounds)
        let side = shieldSide(r)
        let px = Int(ceil(side * scale))
        var fanImages: [CGImage] = []
        for fan in fans {
            for half in 0..<fanHalves {
                guard let image = fanSprite(fan, half: half, bounds: bounds) else { return nil }
                fanImages.append(image)
            }
        }
        var ringImages: [CGImage] = []
        for ring in rings {
            guard let image = ringSprite(ring, bounds: bounds) else { return nil }
            ringImages.append(image)
        }
        guard let bed = bedSprite(bounds: bounds), let corona = coronaSprite(),
              let shadow = shadowSprite(), let shield = shieldSprite(px: px),
              let band = bandSprite(px: px), let lambda = lambdaSprite(px: px),
              let rimBurn = rimBurnSprite(px: px), let flash = flashSprite(),
              let dent = dentSprite() else { return nil }
        return Sprites(bed: bed, fans: fanImages, corona: corona, rings: ringImages, shadow: shadow,
                       shield: shield, band: band, lambda: lambda, rimBurn: rimBurn, flash: flash, dent: dent)
    }

    /// The shield's own art runs 2.3 radii across, rim and burn included.
    static func shieldSide(_ radius: CGFloat) -> CGFloat { radius * 2.3 }

    /// A square context with the origin in the middle, y down, in units of `unit`
    /// per half side: so the drawing below reads as "R × 0.56" whatever its size.
    private static func canvas(px: Int, unit: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        guard px > 0, let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let half = CGFloat(px) / 2
        ctx.translateBy(x: half, y: half)
        ctx.scaleBy(x: half / unit, y: -half / unit)
        draw(ctx)
        return ctx.makeImage()
    }

    private typealias Stop = (at: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)

    private static func hex(_ rgb: UInt32, _ at: CGFloat, alpha: CGFloat = 1) -> Stop {
        (at, CGFloat(rgb >> 16 & 255), CGFloat(rgb >> 8 & 255), CGFloat(rgb & 255), alpha)
    }

    private static func gradient(_ stops: [Stop]) -> CGGradient? {
        let components = stops.flatMap { [$0.r / 255, $0.g / 255, $0.b / 255, $0.a] }
        return CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: components,
                          locations: stops.map(\.at), count: stops.count)
    }

    private static func radial(_ ctx: CGContext, _ stops: [Stop], from c0: CGPoint = .zero, _ r0: CGFloat,
                               to c1: CGPoint? = nil, _ r1: CGFloat, options: CGGradientDrawingOptions = []) {
        guard let g = gradient(stops) else { return }
        ctx.drawRadialGradient(g, startCenter: c0, startRadius: r0, endCenter: c1 ?? c0, endRadius: r1,
                               options: options)
    }

    private static func linear(_ ctx: CGContext, _ stops: [Stop], from a: CGPoint, to b: CGPoint) {
        guard let g = gradient(stops) else { return }
        ctx.drawLinearGradient(g, start: a, end: b, options: [])
    }

    private static func disc(_ r: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
    }

    private static func annulus(_ outer: CGFloat, _ inner: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addPath(disc(outer))
        p.addPath(disc(inner))
        return p
    }

    private static func lambdaPath(_ R: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -R * 0.5, y: R * 0.56))
        p.addLine(to: CGPoint(x: 0, y: -R * 0.56))
        p.addLine(to: CGPoint(x: R * 0.5, y: R * 0.56))
        return p
    }

    /// Soft all over, so a thumbnail of the screen scaled up is as good as a Retina
    /// bitmap of it. Only the shape of the screen matters.
    private static func bedSprite(bounds: CGRect) -> CGImage? {
        let w = 320, h = max(1, Int(CGFloat(w) * bounds.height / max(bounds.width, 1)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let k = CGFloat(w) / max(bounds.width, 1)
        let mid = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        let p = CGFloat(bedPeak)
        radial(ctx, [(0, 8, 5, 2, p * 0.9), (0.5, 8, 5, 2, p * 0.75), (1, 8, 5, 2, min(1, p * 1.15))],
               from: mid, radius(in: bounds) * 0.5 * k, to: mid, hypot(bounds.width, bounds.height) * 0.55 * k,
               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return ctx.makeImage()
    }

    /// The side of the square a fan is drawn on, in points.
    static func fanSide(bounds: CGRect) -> CGFloat { rayReach(in: bounds) * CGFloat(reachPeak) * 2 }

    private static func fanSprite(_ fan: Fan, half: Int, bounds: CGRect) -> CGImage? {
        let reach = rayReach(in: bounds) * CGFloat(reachPeak)
        let r0 = radius(in: bounds) * 0.85
        let peak = fan.alpha * CGFloat(sunPeak)
        let c = fan.color
        return canvas(px: 2048, unit: reach) { ctx in
            ctx.setBlendMode(.plusLighter)     // the rays add up where they cross
            for (i, ray) in rays(of: fan, reach: reach).enumerated() where i % fanHalves == half {
                func point(_ a: CGFloat, _ d: CGFloat) -> CGPoint { CGPoint(x: cos(a) * d, y: sin(a) * d) }
                let wedge = CGMutablePath()
                wedge.move(to: point(ray.angle - ray.halfWidth * 0.35, r0))
                wedge.addLine(to: point(ray.angle - ray.halfWidth, ray.length))
                wedge.addLine(to: point(ray.angle + ray.halfWidth, ray.length))
                wedge.addLine(to: point(ray.angle + ray.halfWidth * 0.35, r0))
                wedge.closeSubpath()
                ctx.saveGState()
                ctx.addPath(wedge)
                ctx.clip()
                linear(ctx, [(0, c.r, c.g, c.b, peak), (0.35, c.r, c.g, c.b, peak * 0.55), (1, c.r, c.g, c.b, 0)],
                       from: point(ray.angle, r0), to: point(ray.angle, ray.length))
                ctx.restoreGState()
            }
        }
    }

    /// The side of the corona's square, in radii, and the gradient inside it.
    static let coronaSide: CGFloat = 5.2
    static let coronaReach: CGFloat = 1.9

    /// The hot light hugging the rim: the thing that makes the shield an eclipse.
    private static func coronaSprite() -> CGImage? {
        let s = CGFloat(sunPeak)
        return canvas(px: 1024, unit: coronaSide / 2) { ctx in
            ctx.setBlendMode(.plusLighter)
            radial(ctx, [(0, 255, 250, 230, min(1, 0.95 * s)), (0.12, 255, 210, 120, 0.6 * s),
                         (0.45, 255, 160, 60, 0.18 * s), (1, 255, 140, 40, 0)],
                   0.9, coronaReach, options: [.drawsBeforeStartLocation])
        }
    }

    /// The moment a ring's shape is taken from. It keeps almost the same proportion
    /// all its life, so one bitmap, scaled, is the whole ring.
    private static let ringShapeAt: Double = 0.3

    /// The ring's crest as a share of the sprite's half side, and its inner edge.
    static func ringProportions(_ ring: Ring, bounds: CGRect) -> (inner: CGFloat, outerToCrest: CGFloat) {
        let s = ringShape(ring, u: ringShapeAt, bounds: bounds)
        let outer = s.crest + s.width * 0.5
        return (max(0, s.crest - s.width) / outer, outer / s.crest)
    }

    private static func ringSprite(_ ring: Ring, bounds: CGRect) -> CGImage? {
        let inner = ringProportions(ring, bounds: bounds).inner
        let c = ring.color
        return canvas(px: 1024, unit: 1) { ctx in
            radial(ctx, [(0, c.r, c.g, c.b, 0), (0.6, c.r, c.g, c.b, 0.5), (0.78, 255, 250, 235, 1), (1, c.r, c.g, c.b, 0)],
                   inner, 1)
        }
    }

    /// The pool of dark the shield hangs over, on a 3-radius square.
    private static func shadowSprite() -> CGImage? {
        canvas(px: 512, unit: 1.5) { ctx in
            radial(ctx, [(0, 0, 0, 0, 0.35), (1, 0, 0, 0, 0)], 0.4, 1.5, options: [.drawsBeforeStartLocation])
        }
    }

    private static func shieldSprite(px: Int) -> CGImage? {
        canvas(px: px, unit: 1.15) { ctx in
            let R: CGFloat = 1
            // The domed face, light from upper-left.
            ctx.saveGState()
            ctx.addPath(disc(R * 0.88))
            ctx.clip()
            radial(ctx, [hex(0xe3b56a, 0), hex(0xb8822f, 0.25), hex(0x7d5118, 0.6), hex(0x4a2c0c, 0.9), hex(0x2a1705, 1)],
                   from: CGPoint(x: -R * 0.32, y: -R * 0.36), R * 0.05, to: .zero, R,
                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()

            // Hammered: seeded dents, each a tiny bevel. Fainter than the prototype's:
            // at Retina size, those read as bubbles.
            for i in 0..<360 {
                let a = CGFloat(seeded(900 + i)) * 6.283, d = sqrt(CGFloat(seeded(1000 + i))) * R * 0.84
                let p = CGPoint(x: cos(a) * d, y: sin(a) * d)
                let rr = R * (0.018 + CGFloat(seeded(1100 + i)) * 0.03)
                radial(ctx, [(0, 255, 225, 170, 0.07), (0.55, 0, 0, 0, 0), (1, 20, 8, 0, 0.09)],
                       from: CGPoint(x: p.x - rr * 0.45, y: p.y - rr * 0.45), 0, to: p, rr)
            }

            // The Λ: raised bronze, dark edge low-right, light edge up-left.
            ctx.setLineJoin(.miter)
            ctx.setLineCap(.butt)
            ctx.saveGState()
            ctx.translateBy(x: R * 0.012, y: R * 0.016)
            ctx.addPath(lambdaPath(R))
            ctx.setLineWidth(R * 0.19)
            ctx.setStrokeColor(red: 30 / 255, green: 14 / 255, blue: 2 / 255, alpha: 0.75)
            ctx.strokePath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(lambdaPath(R))
            ctx.setLineWidth(R * 0.17)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            linear(ctx, [hex(0x5a3410, 0), hex(0x3b2008, 0.45), hex(0x1e1003, 1)],
                   from: CGPoint(x: -R, y: -R), to: CGPoint(x: R, y: R))
            ctx.restoreGState()

            ctx.saveGState()
            ctx.translateBy(x: -R * 0.01, y: -R * 0.012)
            ctx.addPath(lambdaPath(R))
            ctx.setLineWidth(R * 0.03)
            ctx.setStrokeColor(red: 240 / 255, green: 200 / 255, blue: 140 / 255, alpha: 0.55)
            ctx.strokePath()
            ctx.restoreGState()

            // The rim, a torus: dark groove, bright crest, dark outer edge.
            ctx.saveGState()
            ctx.addPath(annulus(R, R * 0.86))
            ctx.clip(using: .evenOdd)
            radial(ctx, [hex(0x2a1706, 0), hex(0x6a4316, 0.18), hex(0xd9a858, 0.45), hex(0x9a6a28, 0.62),
                         hex(0x3a2208, 0.9), hex(0x140a02, 1)], R * 0.86, R)
            linear(ctx, [(0, 255, 230, 180, 0.35), (0.5, 0, 0, 0, 0), (1, 0, 0, 0, 0.45)],
                   from: CGPoint(x: -R, y: -R), to: CGPoint(x: R, y: R))
            ctx.restoreGState()

            // Thirty rivets on the crest.
            for i in 0..<30 {
                let a = CGFloat(i) / 30 * 6.283 + 0.1, rr = R * 0.022
                let p = CGPoint(x: cos(a) * R * 0.93, y: sin(a) * R * 0.93)
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))
                ctx.clip()
                radial(ctx, [hex(0xffe6b0, 0), hex(0xa8742c, 0.5), hex(0x2a1605, 1)],
                       from: CGPoint(x: p.x - rr * 0.4, y: p.y - rr * 0.4), 0, to: p, rr,
                       options: [.drawsAfterEndLocation])
                ctx.restoreGState()
            }

            // The face's own edge, a dark seam against the rim.
            ctx.addPath(disc(R * 0.875))
            ctx.setLineWidth(R * 0.012)
            ctx.setStrokeColor(gray: 0, alpha: 0.6)
            ctx.strokePath()
        }
    }

    /// The streak of light lying across the dome, at the shield's size.
    private static func bandSprite(px: Int) -> CGImage? {
        canvas(px: px, unit: 1.15) { ctx in
            let ang: CGFloat = -0.65, R: CGFloat = 1
            let a = CGFloat(bandPeak)
            ctx.addPath(disc(R * 0.985))
            ctx.clip()
            linear(ctx, [(0, 255, 230, 180, 0), (0.44, 255, 235, 190, a * 0.3), (0.5, 255, 250, 235, a),
                         (0.56, 255, 235, 190, a * 0.3), (1, 255, 230, 180, 0)],
                   from: CGPoint(x: -sin(ang) * R * 0.9, y: cos(ang) * R * 0.9),
                   to: CGPoint(x: sin(ang) * R * 0.9, y: -cos(ang) * R * 0.9))
        }
    }

    private static func lambdaSprite(px: Int) -> CGImage? {
        canvas(px: px, unit: 1.15) { ctx in
            ctx.setLineJoin(.miter)
            ctx.setLineCap(.butt)
            ctx.addPath(lambdaPath(1))
            ctx.setLineWidth(0.16)
            ctx.setStrokeColor(red: 1, green: 215 / 255, blue: 130 / 255, alpha: 0.75)
            ctx.strokePath()
            ctx.addPath(lambdaPath(1))
            ctx.setLineWidth(0.07)
            ctx.setStrokeColor(red: 1, green: 250 / 255, blue: 230 / 255, alpha: 0.8)
            ctx.strokePath()
        }
    }

    /// The eclipse's edge, burning.
    private static func rimBurnSprite(px: Int) -> CGImage? {
        canvas(px: px, unit: 1.15) { ctx in
            ctx.addPath(annulus(1.02, 0.88))
            ctx.clip(using: .evenOdd)
            radial(ctx, [(0, 255, 220, 150, 0), (0.75, 255, 220, 150, 0.35), (1, 255, 250, 235, 0.9)], 0.9, 1.02)
        }
    }

    /// The whole face going white on the impact.
    private static func flashSprite() -> CGImage? {
        canvas(px: 64, unit: 1.15) { ctx in
            ctx.addPath(disc(1))
            ctx.setFillColor(red: 1, green: 1, blue: 250 / 255, alpha: 0.32)
            ctx.fillPath()
        }
    }

    /// Where a blow struck, a splash of light, on a 2-unit square.
    private static func dentSprite() -> CGImage? {
        canvas(px: 256, unit: 2) { ctx in
            radial(ctx, [(0, 255, 255, 245, 1), (0.3, 255, 225, 160, 0.6), (1, 255, 200, 120, 0)], 0, 1)
        }
    }

    // MARK: - The timeline

    /// Keyframes per second: one a frame, CoreAnimation interpolating on a faster panel.
    static let fps: Double = 60

    /// `value(t)` sampled over the clip, on the clock of `begin` (clip time zero).
    ///
    /// **Filled forwards only.** Until its turn comes a layer sits on its model
    /// value, opacity 0. A ring or a blow's first keyframe is its brightest, so a
    /// fill backwards held it on the glass from the press on, during "Madness?".
    private static func track(_ keyPath: String, begin: CFTimeInterval,
                              from t0: Double = firstVisible - 0.02, to t1: Double = lastVisible,
                              mode: CAAnimationCalculationMode = .linear,
                              _ value: (Double) -> Any) -> CAKeyframeAnimation {
        let frames = max(1, Int(((t1 - t0) * fps).rounded()))
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = (0...frames).map { value(t0 + (t1 - t0) * Double($0) / Double(frames)) }
        a.keyTimes = (0...frames).map { NSNumber(value: Double($0) / Double(frames)) }
        a.calculationMode = mode
        a.beginTime = begin + t0
        a.duration = t1 - t0
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        return a
    }

    private static func opacity(_ begin: CFTimeInterval, from t0: Double = firstVisible - 0.02,
                                to t1: Double = lastVisible, _ value: (Double) -> Double) -> CAKeyframeAnimation {
        track("opacity", begin: begin, from: t0, to: t1) { NSNumber(value: Float(value($0))) }
    }

    private static func transform(_ begin: CFTimeInterval, from t0: Double = firstVisible - 0.02,
                                  to t1: Double = lastVisible, _ value: (Double) -> CATransform3D) -> CAKeyframeAnimation {
        track("transform", begin: begin, from: t0, to: t1) { NSValue(caTransform3D: value($0)) }
    }

    private static func sprite(_ image: CGImage, frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        layer.contentsGravity = .resize
        layer.opacity = 0
        layer.actions = ["opacity": NSNull(), "transform": NSNull(), "position": NSNull()]
        return layer
    }

    private static func square(_ side: CGFloat, at mid: CGPoint) -> CGRect {
        CGRect(x: mid.x - side / 2, y: mid.y - side / 2, width: side, height: side)
    }

    /// The whole effect, every layer on `begin`'s clock, inside `container`.
    static func build(in container: CALayer, bounds: CGRect, begin: CFTimeInterval, sprites: Sprites) {
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        let R = radius(in: bounds)

        let bedLayer = sprite(sprites.bed, frame: bounds)
        bedLayer.add(opacity(begin) { bed($0) / bedPeak }, forKey: "spartaBed")
        container.addSublayer(bedLayer)

        // The sun. The rays stay behind the shield however short they are, so their
        // length is one scale on the whole fan.
        let side = fanSide(bounds: bounds)
        for (f, fan) in fans.enumerated() {
            for half in 0..<fanHalves {
                let layer = sprite(sprites.fans[f * fanHalves + half], frame: square(side, at: mid))
                layer.add(opacity(begin) { sun($0) / sunPeak * flicker(half: half, fan: f, $0) }, forKey: "spartaSun")
                layer.add(transform(begin) { t in
                    let s = CGFloat(reach(t) / reachPeak)
                    return CATransform3DRotate(CATransform3DMakeScale(s, s, 1), CGFloat(fan.direction * spin(t)), 0, 0, 1)
                }, forKey: "spartaTurn")
                container.addSublayer(layer)
            }
        }

        let corona = sprite(sprites.corona, frame: square(coronaSide * R, at: mid))
        corona.add(opacity(begin) { sun($0) / sunPeak }, forKey: "spartaSun")
        corona.add(transform(begin) { t in
            let s = CGFloat(shieldScale(t) * (1 + 0.6 / Double(coronaReach) * pulse(impact, 0.8, t)))
            return CATransform3DMakeScale(s, s, 1)
        }, forKey: "spartaBreath")
        container.addSublayer(corona)

        // The rings: under the shield, over the sun.
        for (i, ring) in rings.enumerated() {
            let last = ringShape(ring, u: 1, bounds: bounds)
            let outerSide = (last.crest + last.width * 0.5) * 2
            let shape = ringProportions(ring, bounds: bounds)
            let layer = sprite(sprites.rings[i], frame: square(outerSide, at: mid))
            let t1 = ring.t0 + ring.seconds
            layer.add(opacity(begin, from: ring.t0, to: t1) { ringAlpha(ring, u: ($0 - ring.t0) / ring.seconds) },
                      forKey: "spartaRingFade")
            layer.add(transform(begin, from: ring.t0, to: t1) { t in
                let now = ringShape(ring, u: (t - ring.t0) / ring.seconds, bounds: bounds)
                let s = now.crest * shape.outerToCrest * 2 / outerSide
                return CATransform3DMakeScale(s, s, 1)
            }, forKey: "spartaRingOut")
            container.addSublayer(layer)
        }

        // The shield. Its layers fade one by one rather than as a group: a group
        // would be an offscreen pass for what the eye reads as the same thing.
        let shieldFrame = square(shieldSide(R), at: mid)
        let holder = CALayer()
        holder.frame = shieldFrame
        holder.allowsGroupOpacity = false
        holder.opacity = 0
        holder.actions = ["opacity": NSNull(), "transform": NSNull()]
        holder.add(opacity(begin) { shieldAlpha($0) }, forKey: "spartaFade")
        let width = bounds.width
        holder.add(transform(begin) { t in
            let s = CGFloat(shieldScale(t)), push = shake(t, width: width)
            let moved = CATransform3DMakeTranslation(push.x * 0.3, push.y * 0.3, 0)
            return CATransform3DConcat(CATransform3DMakeScale(s * CGFloat(shieldTilt(t)), s, 1), moved)
        }, forKey: "spartaBlows")

        let inside = CGRect(origin: .zero, size: shieldFrame.size)
        let centre = CGPoint(x: inside.midX, y: inside.midY)

        let shadow = sprite(sprites.shadow, frame: square(R * 3, at: CGPoint(x: centre.x, y: centre.y - R * 0.15)))
        shadow.opacity = 1
        holder.addSublayer(shadow)
        let face = sprite(sprites.shield, frame: inside)
        face.opacity = 1
        holder.addSublayer(face)

        let bandLayer = sprite(sprites.band, frame: inside)
        bandLayer.add(opacity(begin) { band($0) / bandPeak }, forKey: "spartaBand")
        holder.addSublayer(bandLayer)

        // Where the blows land: the rim on "THIS", the face on "IS". In the art's
        // terms, so y down from the middle of the shield.
        let blows: [(t0: Double, x: CGFloat, y: CGFloat, size: CGFloat, alpha: Double)] = [
            (thisBeat, -0.62, -0.68, 0.45, 1.0), (isBeat, 0.45, -0.25, 0.5, 0.95),
        ]
        for blow in blows {
            let spot = CGPoint(x: centre.x + blow.x * R, y: centre.y - blow.y * R)
            let dent = sprite(sprites.dent, frame: square(blow.size * R * 4, at: spot))
            let t1 = blow.t0 + 0.4
            dent.add(opacity(begin, from: blow.t0, to: t1) { blow.alpha * pulse(blow.t0, 0.4, $0) }, forKey: "spartaDent")
            dent.add(transform(begin, from: blow.t0, to: t1) { t in
                let s = CGFloat(1 + 0.8 * (1 - pulse(blow.t0, 0.4, t)))
                return CATransform3DMakeScale(s, s, 1)
            }, forKey: "spartaDentGrow")
            holder.addSublayer(dent)
        }

        let lambda = sprite(sprites.lambda, frame: inside)
        lambda.add(opacity(begin) { lambdaGlow($0) }, forKey: "spartaLambda")
        holder.addSublayer(lambda)

        let rim = sprite(sprites.rimBurn, frame: inside)
        rim.add(opacity(begin) { min(1, sun($0)) }, forKey: "spartaRim")
        holder.addSublayer(rim)

        let flash = sprite(sprites.flash, frame: inside)
        flash.add(opacity(begin, from: impact, to: impact + 0.3) { pulse(impact, 0.3, $0) }, forKey: "spartaFlash")
        holder.addSublayer(flash)

        container.addSublayer(holder)
    }

    /// The desktop, photographed, shaking under everything. At rest it is identical
    /// to what it covers, so it comes and goes without a seam (`BombShake`). Goes
    /// under the bed, and nothing is lost if it never comes: the shield still shakes.
    static func addDesktop(_ image: CGImage, to container: CALayer, bounds: CGRect, begin: CFTimeInterval) {
        let picture = sprite(image, frame: bounds)
        picture.contentsGravity = .resizeAspectFill
        picture.masksToBounds = true
        let last = shakeWindows.last?.upperBound ?? impact
        picture.add(track("opacity", begin: begin, from: thisBeat, to: last, mode: .discrete) { t in
            NSNumber(value: shakeWindows.contains { $0.contains(t) } ? 1 : 0)
        }, forKey: "spartaShows")
        let width = bounds.width
        picture.add(transform(begin, from: thisBeat, to: last) { t in
            let z = CGFloat(zoomPunch(t)), push = shake(t, width: width)
            return CATransform3DConcat(CATransform3DMakeScale(z, z, 1),
                                       CATransform3DMakeTranslation(push.x * z, push.y * z, 0))
        }, forKey: "spartaShake")
        container.insertSublayer(picture, at: 0)
    }
}
