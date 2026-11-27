import AppKit
import QuartzCore

/// 👁️ ⌘⌃7 (2026-11-20, keyed in `victor-mac`): the Eye of the Tower. Victor:
/// *"the eye of the tower of Mordor … no sound, just some light falling on the
/// ground and looking for stuff"*, then, over the first try: *"the tower should
/// be here and the light should spread somewhere here"* (two boxes dragged on
/// the Retina, kept below as fractions of the screen), *"grab an image of the
/// tower from the internet, don't draw it yourself"*, and *"have it follow my
/// mouse when my mouse is below the eye, so I can orient it"*.
///
/// The tower is `Resources/eye-tower.png`, Wikimedia Commons' Barad-dûr line
/// drawing (CC BY 3.0) turned into a dark solid with ember lines by
/// `tools/make-eye-tower.py`. A burning eye opens between its horns; the
/// screen goes dusk-dark; a beam falls from the eye onto the strip along the
/// bottom of the screen and its spot **searches** there — glides to a place,
/// lingers, moves on. While the pointer is **below the eye and moving**, the
/// light leaves the search and **follows the pointer** instead (with a little
/// lag, so it reads as an eye turning, not a cursor); once the pointer has been
/// still for `followGrace` it goes back to searching. The pupil looks where the
/// light is. `lifeSeconds` long; a re-press takes it away.
///
/// Music (Victor, the same day: *"put the LOTR theme song, the one playing when
/// the ring of power was in sight"*, then the exact upload he wanted, *"for as
/// long as the tower shows"*): the YouTube clip "The one ring theme"
/// (Dw6BCAZqkaQ), its first 20 s, faded and loudness-normalised, as
/// `assetsDir/eye-tower.mp3`. Film music, so it stays out of the repo and the
/// eye is silent on a Mac without it.
///
/// The dark is one big layer with a soft hole in the middle that travels with
/// the spot, so "dark everywhere except where the light falls" costs one
/// position per frame, not a mask redrawn every frame. Position, beam, hole and
/// pupil are set together on each tick of a 60 Hz timer (the pointer is only
/// known by polling: the overlay is click-through). Every decision is a pure
/// function below, tested without a screen (`EyeTowerTests`).
enum EyeTower {

    static let effectName = "eye"
    static let musicName = "eye-tower"
    static let musicVolume: Float = 0.9
    /// When the eye goes early (a re-press, stop-all) the music fades this fast;
    /// at its natural end the clip has already faded on its own.
    static let musicFadeOut: Double = 0.8

    // MARK: - Timeline

    static let lifeSeconds: Double = 20
    /// The eye opens over this long before the dark falls.
    static let openSeconds: Double = 1.0
    /// Darkness, beam and spot fade in together over this long.
    static let lightInSeconds: Double = 0.6
    /// The eye closes and the dark lifts over this long at the end.
    static let fadeOutSeconds: Double = 1.1
    static let tickSeconds: Double = 1.0 / 60

    // MARK: - Layout (Victor's boxes, 2026-11-20, on a 3456 × 2234 capture)

    /// The tower stands in this box (unit fractions of the screen, AppKit y-up):
    /// x 282…706, y 232…2172 from the top, in capture pixels.
    static let towerBox = CGRect(x: 282.0 / 3456, y: 1 - 2172.0 / 2234,
                                 width: (706.0 - 282) / 3456, height: (2172.0 - 232) / 2234)
    /// The light searches this strip: x 1272…3152, y 1916…2226 from the top.
    static let lightBox = CGRect(x: 1272.0 / 3456, y: 1 - 2226.0 / 2234,
                                 width: (3152.0 - 1272) / 3456, height: (2226.0 - 1916) / 2234)

    static func scaled(_ unit: CGRect, in b: CGRect) -> CGRect {
        CGRect(x: b.minX + unit.minX * b.width, y: b.minY + unit.minY * b.height,
               width: unit.width * b.width, height: unit.height * b.height)
    }

    /// `eye-tower.png`: 506 × 1145 (the top 56% of the drawing — *"less of the
    /// mountain, more of the tower"*); the horns' bowl spans x 182…284 and the
    /// eye's centre sits at y ≈ 50 from the top (`tools/make-eye-tower.py` output).
    static let towerAspect: CGFloat = 506.0 / 1145
    static let towerEyeAnchor = CGPoint(x: 233.0 / 506, y: 1 - 50.0 / 1145)
    static let towerHornShare: CGFloat = 102.0 / 506

