import AppKit
import QuartzCore

/// 🦀 How Clawd feels while he is on screen for ⌘⌃Q (2026-10-25, Victor: *"the
/// claude icon entering from left on cmd-ctrl q be cool, happy or excited when it
/// enters, but turn scared on whip on, dizzy on whiplash, hopeful on man starting
/// to pray, and turn to cool at finger snap"*).
///
/// The faces are the ones on the model sheet of John Heibel's
/// [ClaudeAnimationBase](https://github.com/JohnHeibel/ClaudeAnimationBase)
/// (MIT; `docs/emotions.jpg` there): same eyes, mouths, emotes and colours, the
/// p5.brush watercolour swapped for flat fills under a hand-wobbled ink line,
/// because this is drawn once into a `CGImage` and not painted every frame.
///
/// Six more ways to walk in came on 2026-10-28 (Victor: *"vreau ca intrarea
/// să aibă încă șase tipuri de atitudini … înainte de a scoate biciul, el vine
/// cu niște atitudini deja"*): sleepy, grumpy, in love, cheeky, sneaky and
/// curious — so the room sees nine different Clawds before the whip is out.
///
/// **What triggers each one lives with the trigger, not here**: the entrance in
/// `EmojiAnimator.showClaudePeek`, the rest in `EffectsEngine` (whip on, pray on
/// / a hymn, a snap) and `EmojiAnimator.whipLash` (a hit). This file only knows
/// what a mood looks like and how it moves.
enum ClawdMood: String, CaseIterable {
    case cool, happy, excited, scared, dizzy, hopeful
    case sleepy, grumpy, love, cheeky, sneaky, curious

    /// What he may walk in as. Never the same one twice in a row
    /// (`entrance(after:roll:)`): a greeting that repeats stops being one.
    static let entrances: [ClawdMood] = [.cool, .happy, .excited,
                                         .sleepy, .grumpy, .love, .cheeky, .sneaky, .curious]

    /// The entrance after `previous`: one of the *other* entrance moods, picked
    /// by `roll` (any non-negative number — the caller's random). Pure, so the
    /// no-repeat rule is a test and not a hope.
    static func entrance(after previous: ClawdMood?, roll: Int) -> ClawdMood {
        let pool = entrances.filter { $0 != previous }
        return pool[abs(roll) % pool.count]
    }

    /// The emote that floats by his head, if this mood has one.
    var emote: ClawdEmote? {
        switch self {
        case .cool: return .music
        case .excited: return .spark
        case .scared: return .sweat
        case .dizzy: return .stars
        case .sleepy: return .zzz
        case .grumpy: return .anger
        case .love: return .hearts
        case .curious: return .question
        case .happy, .hopeful, .cheeky, .sneaky: return nil
        }
    }
}

enum ClawdEmote: CaseIterable { case music, spark, sweat, stars, zzz, anger, hearts, question }

/// Clawd drawn in a mood, at **exactly the geometry of `claude-icon.png`**
/// (461×363: body x 43…418 by y 0…268, arm nubs out to both edges at y 89…180,
/// four legs to the bottom). Keeping the canvas is what lets everything already
/// measured off that PNG keep working untouched — `claudePeekFrame`'s aspect,
/// the 🎅 hat's origin, the white rim, the whip's alpha hit-mask.
///
/// All coordinates below are icon pixels with **y down**, the way an image
/// editor and the source sheet both count. `u` is the sheet's body unit: the
/// body is 10u wide.
enum ClawdArt {
    static let canvas = CGSize(width: 461, height: 363)
    static let u: CGFloat = 37.5

    /// Hand-drawn line "boil": each mood is drawn this many times with a
    /// different wobble and cycled, which is the one thing that makes a still
    /// drawing read as a cartoon rather than as a sticker.
    static let boilFrames = 3
    /// On eights, a little slower than the sheet's own boil — he is big on a
    /// projector, and a fast boil there reads as jitter.
    static let boilInterval: Double = 1.0 / 7

    // MARK: layout (icon pixels, y down)

    static let body = CGRect(x: 45, y: 4, width: 371, height: 262)
    static let centreX: CGFloat = 230.5
    static let eyeY: CGFloat = 100
    static let eyeDX: CGFloat = 94           // 2.5u
    static let mouthY: CGFloat = 178
    static let legs: [ClosedRange<CGFloat>] = [45...80, 127...164, 296...333, 381...416]
    static let legBottom: CGFloat = 360

    /// Where the O mouth of a whip hit goes (`PeekOMouth`), as fractions of the
    /// picture — the drawn mouth, not the old PNG's.
    static let mouthFraction = CGPoint(x: centreX / canvas.width, y: mouthY / canvas.height)

    // MARK: palette (the sheet's PAL)

    static let ink = rgb(0x2B2233)
    static let clay = rgb(0xD97757)
    static let clayDark = rgb(0xA84D33)
    static let clayLight = rgb(0xF5B394)
    static let cream = rgb(0xFFF5E2)
    static let rose = rgb(0xE27A92)
    static let ochre = rgb(0xE8AA38)
    static let sky = rgb(0x8EC3E6)
    static let lens = rgb(0x2A2740)
    static let mouthDark = rgb(0x4A1F2A)
    static let pale = rgb(0xF6E6D2)
    static let heartRed = rgb(0xE0465A)
    static let angry = rgb(0xC8442E)

    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    static func mix(_ a: CGColor, _ b: CGColor, _ k: CGFloat) -> CGColor {
        let x = a.components ?? [0, 0, 0, 1], y = b.components ?? [0, 0, 0, 1]
        return CGColor(srgbRed: x[0] + (y[0] - x[0]) * k, green: x[1] + (y[1] - x[1]) * k,
                       blue: x[2] + (y[2] - x[2]) * k, alpha: 1)
    }

