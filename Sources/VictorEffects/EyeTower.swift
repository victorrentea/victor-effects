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
    static func spotSize(in b: CGRect) -> CGSize {
        let w = b.width * 0.14
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