    /// The tower's top is the box's top, centred on it; it rises out of the
    /// screen's bottom edge, cut there (Victor, after a version that faded out
    /// above it: *"no fade jos, să iasă din partea de jos a ecranului"*). It is
    /// wider than the box: the box said where, the drawing says how wide.
    static func towerFrame(in b: CGRect) -> CGRect {
        let box = scaled(towerBox, in: b)
        let h = box.maxY - b.minY
        let w = h * towerAspect
        return CGRect(x: box.midX - w / 2, y: b.minY, width: w, height: h)
    }
    static func eyeCenter(in b: CGRect) -> CGPoint {
        let t = towerFrame(in: b)
        return CGPoint(x: t.minX + t.width * towerEyeAnchor.x, y: t.minY + t.height * towerEyeAnchor.y)
    }
    /// A little wider than the bowl between the horns, so it burns out of it.
    static func eyeSize(in b: CGRect) -> CGSize {
        let w = towerFrame(in: b).width * towerHornShare * 1.5
        return CGSize(width: w, height: w * 0.46)
    }
    /// 21% of the screen wide (14% until 2026-11-27 — Victor: *"make the light
    /// spot … 1.5x bigger"*).
    static func spotSize(in b: CGRect) -> CGSize {
        let w = b.width * 0.21
        return CGSize(width: w, height: w * 0.46)
    }
    /// Where the spot's centre may go while searching: the strip, kept far
    /// enough in that most of the ellipse stays on it.
    static func ground(in b: CGRect) -> CGRect {
        let strip = scaled(lightBox, in: b)
        let s = spotSize(in: b)
        return strip.insetBy(dx: min(s.width * 0.3, strip.width * 0.4), dy: min(s.height * 0.25, strip.height * 0.4))
    }

    /// The darkness layer is the spot's ellipse scaled by `k`, the hole in its
    /// middle; `k` is large enough that, with the spot anywhere on the screen
    /// (it follows the pointer), the dark still covers all of it.
    static func darknessScale(in b: CGRect) -> CGFloat {
        let s = spotSize(in: b)
        guard s.width > 0, s.height > 0 else { return 1 }
        return max(2.05 * b.width / s.width, 2.05 * b.height / s.height)
    }
    static let darknessAlpha: CGFloat = 0.5

    // MARK: - Where the light goes

    /// The pointer has to have moved within this long for the light to follow it.
    static let followGrace: Double = 2.0
    /// The light follows the pointer while it is on this screen, below the eye
    /// and recently moved.
    static func follows(pointer: CGPoint?, eye: CGPoint, eyeSize: CGSize, sinceMoved: Double) -> Bool {
        guard let p = pointer else { return false }
        return p.y < eye.y - eyeSize.height && sinceMoved < followGrace
    }

    static let dwellRange: ClosedRange<Double> = 0.35...0.9
    /// Searching: top speed, points per second; it slows over the last stretch.
    static let searchSpeed: CGFloat = 650
    /// Following: fraction of the gap closed per second (exponential).
    static let followRate: Double = 7

    /// The next place to search: somewhere on the ground, well away from here.
    static func nextWaypoint<R: RandomNumberGenerator>(from p: CGPoint, in b: CGRect, using rng: inout R) -> CGPoint {
        let g = ground(in: b)
        let gap = g.width * 0.25
        var q = p
        for _ in 0..<12 {
            q = CGPoint(x: CGFloat.random(in: g.minX...g.maxX, using: &rng),
                        y: CGFloat.random(in: g.minY...g.maxY, using: &rng))
            if hypot(q.x - p.x, q.y - p.y) >= gap { break }
        }
        return q
    }

    /// One searching step: toward `target` at `searchSpeed`, easing in the last
    /// `0.3 s so it settles instead of stopping dead.
    static func searchStep(from p: CGPoint, to target: CGPoint, dt: Double) -> CGPoint {
        let dx = target.x - p.x, dy = target.y - p.y
        let d = hypot(dx, dy)
        guard d > 0.5 else { return target }
        let v = min(searchSpeed, max(d * 3.2, 60))
        let step = min(d, v * CGFloat(dt))
        return CGPoint(x: p.x + dx / d * step, y: p.y + dy / d * step)
    }