    // MARK: per-mood pose

    struct Face {
        var eyes: String
        var mouth: String
        var blush: CGFloat = 0
        var pale: CGFloat = 0
        /// Arm raise, radians: 0 straight out, + up, - down (the sheet's aL/aR).
        var armL: CGFloat = 0.2
        var armR: CGFloat = 0.2
        var lookY: CGFloat = 0
        /// Red in the face (grumpy): the clay pulled toward `angry`.
        var heat: CGFloat = 0
    }

    static func face(_ mood: ClawdMood) -> Face {
        switch mood {
        case .cool:    return Face(eyes: "shades", mouth: "smirk", armL: -0.4, armR: 0.7)
        case .happy:   return Face(eyes: "happy", mouth: "smile", blush: 0.3, armL: 0.6, armR: 0.6)
        case .excited: return Face(eyes: "wide", mouth: "open", armL: 1.0, armR: 1.0)
        case .scared:  return Face(eyes: "scared", mouth: "wobble", pale: 0.6, armL: 0.95, armR: 0.95)
        case .dizzy:   return Face(eyes: "swirl", mouth: "wobble", armL: 0.35, armR: -0.2)
        case .hopeful: return Face(eyes: "shine", mouth: "cat", blush: 0.35, armL: 0.5, armR: 0.5, lookY: -0.4)
        case .sleepy:  return Face(eyes: "sleepy", mouth: "yawn", armL: -0.65, armR: -0.65)
        case .grumpy:  return Face(eyes: "angry", mouth: "frown", armL: -0.5, armR: -0.5, heat: 0.45)
        case .love:    return Face(eyes: "heart", mouth: "grin", blush: 0.6, armL: 0.85, armR: 0.85)
        case .cheeky:  return Face(eyes: "wink", mouth: "tongue", blush: 0.2, armL: 0.1, armR: 1.1)
        case .sneaky:  return Face(eyes: "shifty", mouth: "evil", armL: -0.15, armR: 0.25)
        case .curious: return Face(eyes: "curious", mouth: "o", armL: -0.3, armR: 0.95)
        }
    }

    // MARK: rendering

    private static var cache: [String: CGImage] = [:]

    /// Clawd in `mood`, boil frame `boil` (0..<boilFrames). Cached: each is
    /// drawn once per run. Nil only if no bitmap context can be made.
    static func picture(_ mood: ClawdMood, boil: Int = 0) -> CGImage? {
        let key = "\(mood.rawValue)#\(boil)"
        if let hit = cache[key] { return hit }
        guard let ctx = makeContext(canvas) else { return nil }
        var pen = Pen(ctx: ctx, rng: SplitMix(seed: UInt64(boil + 1) &* 0x9E37_79B9))
        draw(mood, boil: boil, pen: &pen)
        let image = ctx.makeImage()
        cache[key] = image
        return image
    }

    /// A y-down sRGB context, so the numbers above read the same as the sheet.
    static func makeContext(_ size: CGSize) -> CGContext? {
        guard let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        return ctx
    }

    private static func draw(_ mood: ClawdMood, boil: Int, pen: inout Pen) {
        let f = face(mood)
        let ctx = pen.ctx
        let col = mix(mix(clay, pale, 0.55 * f.pale), angry, 0.5 * f.heat)
        let dark = mix(clayDark, mix(pale, ink, 0.35), 0.5 * f.pale)
        let light = mix(clayLight, cream, 0.45 * f.pale)

        // arms behind the body
        arm(side: -1, raise: f.armL, col: col, dark: dark, pen: &pen)
        arm(side: 1, raise: f.armR, col: col, dark: dark, pen: &pen)

        // legs under it
        for x in legs {
            let leg = pen.wobblyRect(CGRect(x: x.lowerBound, y: body.maxY - 14,
                                            width: x.upperBound - x.lowerBound,
                                            height: legBottom - body.maxY + 14), jitter: 1.6)
            pen.fill(leg, dark)
            pen.stroke(leg, ink, 7)
        }

        // the body: flat clay, a light wash top-left, a darker band at the bottom
        let shell = pen.wobblyRect(body, jitter: 2.6)
        pen.fill(shell, col)
        ctx.saveGState()
        ctx.addPath(shell)
        ctx.clip()
        let glow = CGMutablePath()
        glow.addEllipse(in: CGRect(x: centreX - 60 - 127, y: body.minY + 64 - 56, width: 254, height: 112),
                        transform: CGAffineTransform(translationX: 0, y: 0))
        ctx.setFillColor(light.copy(alpha: 0.55)!)
        ctx.addPath(pen.wobbly(glow, jitter: 5))
        ctx.fillPath()
        ctx.setFillColor(dark.copy(alpha: 0.45)!)
        ctx.addPath(pen.wobblyRect(CGRect(x: body.minX - 4, y: body.maxY - 58,
                                          width: body.width + 8, height: 70), jitter: 3))
        ctx.fillPath()
        ctx.restoreGState()
        pen.stroke(shell, ink, 9)

        if f.blush > 0 { blush(f.blush, pen: &pen) }
        eyes(f, boil: boil, pen: &pen)
        mouth(f.mouth, pen: &pen)
    }

