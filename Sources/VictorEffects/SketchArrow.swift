import AppKit
import QuartzCore

/// 🔁 The "one more time" replay arrow (tile #71), sketched onto the desktop in
/// cyan as if somebody were drawing it live with a marker.
///
/// This is a **pure builder**, the same shape as `CrtShutdown`:
/// `makeLayer(in:scale:)` returns ONE container layer with the whole
/// choreography already attached, so the caller adds it to the host layer and
/// hands it to `trackEffect(duration: totalDuration)`. The self-termination rule
/// is then satisfied by the ordinary machinery and `stop-all` tears it down like
/// any other tracked effect. No timers, no callbacks, no state: everything it
/// knows about the screen is the bounds it was handed, which is what makes the
/// geometry testable headlessly.
///
/// **Why procedural and not a picture.** An arrow is three strokes and two
/// angles; a PNG of one would be an asset to ship, to scale for every display,
/// and to re-cut the day the shape changes — and it could not be *drawn*. Here
/// the drawing IS the effect: every stroke is a `CAShapeLayer` whose `strokeEnd`
/// runs 0 → 1, which is exactly a pen travelling along it.
///
/// **The sketch look** is three passes over the same ideal geometry, each with
/// its own smooth wobble (`Wobble`), its own width and alpha, and its own
/// slightly different speed — the way a felt-tip goes over a line twice and
/// never lands on it twice. After the drawing settles the passes **boil**: each
/// stroke cycles between three wobble variants at 8 fps, the trick every
/// hand-drawn animation uses to keep an inked line alive. Without it a 13 s hold
/// is thirteen seconds of a frozen decal.
enum SketchArrow {

    // MARK: - Geometry

    /// Everything below is in units of the ring's **centre-line radius** (R = 1),
    /// origin at the ring's centre, **y up** (CALayer's own orientation on this
    /// overlay). The numbers were measured off the tile artwork
    /// (`tiles/sfx_71_one_more_time.jpg`, 872 px square) by thresholding it and
    /// fitting the annulus: centre (471.5, 445), centre-line radius 327.5 px,
    /// stroke 81 px. Keeping them normalised is what lets the same silhouette be
    /// drawn at any screen size.

    /// Where the pen starts: the free tail end, upper **right** (≈ 1:30).
    static let tailAngle: CGFloat = 47 * .pi / 180
    /// Where the ring stops, upper **left** (≈ 11:00), just under the arrowhead.
    /// Tail → head the long way round (through the bottom) is a **clockwise**
    /// 294° sweep, which is the direction the head then points in.
    static let headAngle: CGFloat = 113 * .pi / 180

    /// The arrowhead is an open chevron, not a filled triangle — two long barbs
    /// meeting at a point that sits just outside the ring (r ≈ 1.1) at the head
    /// end. Included angle ≈ 91°, so the point looks up and to the right at ≈ 48°,
    /// i.e. along the ring's clockwise tangent.
    static let apex = CGPoint(x: -0.423, y: 1.011)
    /// The long barb, flung out to the left past the ring (r ≈ 1.63).
    static let barbOuter = CGPoint(x: -1.250, y: 1.047)
    /// The short barb, dropping back inside the ring (r ≈ 0.43).
    static let barbInner = CGPoint(x: -0.371, y: 0.214)

    /// Stroke width as a fraction of R — a quarter of the radius, which is what
    /// makes the artwork read as a marker glyph rather than a diagram.
    static let strokeRatio: CGFloat = 0.247

    /// The whole glyph's box in normalised units, **stroke included**: the ring
    /// plus the outer barb (which is what makes it wider than tall) plus the
    /// point. Used for both the scale and the centring, so "three quarters of
    /// the screen" means the drawing, not the circle it is built on.
    static let glyphBounds = CGRect(x: -1.374, y: -1.124, width: 2.498, height: 2.251)

    /// How much of the screen's height the glyph's box fills.
    static let heightFraction: CGFloat = 0.75

    // MARK: - Timing

    /// The ring: one long unbroken sweep, eased at both ends because a hand does
    /// not start or stop a 294° curve at speed.
    static let ringDraw: Double = 1.35
    /// Each barb is a flick, not a sweep.
    static let barbDraw: Double = 0.32
    /// The head starts just *before* the ring's last pass lands, so the two read
    /// as one gesture instead of two drawings taking turns.
    static let headLead: Double = 0.12
    /// The second barb follows the first, the way a hand lifts and comes back.
    static let barbGap: Double = 0.18
    /// Pen-down to pen-up — of the **last** pass to finish, not the first. Each
    /// pass carries its own delay and speed, so the slow one trailing the others
    /// is what decides when the drawing is over (and therefore when the boil may
    /// start): taking pass 0's timing would set the line squirming while a pen
    /// was still on it.
    static let drawDuration: Double = passes.map {
        $0.delay + $0.speed * (ringDraw + barbDraw) - headLead + barbGap
    }.max() ?? (ringDraw + barbDraw)