    /// One following step: close a share of the gap, the same at any frame rate.
    static func followStep(from p: CGPoint, to target: CGPoint, dt: Double) -> CGPoint {
        let k = CGFloat(1 - exp(-followRate * dt))
        return CGPoint(x: p.x + (target.x - p.x) * k, y: p.y + (target.y - p.y) * k)
    }

    /// The beam is ONE soft sprite (`beamSprite`, a cone of light with no edge
    /// anywhere — Victor, on the hard-edged quad it replaced: *"not an exact
    /// shape, more of a blurry shade of light"*), hung by its top from the eye
    /// and turned so its foot lands on the spot. Stretching and turning a
    /// sprite costs nothing per frame; blurring a shape that moves 60 times a
    /// second would be a filter pass every frame.
    struct Beam: Equatable {
        let length: CGFloat
        let width: CGFloat
        /// Rotation about the eye; 0 points straight down.
        let angle: CGFloat
    }
    /// How far past the spot's centre the cone reaches, so its fading end
    /// melts into the spot instead of stopping at it.
    static let beamOvershoot: CGFloat = 1.12
    static func beam(eye: CGPoint, spot: CGPoint, spotSize: CGSize) -> Beam {
        let dx = spot.x - eye.x, dy = spot.y - eye.y
        let d = max(hypot(dx, dy), 1)
        return Beam(length: d * beamOvershoot, width: spotSize.width * 1.25, angle: atan2(dx, -dy))
    }

    /// Where the pupil sits in the eye when the light is at `spot`: it looks
    /// toward it, never past the eye's rim.
    static func pupilOffset(eye: CGPoint, eyeSize: CGSize, spot: CGPoint, in b: CGRect) -> CGPoint {
        guard b.width > 0, b.height > 0 else { return .zero }
        let dx = max(-1, min(1, (spot.x - eye.x) / (b.width * 0.6)))
        let dy = max(-1, min(0.3, (spot.y - eye.y) / b.height))
        return CGPoint(x: dx * eyeSize.width * 0.24, y: dy * eyeSize.height * 0.12)
    }

    /// The almond's height `dx` from its middle: its arcs are quadratics, so the
    /// height falls as `1 - 4u²` (u = dx / width) — the full height in the
    /// middle, nothing at the tips.
    static func almondHeight(eyeSize: CGSize, dx: CGFloat) -> CGFloat {
        guard eyeSize.width > 0 else { return 0 }
        let u = dx / eyeSize.width
        return max(0, eyeSize.height * (1 - 4 * u * u))
    }

    /// The slit's height at `offset`: it fills the almond where it stands, so
    /// as it looks aside it shortens with the rim instead of poking out above
    /// and below it (Victor, 2026-11-27: *"the iris … should follow the
    /// circumference of the eye … make it stick inside the eye shape"*). Taken
    /// at the slit's outer edge, the narrower side, then a margin.
    static let pupilFill: CGFloat = 0.92
    static func pupilHeight(eyeSize: CGSize, offset: CGPoint, pupilWidth: CGFloat) -> CGFloat {
        let edge = abs(offset.x) + pupilWidth * 0.25
        return max(0, (almondHeight(eyeSize: eyeSize, dx: edge) - 2 * abs(offset.y)) * pupilFill)
    }

    // MARK: - The fall (a click on the tower, 2026-11-27)

    /// Victor: *"the tower being destroyed as at the end of the movie … broken
    /// down under its own weight, tearing it down to pieces as the eye shuts
    /// down, and the tower bends a bit to the right. And then the whole thing
    /// collapses in a big explosion of dust and fire. That only happens if I
    /// click the tower. If I escape, it just fades out."* The timeline, seconds
    /// from the click:
    static let collapseEffectName = "eye-collapse"
    /// The eye flares, then closes and goes out.
    static let eyeOutSeconds: Double = 0.9
    /// The light (dark, beam, spot) is gone this fast once the eye is hit.
    static let lightOutSeconds: Double = 0.5
    /// The tower shudders from here on, harder and harder, until it breaks.
    static let shudderStart: Double = 0.15
    /// It leans right from here …
    static let bendStart: Double = 0.55
    /// … and comes apart here, into the pieces below, which fall and tumble.
    static let breakAt: Double = 1.75
    /// Fire and dust burst from its foot.
    static let boomAt: Double = 2.0
    static let collapseSeconds: Double = 6.8
    /// The fade of whatever is left (smoke) over the last stretch.
    static let collapseFadeSeconds: Double = 1.6
    /// Clockwise in the overlay's y-up space: the top leans right.
    static let bendAngle: CGFloat = -0.17
    static let explosionSound = "03_explosion.mp3"
    /// Escape (or a re-press) only fades it out, this fast.
    static let escapeFadeSeconds: Double = 0.9