    /// One arm nub, pivoting at the body's edge. Drawn before the body so its
    /// root disappears behind it, the way the sheet layers them.
    private static func arm(side: CGFloat, raise: CGFloat, col: CGColor, dark: CGColor, pen: inout Pen) {
        let ctx = pen.ctx
        let pivot = CGPoint(x: side < 0 ? body.minX + 10 : body.maxX - 10, y: 136)
        ctx.saveGState()
        ctx.translateBy(x: pivot.x, y: pivot.y)
        // y is down: "up" for the left arm is a clockwise turn, for the right
        // one counter-clockwise.
        ctx.rotate(by: side < 0 ? raise : -raise)
        let r = side < 0
            ? CGRect(x: -52, y: -19, width: 56, height: 38)
            : CGRect(x: -4, y: -19, width: 56, height: 38)
        let path = pen.wobblyRect(r, jitter: 1.4)
        pen.fill(path, col)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(dark.copy(alpha: 0.25)!)
        ctx.fill(CGRect(x: r.minX, y: 4, width: r.width, height: 20))
        ctx.restoreGState()
        pen.stroke(path, ink, 7)
        ctx.restoreGState()
    }

    private static func blush(_ k: CGFloat, pen: inout Pen) {
        for s: CGFloat in [-1, 1] {
            let c = CGPoint(x: centreX + s * 135, y: mouthY - 8)
            pen.ctx.setFillColor(rose.copy(alpha: 0.35 + 0.4 * k)!)
            pen.ctx.fillEllipse(in: CGRect(x: c.x - 32, y: c.y - 16, width: 64, height: 32))
        }
    }

    // MARK: eyes

    private static func eyes(_ f: Face, boil: Int, pen: inout Pen) {
        if f.eyes == "shades" { shades(pen: &pen); return }
        for s: CGFloat in [-1, 1] {
            let c = CGPoint(x: centreX + s * eyeDX, y: eyeY)
            eye(f.eyes, side: s, at: c, lookY: f.lookY, boil: boil, pen: &pen)
        }
    }