    /// `71_one_more_time.mp3` is 13.56 s (`afinfo`). The arrow lives exactly as
    /// long as the clip, fade included — re-cut the clip and this moves.
    static let soundDuration: Double = 13.56
    /// The closing dissolve, inside `soundDuration`, not after it.
    static let fadeOut: Double = 0.8
    /// What the caller tracks the layer for. **The effect ends on its own here**
    /// whatever any client does or fails to say.
    static let totalDuration: Double = soundDuration

    /// Frames of the boil, and how long each is held (8 fps).
    static let boilVariants = 3
    static let boilFrame: Double = 1.0 / 8.0

    // MARK: - Colour

    /// The line itself: a saturated cyan that survives being drawn over a light
    /// desktop as well as a dark one.
    static let inkColor = NSColor(srgbRed: 0.24, green: 0.82, blue: 1.00, alpha: 1)
    /// The lighter second pass — a marker's wet edge.
    static let paleColor = NSColor(srgbRed: 0.66, green: 0.95, blue: 1.00, alpha: 1)

    // MARK: - Passes

    /// One go over the whole glyph. Three of them overlapping, each missing the
    /// ideal line by a little more than the last, is the entire sketch effect.
    struct Pass {
        let widthRatio: CGFloat   // of the full stroke
        let alpha: Float
        let color: NSColor
        let wobble: CGFloat       // how far this pass strays, in units of R
        let seed: UInt64
        let delay: Double         // behind the first pass
        let speed: Double         // multiplies every duration
    }

    static let passes: [Pass] = [
        Pass(widthRatio: 1.00, alpha: 0.92, color: inkColor, wobble: 0.012, seed: 11, delay: 0.00, speed: 1.00),
        Pass(widthRatio: 0.58, alpha: 0.55, color: paleColor, wobble: 0.030, seed: 29, delay: 0.07, speed: 0.90),
        Pass(widthRatio: 0.36, alpha: 0.40, color: inkColor, wobble: 0.052, seed: 47, delay: 0.14, speed: 1.10),
    ]

    // MARK: - Sampling (pure, normalised units)

    /// The ring, sampled tail → head the long way round, each sample pushed in or
    /// out along its own radius by the pass's wobble.
    static func ringPoints(seed: UInt64, wobble: CGFloat, samples: Int = 220) -> [CGPoint] {
        let noise = Wobble(seed: seed, amp: wobble)
        let sweep = 2 * CGFloat.pi - (headAngle - tailAngle)   // clockwise, ≈ 294°
        return (0...samples).map { i in
            let t = CGFloat(i) / CGFloat(samples)
            let a = tailAngle - sweep * t
            let r = 1 + noise.at(t)
            return CGPoint(x: r * cos(a), y: r * sin(a))
        }
    }

    /// One barb, sampled **from the apex outwards** — which is the order a hand
    /// draws it in, the pen already being at the point when the ring lands
    /// there. The wobble is ramped in from zero so both barbs start on exactly
    /// the same pixel however far they stray afterwards: a chevron whose two
    /// lines miss each other is a different drawing.
    static func barbPoints(to tip: CGPoint, seed: UInt64, wobble: CGFloat, samples: Int = 48) -> [CGPoint] {
        let noise = Wobble(seed: seed, amp: wobble)
        let dx = tip.x - apex.x, dy = tip.y - apex.y
        let len = max(sqrt(dx * dx + dy * dy), 0.0001)
        let nx = -dy / len, ny = dx / len                      // unit normal
        return (0...samples).map { i in
            let t = CGFloat(i) / CGFloat(samples)
            let ramp = min(1, t * 4)
            let off = noise.at(t) * ramp
            return CGPoint(x: apex.x + dx * t + nx * off, y: apex.y + dy * t + ny * off)
        }
    }

    // MARK: - Building