    /// Where a click counts as a click on the tower: its solid middle half
    /// (the drawing's frame is wider than the masonry) plus the eye on top.
    static func towerHitRect(in b: CGRect) -> CGRect {
        let t = towerFrame(in: b)
        let core = CGRect(x: t.minX + t.width * 0.25, y: t.minY, width: t.width * 0.5, height: t.height)
        let e = eyeCenter(in: b), s = eyeSize(in: b)
        let eye = CGRect(x: e.x - s.width * 0.6, y: e.y - s.height, width: s.width * 1.2, height: s.height * 2)
        return core.union(eye)
    }

    /// One chunk of masonry. `unit` is its rect in the tower image, unit
    /// coordinates, y UP (0 = the foot); velocities are in tower heights per
    /// second, `delay` in seconds after the break.
    struct Piece: Equatable {
        let unit: CGRect
        let vx: CGFloat
        let vy: CGFloat
        let spin: CGFloat
        let delay: Double
    }

    /// The tower cut like masonry — rows of blocks, every other row offset by
    /// half a block so no seam runs the whole way up — keeping only blocks
    /// with stone in them (`coverage`, the share of opaque pixels in a unit
    /// rect, y up). The foot gives first and the top follows a beat later, so
    /// it sinks under its own weight instead of popping apart all at once;
    /// everything drifts right, the way it leaned.
    static func pieces<R: RandomNumberGenerator>(cols: Int, rows: Int, coverage: (CGRect) -> Double,
                                                 using rng: inout R) -> [Piece] {
        var out: [Piece] = []
        let h = 1 / CGFloat(rows), w = 1 / CGFloat(cols)
        for r in 0..<rows {
            let shift = r % 2 == 1 ? w / 2 : 0
            for c in -1..<cols {
                let x0 = max(0, CGFloat(c) * w + shift), x1 = min(1, CGFloat(c + 1) * w + shift)
                guard x1 - x0 > w * 0.2 else { continue }
                let unit = CGRect(x: x0, y: CGFloat(r) * h, width: x1 - x0, height: h)
                guard coverage(unit) >= 0.06 else { continue }
                let up = unit.midY
                out.append(Piece(unit: unit,
                                 vx: CGFloat.random(in: 0.02...0.16, using: &rng) + (unit.midX - 0.5) * 0.12,
                                 vy: CGFloat.random(in: -0.05...0.12, using: &rng),
                                 spin: CGFloat.random(in: -2.6...2.6, using: &rng),
                                 delay: Double(up) * 0.45 + Double.random(in: 0...0.18, using: &rng)))
            }
        }
        return out
    }

    /// Gravity for the falling stone, in tower heights per second².
    static let rubbleGravity: CGFloat = 1.9

    /// Where a piece is `t` seconds into its fall (no air, no floor: the foot
    /// of the screen is where they leave).
    static func fallen(_ p: CGPoint, piece: Piece, towerHeight h: CGFloat, t: Double) -> CGPoint {
        let t = CGFloat(max(0, t))
        return CGPoint(x: p.x + piece.vx * h * t,
                       y: p.y + piece.vy * h * t - 0.5 * rubbleGravity * h * t * t)
    }

    /// The share of opaque pixels per unit rect (y up) of `image`, measured on
    /// a small copy once.
    static func alphaCoverage(_ image: CGImage) -> (CGRect) -> Double {
        let w = 64, h = max(1, Int((64 * CGFloat(image.height) / CGFloat(max(1, image.width))).rounded()))
        // RGBA, reading the alpha byte: an alpha-only context wants no colour
        // space at all, and with one it is silently nil — every block then
        // reads as empty and the tower falls as nothing.
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // The bitmap's first row is the image's top: y up means row h-1-y.
        return { r in
            let x0 = max(0, Int(r.minX * CGFloat(w))), x1 = min(w, Int((r.maxX * CGFloat(w)).rounded(.up)))
            let y0 = max(0, Int(r.minY * CGFloat(h))), y1 = min(h, Int((r.maxY * CGFloat(h)).rounded(.up)))
            guard x1 > x0, y1 > y0 else { return 0 }
            var solid = 0
            for y in y0..<y1 { for x in x0..<x1 where px[((h - 1 - y) * w + x) * 4 + 3] > 96 { solid += 1 } }
            return Double(solid) / Double((x1 - x0) * (y1 - y0))
        }
    }