    private static func eye(_ kind: String, side s: CGFloat, at c: CGPoint, lookY: CGFloat,
                            boil: Int, pen: inout Pen) {
        let ctx = pen.ctx
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * u, y: c.y + y * u) }
        func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
            CGRect(x: c.x + (cx - rx) * u, y: c.y + (cy - ry) * u, width: 2 * rx * u, height: 2 * ry * u)
        }
        switch kind {
        case "happy":
            pen.line([p(-0.9, 0.7), p(0, -0.5), p(0.9, 0.7)], ink, 11, smooth: true)
        case "wide":
            let w: CGFloat = 1.25, h: CGFloat = 2.7
            ctx.setFillColor(ink)
            ctx.addPath(CGPath(roundedRect: oval(0, 0, w / 2, h / 2), cornerWidth: 5, cornerHeight: 5, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(cream.copy(alpha: 0.92)!)
            ctx.fillEllipse(in: oval(-w * 0.18, -h * 0.29, 0.17 * w, 0.24 * w))
        case "scared":
            let white = CGPath(ellipseIn: oval(0, 0, 0.95, 1.15), transform: nil)
            pen.fill(pen.wobbly(white, jitter: 1.2), cream)
            pen.stroke(pen.wobbly(white, jitter: 1.2), ink, 5)
            // the pupil shakes from boil to boil — the sheet does it at 40 Hz
            let jx = [0.0, 0.05, -0.05][boil % 3]
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: oval(CGFloat(jx), 0.1, 0.3, 0.4))
        case "swirl":
            var pts: [CGPoint] = []
            let phase = CGFloat(boil) * 2.1 * s
            for k in 0..<48 {
                let a = CGFloat(k) * 0.233 + phase, r = CGFloat(k) * 0.02 * u
                pts.append(CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            }
            pen.line(pts, ink, 6, smooth: false)
        case "shine":
            let ly = lookY * 0.4 * 0.6
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: oval(0, ly, 0.78, 1.12))
            ctx.setFillColor(cream)
            ctx.fillEllipse(in: oval(-0.25, ly - 0.45, 0.3, 0.38))
            ctx.fillEllipse(in: oval(0.25, ly + 0.45, 0.14, 0.14))
        case "sleepy":     // half-shut: the lower half of the pupil under a drooping lid
            ctx.saveGState()
            ctx.clip(to: CGRect(x: c.x - u, y: c.y + 0.05 * u, width: 2 * u, height: u))
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: oval(0, 0.1, 0.55, 0.5))
            ctx.restoreGState()
            pen.line([p(-0.8, -0.05 + 0.12 * s), p(0, 0.05), p(0.8, -0.05 - 0.12 * s)], ink, 9, smooth: true)
        case "angry":      // a short pupil under a brow that dives toward the nose
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: oval(0, 0.2, 0.45, 0.7))
            pen.line([p(s * 1.0, -1.35), p(-s * 0.75, -0.6)], ink, 12)
        case "heart":
            let h = heart(center: c, r: 0.95 * u)
            pen.fill(h, heartRed)
            pen.stroke(h, ink, 6)
            ctx.setFillColor(cream.copy(alpha: 0.9)!)
            ctx.fillEllipse(in: oval(-0.45, -0.35, 0.18, 0.14))
        case "wink":       // the left one open and shining, the right one shut
            if s < 0 {
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: oval(0, 0, 0.7, 1.05))
                ctx.setFillColor(cream)
                ctx.fillEllipse(in: oval(-0.22, -0.4, 0.26, 0.32))
            } else {
                pen.line([p(-0.9, 0.05), p(0, 0.45), p(0.9, 0.05)], ink, 11, smooth: true)
                pen.line([p(0.85, 0.05), p(1.2, -0.3)], ink, 7)   // a lash flick
            }
        case "shifty":     // narrowed, both glancing to the right
            ctx.saveGState()
            ctx.clip(to: CGRect(x: c.x - u, y: c.y - 0.2 * u + 0.15 * s * u, width: 2 * u, height: u))
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: oval(0.35, 0.15, 0.45, 0.65))
            ctx.restoreGState()
            pen.line([p(-0.85, -0.2 + 0.15 * s), p(0.85, -0.2 - 0.15 * s)], ink, 9)
        case "curious":    // one eye wide, the other squinting under a raised brow
            if s < 0 {
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: oval(0, 0, 0.75, 1.1))
                ctx.setFillColor(cream)
                ctx.fillEllipse(in: oval(-0.25, -0.42, 0.26, 0.32))
            } else {
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: oval(0, 0.15, 0.42, 0.55))
                pen.line([p(-0.8, -1.2), p(0, -1.65), p(0.85, -1.35)], ink, 9, smooth: true)
            }
        default:
            ctx.setFillColor(ink)
            ctx.fill(oval(0, 0, 0.5, 1))
        }
    }

    /// A heart, `r` its half-width, point down (y down). Built of curves and
    /// NOT run through `Pen.wobbly`, which would trace it as an ellipse.
    static func heart(center c: CGPoint, r: CGFloat) -> CGPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * r, y: c.y + y * r) }
        let path = CGMutablePath()
        path.move(to: p(0, 0.9))
        path.addCurve(to: p(-1, -0.25), control1: p(-0.55, 0.5), control2: p(-1, 0.15))
        path.addCurve(to: p(0, -0.45), control1: p(-1, -0.95), control2: p(-0.15, -0.95))
        path.addCurve(to: p(1, -0.25), control1: p(0.15, -0.95), control2: p(1, -0.95))
        path.addCurve(to: p(0, 0.9), control1: p(1, 0.15), control2: p(0.55, 0.5))
        path.closeSubpath()
        return path
    }

    /// Sunglasses: two dark lenses, a bridge, arms running back to the edges.
    private static func shades(pen: inout Pen) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: centreX + x * u, y: eyeY + y * u) }
        for s: CGFloat in [-1, 1] {
            pen.line([p(s * 3.85, -0.85), p(s * 4.95, -0.95)], ink, 7)
        }
        pen.line([p(-1.15, -0.75), p(0, -1.05), p(1.15, -0.75)], ink, 7, smooth: true)
        for s: CGFloat in [-1, 1] {
            let cx = s * 2.5
            let lens = CGMutablePath()
            lens.addLines(between: [p(cx - 1.4, -1.1), p(cx + 1.4, -1.1), p(cx + 1.3, -0.2),
                                    p(cx + 0.8, 0.65), p(cx, 0.8), p(cx - 0.8, 0.65), p(cx - 1.3, -0.2)])
            lens.closeSubpath()
            let shape = pen.wobbly(lens, jitter: 1.2)
            pen.fill(shape, ClawdArt.lens)
            pen.stroke(shape, ink, 7)
            pen.line([p(cx - 0.85, -0.35), p(cx - 0.25, -0.85)], cream, 4.5)   // glint
            pen.line([p(cx - 0.45, 0.15), p(cx - 0.05, -0.2)], cream, 3)
        }
    }

    // MARK: mouths

    private static func mouth(_ kind: String, pen: inout Pen) {
        let ctx = pen.ctx
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: centreX + x * u, y: mouthY + y * u) }
        switch kind {
        case "smile": pen.line([p(-0.8, -0.3), p(0, 0.2), p(0.8, -0.3)], ink, 9, smooth: true)
        case "smirk": pen.line([p(-0.8, -0.05), p(0.2, 0), p(0.9, -0.45)], ink, 9, smooth: true)
        case "wobble": pen.line([p(-1, -0.1), p(-0.5, -0.4), p(0, -0.1), p(0.5, -0.4), p(1, -0.1)], ink, 8, smooth: true)
        case "cat": pen.line([p(-0.9, -0.2), p(-0.45, 0.2), p(0, -0.2), p(0.45, 0.2), p(0.9, -0.2)], ink, 8, smooth: true)
        case "open":
            let o = CGPath(ellipseIn: CGRect(x: centreX - 0.75 * u, y: mouthY + 0.05 * u - 0.6 * u,
                                             width: 1.5 * u, height: 1.2 * u), transform: nil)
            let shape = pen.wobbly(o, jitter: 1)
            pen.fill(shape, mouthDark)
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            ctx.setFillColor(rose)
            ctx.fillEllipse(in: CGRect(x: centreX - 0.45 * u, y: mouthY + 0.35 * u - 0.2 * u,
                                       width: 0.9 * u, height: 0.5 * u))
            ctx.restoreGState()
            pen.stroke(shape, ink, 6)
        case "frown": pen.line([p(-0.8, 0.3), p(0, -0.15), p(0.8, 0.3)], ink, 9, smooth: true)
        case "yawn":
            let o = CGPath(ellipseIn: CGRect(x: centreX - 0.35 * u, y: mouthY - 0.45 * u,
                                             width: 0.7 * u, height: 0.9 * u), transform: nil)
            let shape = pen.wobbly(o, jitter: 0.8)
            pen.fill(shape, mouthDark)
            pen.stroke(shape, ink, 6)
        case "o":
            let o = CGPath(ellipseIn: CGRect(x: centreX + 0.15 * u, y: mouthY - 0.25 * u,
                                             width: 0.5 * u, height: 0.5 * u), transform: nil)
            pen.stroke(pen.wobbly(o, jitter: 0.6), ink, 7)
        case "grin":       // a wide open D: flat on top, round below, a tongue in it
            let d = CGMutablePath()
            d.move(to: p(-1.0, -0.35))
            d.addLine(to: p(1.0, -0.35))
            d.addQuadCurve(to: p(-1.0, -0.35), control: p(0, 1.15))
            d.closeSubpath()
            pen.fill(d, mouthDark)
            ctx.saveGState()
            ctx.addPath(d)
            ctx.clip()
            ctx.setFillColor(rose)
            ctx.fillEllipse(in: CGRect(x: centreX - 0.55 * u, y: mouthY + 0.1 * u, width: 1.1 * u, height: 0.6 * u))
            ctx.restoreGState()
            pen.stroke(d, ink, 6)
        case "tongue":     // a lopsided smile with the tongue out on the right
            let t = CGMutablePath()
            t.move(to: p(0.05, -0.05))
            t.addLine(to: p(0.75, -0.2))
            t.addQuadCurve(to: p(0.05, -0.05), control: p(0.5, 0.95))
            t.closeSubpath()
            pen.fill(t, rose)
            pen.stroke(t, ink, 5)
            pen.line([p(0.42, 0.0), p(0.45, 0.3)], mouthDark, 3.5)
            pen.line([p(-0.9, -0.3), p(-0.2, 0.05), p(0.95, -0.25)], ink, 9, smooth: true)
        case "evil":       // a too-wide toothy grin
            let g = CGMutablePath()
            g.move(to: p(-1.35, -0.45))
            g.addQuadCurve(to: p(1.35, -0.45), control: p(0, -0.05))
            g.addQuadCurve(to: p(-1.35, -0.45), control: p(0, 1.05))
            g.closeSubpath()
            pen.fill(g, cream)
            ctx.saveGState()
            ctx.addPath(g)
            ctx.clip()
            for x: CGFloat in [-0.75, -0.25, 0.25, 0.75] {
                pen.line([p(x, -0.6), p(x, 0.8)], ink, 3.5)
            }
            pen.line([p(-1.4, 0.05), p(1.4, 0.05)], ink, 3.5)
            ctx.restoreGState()
            pen.stroke(g, ink, 7)
        default: break
        }
    }

    // MARK: emotes

    /// One emote as its own small picture, centred, `side` pixels square, so
    /// the animator can move it about without redrawing Clawd.
    static func emotePicture(_ emote: ClawdEmote) -> CGImage? {
        let key = "emote:\(emote)"
        if let hit = cache[key] { return hit }
        let side: CGFloat = 120
        guard let ctx = makeContext(CGSize(width: side, height: side)) else { return nil }
        var pen = Pen(ctx: ctx, rng: SplitMix(seed: 7))
        let c = CGPoint(x: side / 2, y: side / 2)
        let s: CGFloat = 21     // the sheet's emote unit, in icon pixels
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * s, y: c.y + y * s) }
        switch emote {
        case .music:
            // two quavers, the second one lower and to the right
            ctx.setFillColor(ink)
            ctx.saveGState(); ctx.translateBy(x: p(-1.1, 1.0).x, y: p(-1.1, 1.0).y); ctx.rotate(by: -0.3)
            ctx.fillEllipse(in: CGRect(x: -0.7 * s, y: -0.5 * s, width: 1.4 * s, height: 1.0 * s)); ctx.restoreGState()
            pen.line([p(-0.5, 0.9), p(-0.5, -1.8), p(0.5, -1.2)], ink, 6)
            ctx.saveGState(); ctx.translateBy(x: p(1.0, 1.7).x, y: p(1.0, 1.7).y); ctx.rotate(by: -0.3)
            ctx.fillEllipse(in: CGRect(x: -0.45 * s, y: -0.33 * s, width: 0.9 * s, height: 0.66 * s)); ctx.restoreGState()
            pen.line([p(1.4, 1.65), p(1.4, 0.1)], ink, 5)
        case .spark:
            let big = star(center: p(-0.4, -0.2), r: 1.6 * s, inner: 0.38, points: 4)
            pen.fill(big, cream); pen.stroke(big, ink, 5)
            ctx.saveGState(); ctx.addPath(big); ctx.clip()
            ctx.setFillColor(ochre.copy(alpha: 0.45)!); ctx.fill(CGRect(x: 0, y: c.y, width: side, height: side))
            ctx.restoreGState()
            let small = star(center: p(1.5, 1.0), r: 0.8 * s, inner: 0.38, points: 4)
            pen.fill(small, ochre); pen.stroke(small, ink, 4)
        case .sweat:
            for (dx, dy, r) in [(CGFloat(-0.6), CGFloat(-0.4), CGFloat(1)), (1.0, 1.0, 0.7)] {
                let drop = CGMutablePath()
                drop.move(to: p(dx, dy - 1.6 * r))
                drop.addQuadCurve(to: p(dx + 0.9 * r, dy + 0.2), control: p(dx + 0.55 * r, dy - 0.6 * r))
                drop.addQuadCurve(to: p(dx - 0.9 * r, dy + 0.2), control: p(dx, dy + 1.5 * r))
                drop.addQuadCurve(to: p(dx, dy - 1.6 * r), control: p(dx - 0.55 * r, dy - 0.6 * r))
                pen.fill(drop, sky); pen.stroke(drop, ink, 4.5)
                pen.line([p(dx - 0.35 * r, dy - 0.1), p(dx - 0.2 * r, dy - 0.6 * r)], cream, 3.5)
            }
        case .stars:
            let st = star(center: c, r: 1.15 * s, inner: 0.45, points: 5)
            pen.fill(st, ochre); pen.stroke(st, ink, 4.5)
        case .zzz:         // three Z's, each smaller and higher
            for (x, y, r, w) in [(CGFloat(-1.3), CGFloat(1.2), CGFloat(0.8), CGFloat(7)),
                                 (0.4, -0.2, 0.6, 6), (1.6, -1.4, 0.42, 5)] {
                pen.line([p(x - r, y - r), p(x + r, y - r), p(x - r, y + r), p(x + r, y + r)], ink, w)
            }
        case .anger:       // the manga vein: four arcs bowing in to the middle
            for (sx, sy) in [(CGFloat(-1), CGFloat(-1)), (1, -1), (1, 1), (-1, 1)] {
                let a = CGMutablePath()
                a.move(to: p(sx * 0.35, sy * 1.75))
                a.addQuadCurve(to: p(sx * 1.75, sy * 0.35), control: p(sx * 0.45, sy * 0.45))
                pen.stroke(a, ink, 13)
                pen.stroke(a, angry, 7)
            }
        case .hearts:
            let h = heart(center: c, r: 1.25 * s)
            pen.fill(h, heartRed); pen.stroke(h, ink, 5)
            ctx.setFillColor(cream.copy(alpha: 0.9)!)
            ctx.fillEllipse(in: CGRect(x: p(-0.75, -0.55).x, y: p(-0.75, -0.55).y, width: 0.45 * s, height: 0.35 * s))
        case .question:
            pen.line([p(-0.9, -1.0), p(-0.5, -1.75), p(0.45, -1.8), p(0.95, -1.05),
                      p(0.3, -0.35), p(0, 0.15), p(0, 0.55)], ink, 10, smooth: true)
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: CGRect(x: p(0, 1.45).x - 0.32 * s, y: p(0, 1.45).y - 0.32 * s,
                                       width: 0.64 * s, height: 0.64 * s))
        }
        let image = ctx.makeImage()
        cache[key] = image
        return image
    }

    /// The emote's picture is this many icon pixels square.
    static let emoteSide: CGFloat = 120

    static func star(center c: CGPoint, r: CGFloat, inner: CGFloat, points n: Int) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<(n * 2) {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(n)
            let q = i % 2 == 1 ? r * inner : r
            let pt = CGPoint(x: c.x + cos(a) * q, y: c.y + sin(a) * q)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}