    /// The container, with every stroke and every animation already on it, or
    /// nil for bounds nothing can be drawn in.
    static func makeLayer(in bounds: CGRect, scale: CGFloat) -> CALayer? {
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let r = bounds.height * heightFraction / glyphBounds.height
        // Centre the GLYPH's box on the screen, not the ring's: the outer barb
        // sticks out to the left, and centring the ring would hang the whole
        // drawing to the right of the middle.
        let centre = CGPoint(x: bounds.midX - r * glyphBounds.midX,
                             y: bounds.midY - r * glyphBounds.midY)
        let lineW = r * strokeRatio

        let container = CALayer()
        container.frame = bounds
        container.contentsScale = scale

        let t0 = CACurrentMediaTime()

        for pass in passes {
            // Three wobble variants per stroke: variant 0 is what gets drawn,
            // the other two are only ever the boil's other frames.
            func variants(_ make: (UInt64) -> [CGPoint]) -> [CGPath] {
                (0..<boilVariants).map { v in
                    smoothPath(make(pass.seed &+ UInt64(v) &* 101).map {
                        CGPoint(x: centre.x + r * $0.x, y: centre.y + r * $0.y)
                    })
                }
            }

            let ring = variants { ringPoints(seed: $0, wobble: pass.wobble) }
            let outer = variants { barbPoints(to: barbOuter, seed: $0 &+ 7, wobble: pass.wobble) }
            let inner = variants { barbPoints(to: barbInner, seed: $0 &+ 13, wobble: pass.wobble) }

            let ringStart = t0 + pass.delay
            let headStart = ringStart + ringDraw * pass.speed - headLead

            container.addSublayer(stroked(ring, pass: pass, width: lineW * pass.widthRatio, scale: scale,
                                         begin: ringStart, duration: ringDraw * pass.speed,
                                         boilAt: t0 + drawDuration))
            container.addSublayer(stroked(outer, pass: pass, width: lineW * pass.widthRatio * 0.92, scale: scale,
                                         begin: headStart, duration: barbDraw * pass.speed,
                                         boilAt: t0 + drawDuration))
            container.addSublayer(stroked(inner, pass: pass, width: lineW * pass.widthRatio * 0.92, scale: scale,
                                         begin: headStart + barbGap, duration: barbDraw * pass.speed,
                                         boilAt: t0 + drawDuration))
        }

        // The whole drawing dissolves inside its own lifetime, so the layer the
        // caller removes at `totalDuration` is already invisible when it goes.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = t0 + totalDuration - fadeOut
        fade.duration = fadeOut
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        container.add(fade, forKey: "fade")

        return container
    }

    /// One pass over one stroke: a shape layer whose `strokeEnd` is the pen.
    private static func stroked(_ paths: [CGPath], pass: Pass, width: CGFloat, scale: CGFloat,
                               begin: CFTimeInterval, duration: Double, boilAt: CFTimeInterval) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = paths[0]
        // fillColor defaults to BLACK: an unset one would paint the ring's whole
        // disc over the desktop.
        layer.fillColor = nil
        layer.strokeColor = pass.color.cgColor
        layer.opacity = pass.alpha
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.contentsScale = scale
        // A soft cyan halo, so the line reads over a busy desktop without having
        // to be any thicker than the artwork's.
        layer.shadowColor = pass.color.cgColor
        layer.shadowRadius = width * 0.55
        layer.shadowOpacity = 0.85
        layer.shadowOffset = .zero

        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.beginTime = begin
        draw.duration = duration
        draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // .backwards so the stroke is INVISIBLE until its turn comes — without
        // it the arrowhead would sit there fully drawn while the ring is still
        // being swept.
        draw.fillMode = .backwards
        layer.strokeEnd = 1
        layer.add(draw, forKey: "draw")

        // The boil. Discrete, so the line jumps between variants like a redrawn
        // frame rather than morphing between them; it only starts once the pen
        // has left, because a line that is still being drawn must not squirm.
        let boil = CAKeyframeAnimation(keyPath: "path")
        boil.values = paths
        boil.calculationMode = .discrete
        boil.beginTime = boilAt
        boil.duration = boilFrame * Double(paths.count)
        boil.repeatCount = .greatestFiniteMagnitude
        layer.add(boil, forKey: "boil")

        return layer
    }

    /// A polyline turned into a curve: quadratic segments through the midpoints,
    /// with each sample as its own control point. Dense samples plus this is a
    /// smooth hand-drawn line; straight segments between them would read as a
    /// polygon at the widths this effect uses.
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                              y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// Smooth, seeded, repeatable 1-D noise: three sine waves at unrelated
/// frequencies. Repeatable matters — the boil cycles a *fixed* set of variants,
/// so a stroke that regenerated itself differently every frame would shimmer
/// instead of breathe.
struct Wobble {
    private let amp: CGFloat
    private let freq: [CGFloat]
    private let phase: [CGFloat]

    init(seed: UInt64, amp: CGFloat) {
        var rng = SplitMix64(seed: seed)
        self.amp = amp
        freq = [1.3 + rng.unit() * 1.4, 3.1 + rng.unit() * 2.0, 6.4 + rng.unit() * 3.0]
        phase = [rng.unit() * 2 * .pi, rng.unit() * 2 * .pi, rng.unit() * 2 * .pi]
    }

    /// The offset at `t` ∈ 0…1 along the stroke. Weighted 6:3:1 so the line has
    /// one big lazy swing with smaller ones riding on it, rather than fur.
    func at(_ t: CGFloat) -> CGFloat {
        amp * (0.6 * sin(freq[0] * t * 2 * .pi + phase[0])
             + 0.3 * sin(freq[1] * t * 2 * .pi + phase[1])
             + 0.1 * sin(freq[2] * t * 2 * .pi + phase[2]))
    }
}

/// SplitMix64 — a three-line PRNG with no global state, so the wobble is a pure
/// function of its seed on every machine and in every test run.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678_9ABC_DEF0 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0…1.
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53) }
}