    /// A tongue of fire, upright: round and white-hot at its foot, drawn up to
    /// a point, orange to red at the edge, soft all round. Row 0 is the TOP.
    static func flameSprite() -> CGImage? {
        if let c = cache["flame"] { return c }
        let w = 64, h = 128
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let v = 1 - (Double(y) + 0.5) / Double(h)          // 0 at the foot, 1 at the tip
            // Half-width: a round foot narrowing to the tip.
            let half = 0.46 * (v < 0.25 ? (1 - pow((0.25 - v) / 0.25, 2)).squareRoot() : pow(1 - (v - 0.25) / 0.75, 1.3))
            for x in 0..<w {
                let u = abs((Double(x) + 0.5) / Double(w) - 0.5)
                guard half > 0.001 else { continue }
                let q = u / half
                let edge = max(0, 1 - q * q)
                let a = min(1, edge * 1.4) * (1 - 0.55 * v)
                let core = max(0, 1 - q * 1.6) * (1 - v)       // the white heart, low in the tongue
                let r = 1.0, g = 0.35 + 0.55 * core + 0.1 * (1 - v), b = 0.05 + 0.6 * core
                let i = (y * w + x) * 4
                px[i] = UInt8(min(1, r) * a * 255); px[i + 1] = UInt8(min(1, g) * a * 255)
                px[i + 2] = UInt8(min(1, b) * a * 255); px[i + 3] = UInt8(a * 255)
            }
        }
        let img = px.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        cache["flame"] = img
        return img
    }

    /// A puff of smoke: soft, grey-brown, a lighter middle.
    static func dustSprite() -> CGImage? {
        glowSprite("dust", r: 0.42, g: 0.37, b: 0.33, core: 0.75, mid: 0.45)
    }

    // MARK: - The fire on the rim (2026-11-27)

    /// Victor: *"make it somehow burning … spreading like bits of fire around
    /// it"*. Points on the almond's rim (its two quadratic arcs) with the way
    /// out of the eye at each, for small emitters that throw flames off it.
    /// `lens` is the almond's rect; angles are y-up radians.
    static func rimEmitters(lens: CGRect, count: Int) -> [(point: CGPoint, outward: CGFloat)] {
        guard count > 1, lens.width > 0, lens.height > 0 else { return [] }
        let half = count / 2
        var out: [(CGPoint, CGFloat)] = []
        for arc in [1.0, -1.0] as [CGFloat] {
            for i in 0..<half {
                let t = (CGFloat(i) + 0.5) / CGFloat(half)
                let p = CGPoint(x: lens.minX + t * lens.width, y: lens.midY + arc * 2 * t * (1 - t) * lens.height)
                // The outward normal of an ellipse of the almond's size: the
                // tips throw sideways, the middle of each arc up or down.
                let nx = (p.x - lens.midX) / (lens.width * lens.width)
                let ny = (p.y - lens.midY) / (lens.height * lens.height)
                out.append((p, atan2(ny, nx)))
            }
        }
        return out
    }

    // MARK: - The living fire (assetsDir/eye-fire.png, 2026-11-27)

    /// The eye as Victor picked it — a looping clip of an eye made of fire,
    /// keyed and packed into a sprite sheet by `tools/make-eye-fire.py`
    /// (`eye-fire.png` + `eye-fire.json`). Not ours to publish, so it is an
    /// `assetsDir` drop-in: without it the eye is drawn (`eyeSprite`).
    struct FireSheet {
        let image: CGImage
        let cols: Int
        let rows: Int
        let frames: Int
        let seconds: Double

        /// Frame `i`'s rect in the sheet, unit coordinates, y UP (a CALayer's
        /// contentsRect on the Mac): the sheet's top row is the highest.
        func rect(_ i: Int) -> CGRect {
            let w = 1 / CGFloat(cols), h = 1 / CGFloat(rows)
            return CGRect(x: CGFloat(i % cols) * w, y: 1 - CGFloat(i / cols + 1) * h, width: w, height: h)
        }
    }

    /// Where the flames of the clip's eye sit in one of its frames: the eye's
    /// body spans x 30…185 of 210 and y 10…145 of 150.
    static let fireBodyShare = CGSize(width: 155.0 / 210, height: 135.0 / 150)
    /// The clip's eye is rounder than the drawn almond; laid over it, its
    /// body is this much of the almond's width wide and of its height tall.
    /// 1.4 wide since 2026-11-27 evening (was 1.15) — Victor: *"stretch it a bit
    /// towards the left-right 'insertion' points into the tower"*.
    static let fireBodyOverLens = CGSize(width: 1.4, height: 1.9)

    // MARK: - The gaze in the fire (2026-11-27, evening)

    /// Victor, over the clip with a pupil drawn on it: *"when the eye has to
    /// move, stretch it slightly towards that direction, so that the black
    /// centre moves gently towards where the gaze points"*. The clip's own slit
    /// is the pupil now; the fire is WARPED so its middle slides toward the
    /// light while its edges stay where they are (the tips stay at the horns):
    /// each axis maps `u → u + s·sin(πu)`, `s` a share of the body. Separable,
    /// so a grid of tiles cut from the frame stays a grid of rectangles —
    /// Core Animation can draw it with `contentsRect`s, no mesh needed.
    static let gazeShiftMax = CGSize(width: 0.11, height: 0.04)
    /// The light is always below the eye, so the slit looks down a little more
    /// than up; far to the side it has gone as far as it goes.
    static func gazeShift(eye: CGPoint, spot: CGPoint, in b: CGRect) -> CGPoint {
        guard b.width > 0, b.height > 0 else { return .zero }
        let dx = max(-1, min(1, (spot.x - eye.x) / (b.width * 0.6)))
        let dy = max(-1, min(0.3, (spot.y - eye.y) / b.height))
        return CGPoint(x: dx * gazeShiftMax.width, y: dy * gazeShiftMax.height)
    }
    /// Where unit coordinate `u` of the clip lands in the body. Monotonic (no
    /// fold) while `|s| < 1/π`, which `gazeShiftMax` stays well under.
    static func warp(_ u: CGFloat, shift s: CGFloat) -> CGFloat {
        u + s * sin(.pi * u)
    }
    /// The grid the body is cut into: enough that the piecewise-linear warp
    /// reads as a curve.
    static let gazeTiles = (cols: 12, rows: 6)

    static func fireFrame(lens: CGRect) -> CGRect {
        let w = lens.width * fireBodyOverLens.width / fireBodyShare.width
        let h = lens.height * fireBodyOverLens.height / fireBodyShare.height
        return CGRect(x: lens.midX - w / 2, y: lens.midY - h / 2, width: w, height: h)
    }

    private static var fireSheetCache: FireSheet??
    static func fireSheet() -> FireSheet? {
        if let cached = fireSheetCache { return cached }
        var sheet: FireSheet?
        if let png = EffectsResources.url("eye-fire", "png"),
           let json = EffectsResources.url("eye-fire", "json"),
           let data = try? Data(contentsOf: json),
           let meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let cols = meta["cols"] as? Int, let rows = meta["rows"] as? Int,
           let frames = meta["frames"] as? Int, let seconds = (meta["seconds"] as? NSNumber)?.doubleValue,
           cols > 0, rows > 0, frames > 0, seconds > 0,
           let src = CGImageSourceCreateWithURL(png as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            sheet = FireSheet(image: image, cols: cols, rows: rows, frames: frames, seconds: seconds)
        }
        fireSheetCache = .some(sheet)
        return sheet
    }

    // MARK: - Sprites (drawn once, cached)

    private static var cache: [String: CGImage] = [:]

    private static func canvas(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// An almond (vesica) inside `r`: two arcs meeting at the left and right tips.
    static func almond(in r: CGRect) -> CGPath {
        let p = CGMutablePath()
        let left = CGPoint(x: r.minX, y: r.midY), right = CGPoint(x: r.maxX, y: r.midY)
        p.move(to: left)
        p.addQuadCurve(to: right, control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.5))
        p.addQuadCurve(to: left, control: CGPoint(x: r.midX, y: r.minY - r.height * 0.5))
        p.closeSubpath()
        return p
    }

    /// The burning eye, flames licking off its rim, no pupil (that moves on its own).
    static func eyeSprite() -> CGImage? {
        if let c = cache["eye"] { return c }
        let w = 640, h = 400
        guard let ctx = canvas(w, h) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let lens = CGRect(x: CGFloat(w) * 0.12, y: CGFloat(h) * 0.30, width: CGFloat(w) * 0.76, height: CGFloat(h) * 0.40)
        let mid = CGPoint(x: lens.midX, y: lens.midY)

        // Flames: tongues off the rim, pointing out, under the lens.
        var rng = SplitMix(seed: 7)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 26, color: CGColor(red: 1, green: 0.35, blue: 0.0, alpha: 1))
        for i in 0..<70 {
            let a = Double(i) / 70 * 2 * .pi + rng.unit() * 0.08
            let rx = lens.width * 0.5, ry = lens.height * 0.5 * (0.75 + 0.25 * abs(sin(a)))
            let base = CGPoint(x: mid.x + rx * CGFloat(cos(a)) * 0.92, y: mid.y + ry * CGFloat(sin(a)) * 0.92)
            let len = CGFloat(18 + rng.unit() * 46) * (0.6 + 0.6 * CGFloat(abs(sin(a))))
            let out = CGPoint(x: CGFloat(cos(a)) * 0.55, y: CGFloat(sin(a)) * 1.0)
            let n = hypot(out.x, out.y)
            let dir = CGPoint(x: out.x / n, y: out.y / n)
            let tip = CGPoint(x: base.x + dir.x * len, y: base.y + dir.y * len)
            let half = CGFloat(6 + rng.unit() * 8)
            let tongue = CGMutablePath()
            tongue.move(to: CGPoint(x: base.x - dir.y * half, y: base.y + dir.x * half))
            tongue.addQuadCurve(to: tip, control: CGPoint(x: base.x + dir.x * len * 0.6 - dir.y * half * 0.4,
                                                         y: base.y + dir.y * len * 0.6 + dir.x * half * 0.4))
            tongue.addQuadCurve(to: CGPoint(x: base.x + dir.y * half, y: base.y - dir.x * half),
                                control: CGPoint(x: base.x + dir.x * len * 0.5 + dir.y * half * 0.6,
                                                 y: base.y + dir.y * len * 0.5 - dir.x * half * 0.6))
            tongue.closeSubpath()
            let hot = rng.unit()
            ctx.setFillColor(CGColor(red: 1, green: CGFloat(0.35 + 0.4 * hot), blue: CGFloat(0.05 * hot), alpha: CGFloat(0.55 + 0.35 * rng.unit())))
            ctx.addPath(tongue)
            ctx.fillPath()
        }
        ctx.restoreGState()

        // The lens: white-hot in the middle, through yellow and orange to deep red.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 30, color: CGColor(red: 1, green: 0.45, blue: 0.05, alpha: 1))
        ctx.addPath(almond(in: lens))
        ctx.setFillColor(CGColor(red: 0.7, green: 0.12, blue: 0.0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(almond(in: lens))
        ctx.clip()
        if let g = CGGradient(colorSpace: space, colorComponents: [
            1.00, 1.00, 0.88, 1,
            1.00, 0.86, 0.30, 1,
            1.00, 0.52, 0.06, 1,
            0.78, 0.18, 0.00, 1,
            0.40, 0.03, 0.00, 1], locations: [0, 0.18, 0.45, 0.78, 1], count: 5) {
            ctx.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid,
                                   endRadius: lens.width * 0.5, options: [.drawsAfterEndLocation])
        }
        // Fiery streaks radiating from the centre, the iris's grain.
        for i in 0..<48 {
            let a = Double(i) / 48 * 2 * .pi + rng.unit() * 0.1
            let r0 = lens.height * 0.18, r1 = lens.width * CGFloat(0.35 + 0.15 * rng.unit())
            ctx.move(to: CGPoint(x: mid.x + r0 * CGFloat(cos(a)), y: mid.y + r0 * CGFloat(sin(a))))
            ctx.addLine(to: CGPoint(x: mid.x + r1 * CGFloat(cos(a)), y: mid.y + r1 * CGFloat(sin(a))))
            ctx.setStrokeColor(CGColor(red: 0.55, green: 0.08, blue: 0, alpha: CGFloat(0.25 + 0.3 * rng.unit())))
            ctx.setLineWidth(CGFloat(1.5 + 2.5 * rng.unit()))
            ctx.strokePath()
        }
        ctx.restoreGState()
        let img = ctx.makeImage()
        cache["eye"] = img
        return img
    }

    /// Fraction of the eye sprite the lens takes, so the layer can be sized
    /// from the lens the layout wants.
    static let eyeSpriteLensShare = CGSize(width: 0.76, height: 0.40)

    /// The cat's slit, black with a dark-red edge.
    static func pupilSprite() -> CGImage? {
        if let c = cache["pupil"] { return c }
        let w = 60, h = 240
        guard let ctx = canvas(w, h) else { return nil }
        let r = CGRect(x: 8, y: 6, width: CGFloat(w) - 16, height: CGFloat(h) - 12)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.maxX + r.width * 0.6, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.minX - r.width * 0.6, y: r.midY))
        p.closeSubpath()
        ctx.setShadow(offset: .zero, blur: 6, color: CGColor(red: 0.4, green: 0.0, blue: 0.0, alpha: 1))
        ctx.addPath(p)
        ctx.setFillColor(CGColor(red: 0.02, green: 0.0, blue: 0.0, alpha: 1))
        ctx.fillPath()
        let img = ctx.makeImage()
        cache["pupil"] = img
        return img
    }

    /// The cone: narrow and brightest at the top (the eye), widening to the full
    /// sprite width at the foot, gaussian across so it has no edge, fading out
    /// over its last stretch. Row 0 is the TOP of the image.
    static func beamSprite() -> CGImage? {
        if let c = cache["beam"] { return c }
        let w = 160, h = 320
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let col = (r: 1.0, g: 0.66, b: 0.26)
        let footEnd = Double(1 / beamOvershoot)          // where the spot's centre falls
        for y in 0..<h {
            let v = Double(y) / Double(h - 1)
            let half = 0.06 + 0.40 * v                     // half-width, unit of sprite width
            var along = 0.55 - 0.30 * v                    // dimmer as it travels
            if v > footEnd * 0.82 { along *= max(0, 1 - (v - footEnd * 0.82) / (1 - footEnd * 0.82)) }
            for x in 0..<w {
                let u = (Double(x) + 0.5) / Double(w) - 0.5
                let q = u / half
                let a = max(0, min(1, along * exp(-q * q * 2.2)))
                let i = (y * w + x) * 4
                px[i] = UInt8(col.r * a * 255); px[i + 1] = UInt8(col.g * a * 255)
                px[i + 2] = UInt8(col.b * a * 255); px[i + 3] = UInt8(a * 255)
            }
        }
        let img = px.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        cache["beam"] = img
        return img
    }

    /// A soft round glow, `color` in the middle, nothing at the rim.
    static func glowSprite(_ key: String, r: CGFloat, g: CGFloat, b: CGFloat, core: CGFloat, mid: CGFloat) -> CGImage? {
        if let c = cache[key] { return c }
        let s = 256
        guard let ctx = canvas(s, s),
              let grad = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: [
                min(1, r + 0.1), min(1, g + 0.15), min(1, b + 0.2), core,
                r, g, b, mid,
                r, g * 0.8, b * 0.6, 0], locations: [0, 0.55, 1], count: 3) else { return nil }
        let c = CGPoint(x: CGFloat(s) / 2, y: CGFloat(s) / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(s) / 2, options: [])
        let img = ctx.makeImage()
        cache[key] = img
        return img
    }

    /// The dark, with a soft hole in the middle whose radius is `1/k` of the
    /// sprite's (i.e. the spot's ellipse once the layer is the spot scaled by k).
    static func darknessSprite(k: CGFloat) -> CGImage? {
        let key = "dark@\(Int(k * 10))"
        if let c = cache[key] { return c }
        let s = 1536
        var px = [UInt8](repeating: 0, count: s * s * 4)
        let hole = Double(0.5 / k) * 0.78          // fully lit inside this (unit radius)
        let edge = Double(0.5 / k) * 1.25          // fully dark beyond this
        let tint = (r: 0.06, g: 0.01, b: 0.0)
        for y in 0..<s {
            let v = (Double(y) + 0.5) / Double(s) - 0.5
            for x in 0..<s {
                let u = (Double(x) + 0.5) / Double(s) - 0.5
                let d = (u * u + v * v).squareRoot()
                let t = max(0, min(1, (d - hole) / (edge - hole)))
                let a = t * t * (3 - 2 * t)
                let i = (y * s + x) * 4
                px[i] = UInt8(tint.r * a * 255); px[i + 1] = UInt8(tint.g * a * 255)
                px[i + 2] = UInt8(tint.b * a * 255); px[i + 3] = UInt8(a * 255)
            }
        }
        let img = px.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: s, height: s, bitsPerComponent: 8, bytesPerRow: s * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        cache[key] = img
        return img
    }
}