/// The hand: a context plus a seeded wobble, so a boil frame is the same
/// drawing every run (and every test).
struct Pen {
    let ctx: CGContext
    var rng: SplitMix

    mutating func jit(_ j: CGFloat) -> CGFloat { (CGFloat(rng.unit()) * 2 - 1) * j }

    /// A rectangle traced by hand: edges broken every ~45 px, every point
    /// nudged by up to `jitter`.
    mutating func wobblyRect(_ r: CGRect, jitter: CGFloat) -> CGPath {
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        var pts: [CGPoint] = []
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            let n = max(1, Int((hypot(b.x - a.x, b.y - a.y) / 45).rounded()))
            for k in 0..<n {
                let t = CGFloat(k) / CGFloat(n)
                pts.append(CGPoint(x: a.x + (b.x - a.x) * t + jit(jitter), y: a.y + (b.y - a.y) * t + jit(jitter)))
            }
        }
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        return path
    }

    /// Any closed shape, re-traced through jittered samples of its outline.
    mutating func wobbly(_ shape: CGPath, jitter: CGFloat) -> CGPath {
        var samples: [CGPoint] = []
        shape.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint, .addLineToPoint: samples.append(e.points[0])
            case .addQuadCurveToPoint: samples.append(e.points[1])
            case .addCurveToPoint: samples.append(e.points[2])
            default: break
            }
        }
        // ellipses come back as four curves: densify by flattening instead
        if samples.count < 8 {
            samples = []
            let box = shape.boundingBoxOfPath
            for i in 0..<28 {
                let a = CGFloat(i) / 28 * 2 * .pi
                samples.append(CGPoint(x: box.midX + cos(a) * box.width / 2, y: box.midY + sin(a) * box.height / 2))
            }
        }
        let path = CGMutablePath()
        path.addLines(between: samples.map { CGPoint(x: $0.x + jit(jitter), y: $0.y + jit(jitter)) })
        path.closeSubpath()
        return path
    }

    func fill(_ path: CGPath, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }

    func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// An open ink stroke; `smooth` runs it through a Catmull-Rom curve.
    mutating func line(_ pts: [CGPoint], _ color: CGColor, _ width: CGFloat, smooth: Bool = false) {
        guard pts.count > 1 else { return }
        let jittered = pts.map { CGPoint(x: $0.x + jit(0.8), y: $0.y + jit(0.8)) }
        let path = CGMutablePath()
        path.move(to: jittered[0])
        if smooth, jittered.count > 2 {
            for i in 0..<(jittered.count - 1) {
                let p0 = jittered[max(0, i - 1)], p1 = jittered[i]
                let p2 = jittered[i + 1], p3 = jittered[min(jittered.count - 1, i + 2)]
                path.addCurve(to: p2,
                              control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                              control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
            }
        } else {
            for q in jittered.dropFirst() { path.addLine(to: q) }
        }
        stroke(path, color, width)
    }
}

/// A tiny seeded generator: the wobble of a boil frame must not change from
/// one launch to the next, or the hit-mask tests would test a different drawing.
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
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// How each mood moves, as Core Animation on the mascot's layer — the sheet's
/// `body(t)` per emotion, translated into loops. Everything here is
/// **additive** (on `position` and `transform.rotation.z`), because the same
/// layer is already being slid in, wiggled and thrown about by the whip; an
/// additive loop rides on top of all of that instead of fighting it. The loops
/// repeat forever and need no stop of their own: they die with the layer when
/// the peek leaves (`schedulePeekExit`), or are swapped by the next mood.
enum ClawdMotion {
    static let motionKey = "mood-motion"
    static let swayKey = "mood-sway"
    static let emoteName = "clawd-emote"

    /// `unit` is the sheet's body unit `u` in layer points. y is UP here.
    static func addMotion(_ mood: ClawdMood, to layer: CALayer, unit u: CGFloat) {
        func loop(_ key: String, _ path: String, _ values: [Any], _ duration: Double, ease: Bool = true) {
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values
            a.duration = duration
            a.isAdditive = true
            a.repeatCount = .infinity
            if ease { a.calculationMode = .cubic }
            layer.add(a, forKey: key)
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSValue { NSValue(point: NSPoint(x: x, y: y)) }
        /// `n` samples of one period of `f`, closed.
        func wave(_ n: Int = 12, _ f: (CGFloat) -> NSValue) -> [NSValue] {
            (0...n).map { f(CGFloat($0) / CGFloat(n) * 2 * .pi) }
        }
        switch mood {
        case .happy:     // bouncing on the beat
            loop(motionKey, "position", wave { pt(0, 0.7 * u * abs(sin($0 / 2))) }, 0.5)
        case .excited:   // springy little hops, twice as fast
            loop(motionKey, "position", wave { pt(0, 1.3 * u * abs(sin($0 / 2))) }, 0.36)
        case .cool:      // a laid-back nod
            loop(motionKey, "position", wave { pt(0, -0.25 * u * max(0, sin($0))) }, 0.6)
            loop(swayKey, "transform.rotation.z", wave { NSNumber(value: Double(0.035 * max(0, sin($0)))) }, 0.6)
        case .scared:    // a shiver
            loop(motionKey, "position", [pt(0, 0), pt(0.12 * u, 0), pt(-0.12 * u, 0.04 * u), pt(0, 0)],
                 1.0 / 11, ease: false)
        case .dizzy:     // reeling round in a slow circle
            loop(motionKey, "position", wave(16) { pt(0.7 * u * sin($0), 0.3 * u * abs(cos($0))) }, 1.25)
            loop(swayKey, "transform.rotation.z", wave(16) { NSNumber(value: Double(-0.12 * sin($0))) }, 1.25)
        case .hopeful:   // floating a little, looking up
            loop(motionKey, "position", wave { pt(0, 0.25 * u * (1 - cos($0)) / 2) }, 1.6)
            loop(swayKey, "transform.rotation.z", wave { NSNumber(value: Double(0.03 * sin($0))) }, 3.2)
        case .sleepy:    // slow breathing, nodding off to one side
            loop(motionKey, "position", wave { pt(0, -0.2 * u * (1 - cos($0)) / 2) }, 2.6)
            loop(swayKey, "transform.rotation.z", wave { NSNumber(value: Double(-0.07 * (1 - cos($0)) / 2)) }, 2.6)
        case .grumpy:    // stomping, short and hard
            loop(motionKey, "position", wave { pt(0.05 * u * sin(3 * $0), 0.35 * u * abs(sin($0 / 2))) }, 0.42)
        case .love:      // swaying on a cloud
            loop(motionKey, "position", wave { pt(0, 0.35 * u * (1 - cos($0)) / 2) }, 1.1)
            loop(swayKey, "transform.rotation.z", wave { NSNumber(value: Double(0.06 * sin($0))) }, 2.2)
        case .cheeky:    // a cocky lean, back and forth
            loop(motionKey, "position", wave { pt(0, 0.3 * u * abs(sin($0))) }, 0.8)
            loop(swayKey, "transform.rotation.z", wave { NSNumber(value: Double(-0.07 * sin($0))) }, 0.8)
        case .sneaky:    // tiptoeing side to side
            loop(motionKey, "position", wave(16) { pt(0.45 * u * sin($0), 0.2 * u * abs(sin(2 * $0))) }, 1.5)
        case .curious:   // tilting the head to look closer, and back
            loop(motionKey, "position", wave { pt(0.15 * u * (1 - cos($0)) / 2, 0) }, 2.0)
            loop(swayKey, "transform.rotation.z", wave { NSNumber(value: Double(0.1 * (1 - cos($0)) / 2)) }, 2.0)
        }
    }

    /// The emote by his head. `picture` is where the bare icon lies in the
    /// layer, `scale` icon pixels → points. With the 🎅 hat on the right corner
    /// the corner emotes move to the left one.
    static func addEmote(_ emote: ClawdEmote, to layer: CALayer, picture: CGRect,
                         scale k: CGFloat, leftCorner: Bool) {
        guard let raw = ClawdArt.emotePicture(emote) else { return }
        let image = PeekMascotOutline.outlined(raw, pad: 5) ?? raw
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {   // icon px, y down → layer
            CGPoint(x: picture.minX + x * k, y: picture.maxY - y * k)
        }
        let cornerX: CGFloat = leftCorner ? 10 : ClawdArt.canvas.width - 10
        let box = CALayer()
        box.name = emoteName
        box.frame = layer.bounds
        layer.addSublayer(box)

        func sprite(_ size: CGFloat, at p: CGPoint) -> CALayer {
            let s = CALayer()
            s.contents = image
            s.contentsGravity = .resizeAspect
            s.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2
            s.bounds = CGRect(x: 0, y: 0, width: size * k, height: size * k)
            s.position = p
            box.addSublayer(s)
            return s
        }
        func pop(_ s: CALayer, delay: Double = 0) {
            let a = CAKeyframeAnimation(keyPath: "transform.scale")
            a.values = [0.01, 1.2, 1]
            a.keyTimes = [0, 0.7, 1]
            a.duration = 0.3
            a.beginTime = CACurrentMediaTime() + delay
            a.fillMode = .backwards
            s.add(a, forKey: "pop")
        }
        let side = ClawdArt.emoteSide + 10
        switch emote {
        case .music:
            let s = sprite(side, at: at(cornerX + (leftCorner ? -10 : 10), -45))
            pop(s)
            let bob = CAKeyframeAnimation(keyPath: "position")
            bob.values = (0...12).map { i -> NSValue in
                let a = CGFloat(i) / 12 * 2 * .pi
                return NSValue(point: NSPoint(x: 0, y: 7 * k * sin(a)))
            }
            bob.isAdditive = true
            bob.duration = 1.26
            bob.repeatCount = .infinity
            s.add(bob, forKey: "bob")
            let rock = CABasicAnimation(keyPath: "transform.rotation.z")
            rock.fromValue = -0.12; rock.toValue = 0.12
            rock.duration = 0.63; rock.autoreverses = true; rock.repeatCount = .infinity
            rock.isAdditive = true
            s.add(rock, forKey: "rock")
        case .spark:
            let s = sprite(side, at: at(cornerX + (leftCorner ? -15 : 15), -40))
            pop(s)
            let tw = CABasicAnimation(keyPath: "transform.rotation.z")
            tw.fromValue = -0.15; tw.toValue = 0.15
            tw.duration = 0.26; tw.autoreverses = true; tw.repeatCount = .infinity
            tw.isAdditive = true
            s.add(tw, forKey: "twinkle")
        case .sweat:
            let s = sprite(side * 0.9, at: at(cornerX + (leftCorner ? -5 : 5), 5))
            pop(s)
            let drip = CAKeyframeAnimation(keyPath: "position")
            drip.values = [NSValue(point: .zero), NSValue(point: NSPoint(x: 0, y: -14 * k)), NSValue(point: .zero)]
            drip.keyTimes = [0, 0.85, 1]
            drip.isAdditive = true
            drip.duration = 0.9
            drip.repeatCount = .infinity
            s.add(drip, forKey: "drip")
        case .stars:     // three little stars circling over his head
            let centre = at(ClawdArt.canvas.width / 2, -40)
            let orbit = CGPath(ellipseIn: CGRect(x: centre.x - 190 * k, y: centre.y - 26 * k,
                                                 width: 380 * k, height: 52 * k), transform: nil)
            for i in 0..<3 {
                let s = sprite(side * 0.55, at: centre)
                pop(s, delay: Double(i) * 0.08)
                let go = CAKeyframeAnimation(keyPath: "position")
                go.path = orbit
                go.calculationMode = .paced
                go.duration = 1.26
                go.repeatCount = .infinity
                go.timeOffset = 1.26 * Double(i) / 3
                s.add(go, forKey: "orbit")
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0; spin.toValue = 2 * Double.pi
                spin.duration = 2.1; spin.repeatCount = .infinity
                spin.isAdditive = true
                s.add(spin, forKey: "spin")
            }
        case .zzz:       // drifting up and away, again and again
            let s = sprite(side, at: at(cornerX + (leftCorner ? -10 : 10), -35))
            pop(s)
            let rise = CAKeyframeAnimation(keyPath: "position")
            rise.values = [NSValue(point: .zero), NSValue(point: NSPoint(x: 12 * k, y: 30 * k))]
            rise.isAdditive = true
            rise.duration = 1.8
            rise.repeatCount = .infinity
            s.add(rise, forKey: "rise")
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.6, 1]
            fade.duration = 1.8
            fade.repeatCount = .infinity
            s.add(fade, forKey: "fade")
        case .anger:     // throbbing
            let s = sprite(side * 0.85, at: at(cornerX + (leftCorner ? 5 : -5), -25))
            pop(s)
            let throb = CABasicAnimation(keyPath: "transform.scale")
            throb.fromValue = 1; throb.toValue = 1.25
            throb.duration = 0.22; throb.autoreverses = true; throb.repeatCount = .infinity
            throb.beginTime = CACurrentMediaTime() + 0.3
            s.add(throb, forKey: "throb")
        case .hearts:    // three hearts rising off his head, one after the other
            for i in 0..<3 {
                let x = ClawdArt.canvas.width * (0.25 + 0.25 * CGFloat(i))
                let s = sprite(side * 0.55, at: at(x, -10))
                s.opacity = 0
                let rise = CAKeyframeAnimation(keyPath: "position")
                rise.values = (0...8).map { j -> NSValue in
                    let t = CGFloat(j) / 8
                    return NSValue(point: NSPoint(x: 12 * k * sin(t * 2 * .pi), y: 110 * k * t))
                }
                rise.isAdditive = true
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 1, 1, 0]
                fade.keyTimes = [0, 0.15, 0.65, 1]
                let group = CAAnimationGroup()
                group.animations = [rise, fade]
                group.duration = 1.5
                group.repeatCount = .infinity
                group.beginTime = CACurrentMediaTime() + Double(i) * 0.5
                s.add(group, forKey: "float")
            }
        case .question:  // bobbing and rocking, like the notes
            let s = sprite(side, at: at(cornerX + (leftCorner ? -10 : 10), -45))
            pop(s)
            let rock = CABasicAnimation(keyPath: "transform.rotation.z")
            rock.fromValue = -0.18; rock.toValue = 0.18
            rock.duration = 0.7; rock.autoreverses = true; rock.repeatCount = .infinity
            rock.isAdditive = true
            s.add(rock, forKey: "rock")
        }
    }
}
