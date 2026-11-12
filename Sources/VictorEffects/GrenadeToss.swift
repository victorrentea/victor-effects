import AppKit
import QuartzCore

/// 💣 Tile #87 "Fire in the hole!": a pineapple grenade is lobbed in from the
/// bottom-left corner, tumbles through an arc, bounces twice, rattles, and
/// blows up in the middle of the screen.
///
/// The clip (`87_grenade.mp3`, 1.51 s) is only the shout — the words run from
/// 0.22 s to ~1.2 s and there is no blast in it — so the timeline is fitted to
/// the voice: the grenade is in the air while "fire in the hole" is being said,
/// lands on "hole", and goes off a quarter of a second after the shout ends.
/// The boom is borrowed from `03_explosion.mp3`, seeked straight to its blast
/// (`EmojiAnimator.explosionBlastOnset`), so it lands on the fireball's first
/// frame instead of a whistle later.
///
/// Everything here is drawn in code — the grenade, the fireball, the smoke —
/// so the effect needs no asset and is publishable as is. The nuke's
/// `explosion.gif` was the obvious thing to reuse and the wrong one: it is a
/// mushroom cloud, which reads as tile #3, not as a hand grenade.
///
/// Pure where it can be: the grenade's pose at any instant is a function of
/// time and screen (`pose(at:in:)`), sampled into keyframes the window server
/// runs on its own, so nothing ticks on the main thread while it flies.
enum GrenadeToss {

    // MARK: Timeline (seconds from the press)

    /// From the corner to the first touchdown.
    static let flight: Double = 0.80
    /// End of the first (bigger) bounce.
    static let bounce1End: Double = 1.02
    /// End of the second bounce: the grenade lies still from here.
    static let bounce2End: Double = 1.16
    /// It starts to rattle — the fuse is about to go.
    static let rattleStart: Double = 1.20
    /// The blast. A quarter of a second after the shout's last word, so the
    /// room hears the warning end before the bang, not over it.
    static let blastAt: Double = 1.45
    /// How long the blast's own layers live (the smoke is the slowest).
    static let blastDuration: Double = 2.4
    /// When everything is gone. `trackEffect` removes the container here.
    static let totalDuration: Double = blastAt + blastDuration

    // MARK: Geometry (fractions of the screen)

    /// Grenade height at rest, as a fraction of the screen's shorter side.
    static let restHeightFraction: CGFloat = 0.12
    /// How much bigger it is as it leaves the corner — it is thrown from near
    /// the viewer INTO the screen, so it shrinks as it flies away.
    static let startScale: CGFloat = 2.2
    /// Height of the throw's arc above the straight corner→landing line.
    static let arcHeightFraction: CGFloat = 0.35
    /// The two bounces, as fractions of the screen height.
    static let bounce1HeightFraction: CGFloat = 0.07
    static let bounce2HeightFraction: CGFloat = 0.025
    /// Where it first touches down, left of where it comes to rest — the
    /// bounces carry it the rest of the way to the centre.
    static let land1OffsetFraction: CGFloat = 0.09
    static let land2OffsetFraction: CGFloat = 0.03
    /// Fireball diameter, as a fraction of the screen's shorter side.
    static let blastDiameterFraction: CGFloat = 0.75

    /// Turns it tumbles through, clockwise (it flies to the right). The total,
    /// 4¼ turns, leaves it lying on its side with the fuse to the right.
    static let flightTurns: Double = 3.3
    static let bounce1Turns: Double = 0.6
    static let bounce2Turns: Double = 0.35

    /// The rattle before the blast: angle amplitude (radians) and frequency.
    static let rattleAmplitude: Double = 0.10
    static let rattleHz: Double = 14

    /// The middle of the screen: where it rests and where it explodes.
    static func restPoint(in b: CGRect) -> CGPoint { CGPoint(x: b.midX, y: b.midY) }

    /// On the bottom-left corner, just outside it: at `startScale` the grenade
    /// already overlaps the corner on the first frame, so the room sees it come
    /// IN from there rather than appear on the left edge.
    static func startPoint(in b: CGRect) -> CGPoint {
        CGPoint(x: b.minX - 0.02 * b.width, y: b.minY - 0.04 * b.height)
    }

    static func restHeight(in b: CGRect) -> CGFloat { min(b.width, b.height) * restHeightFraction }

    struct Pose: Equatable {
        var position: CGPoint
        /// Radians, y-up (negative = clockwise).
        var angle: Double
        var scale: CGFloat
    }

    /// Where the grenade is, how it is turned and how big it is, `t` seconds
    /// after the press. Clamped: before 0 it is at the corner, after the blast
    /// it stays where it went off.
    static func pose(at t: Double, in b: CGRect) -> Pose {
        let start = startPoint(in: b), rest = restPoint(in: b)
        let land1 = CGPoint(x: rest.x - land1OffsetFraction * b.width, y: rest.y)
        let land2 = CGPoint(x: rest.x - land2OffsetFraction * b.width, y: rest.y)
        let turn = -2 * Double.pi
        let t = max(0, min(t, blastAt))

        func lerp(_ a: CGFloat, _ b: CGFloat, _ u: CGFloat) -> CGFloat { a + (b - a) * u }
        func hop(_ s: CGFloat) -> CGFloat { 4 * s * (1 - s) }

        if t < flight {
            let s = CGFloat(t / flight)
            // Eased: fast out of the hand, slowing as it travels away — gently,
            // or the corner is crossed in a frame and never seen.
            let u = 1 - pow(1 - s, 1.2)
            let x = lerp(start.x, land1.x, u)
            let y = lerp(start.y, land1.y, u) + arcHeightFraction * b.height * hop(u)
            return Pose(position: CGPoint(x: x, y: y),
                        angle: turn * flightTurns * Double(s),
                        scale: lerp(startScale, 1, u))
        }
        if t < bounce1End {
            let s = CGFloat((t - flight) / (bounce1End - flight))
            return Pose(position: CGPoint(x: lerp(land1.x, land2.x, s),
                                          y: rest.y + bounce1HeightFraction * b.height * hop(s)),
                        angle: turn * (flightTurns + bounce1Turns * Double(s)),
                        scale: 1)
        }
        if t < bounce2End {
            let s = CGFloat((t - bounce1End) / (bounce2End - bounce1End))
            return Pose(position: CGPoint(x: lerp(land2.x, rest.x, s),
                                          y: rest.y + bounce2HeightFraction * b.height * hop(s)),
                        angle: turn * (flightTurns + bounce1Turns + bounce2Turns * Double(s)),
                        scale: 1)
        }
        let lying = turn * (flightTurns + bounce1Turns + bounce2Turns)
        guard t >= rattleStart else { return Pose(position: rest, angle: lying, scale: 1) }
        let r = t - rattleStart
        // Grows into the blast: a twitch at first, a frantic shake by the end.
        let grow = min(1, r / (blastAt - rattleStart))
        return Pose(position: CGPoint(x: rest.x + CGFloat(2 * grow * sin(2 * .pi * 23 * r)), y: rest.y),
                    angle: lying + rattleAmplitude * grow * sin(2 * .pi * rattleHz * r),
                    scale: 1)
    }

    /// The flight as three keyframe animations (position, rotation, scale),
    /// sampled at 60 fps up to the blast.
    static func flightAnimations(in b: CGRect) -> [String: CAKeyframeAnimation] {
        let fps = 60.0
        let n = Int((blastAt * fps).rounded())
        let poses = (0...n).map { pose(at: Double($0) / fps, in: b) }
        func track(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.values = values
            a.duration = blastAt
            a.calculationMode = .linear
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            return a
        }
        return [
            "position": track("position", poses.map { NSValue(point: $0.position) }),
            "transform.rotation.z": track("transform.rotation.z", poses.map { $0.angle }),
            "transform.scale": track("transform.scale", poses.map { $0.scale }),
        ]
    }

    // MARK: The grenade

    /// Sprite aspect, width / height (body + fuse + ring sticking out).
    static let spriteAspect: CGFloat = 0.78

    /// A Mk 2 "pineapple": olive segmented body, dark fuse, the spoon down its
    /// right side, the ring on the left. Drawn once per size.
    static func grenadeImage(height: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "\(Int(height))@\(scale)"
        if let hit = grenadeCache[key] { return hit }
        let w = height * spriteAspect, h = height
        let pw = Int(ceil(w * scale)), ph = Int(ceil(h * scale))
        guard pw > 0, ph > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: EmojiAnimator.nativeBitmapInfo) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setLineCap(.round)

        // Body: an egg in the lower 78 %, centred a little right to leave room for the ring.
        let bodyW = w * 0.74, bodyH = h * 0.74
        let body = CGRect(x: w * 0.2, y: h * 0.02, width: bodyW, height: bodyH)
        let space = CGColorSpaceCreateDeviceRGB()
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(red: r, green: g, blue: b, alpha: a)
        }

        // Fuse (behind the spoon, above the body).
        let fuse = CGRect(x: body.midX - bodyW * 0.17, y: body.maxY - bodyH * 0.06,
                          width: bodyW * 0.34, height: h * 0.15)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: fuse, cornerWidth: bodyW * 0.04, cornerHeight: bodyW * 0.04, transform: nil))
        ctx.clip()
        if let g = CGGradient(colorsSpace: space,
                              colors: [rgb(0.22, 0.23, 0.22), rgb(0.55, 0.56, 0.53), rgb(0.18, 0.19, 0.18)] as CFArray,
                              locations: [0, 0.4, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: fuse.minX, y: 0), end: CGPoint(x: fuse.maxX, y: 0), options: [])
        }
        ctx.restoreGState()

        // Body with its pineapple grid.
        ctx.saveGState()
        ctx.addEllipse(in: body)
        ctx.clip()
        if let g = CGGradient(colorsSpace: space,
                              colors: [rgb(0.55, 0.62, 0.30), rgb(0.33, 0.39, 0.16), rgb(0.16, 0.19, 0.07)] as CFArray,
                              locations: [0, 0.55, 1]) {
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: body.minX + bodyW * 0.35, y: body.minY + bodyH * 0.68),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: body.midX, y: body.midY),
                                   endRadius: bodyW * 0.62, options: [.drawsAfterEndLocation])
        }
        ctx.setStrokeColor(rgb(0.10, 0.12, 0.04, 0.85))
        ctx.setLineWidth(max(1, bodyW * 0.045))
        for i in 1...5 {   // horizontal grooves
            let y = body.minY + bodyH * CGFloat(i) / 6
            ctx.move(to: CGPoint(x: body.minX, y: y)); ctx.addLine(to: CGPoint(x: body.maxX, y: y))
        }
        ctx.strokePath()
        for f in [0.0, 0.38, 0.72] as [CGFloat] {   // vertical grooves: ellipses of shrinking width
            let gw = bodyW * f
            ctx.strokeEllipse(in: CGRect(x: body.midX - gw / 2, y: body.minY - 2, width: max(1, gw), height: bodyH + 4))
        }
        // A highlight on the upper-left, where the light hits.
        ctx.setFillColor(rgb(1, 1, 0.85, 0.22))
        ctx.fillEllipse(in: CGRect(x: body.minX + bodyW * 0.16, y: body.minY + bodyH * 0.55,
                                   width: bodyW * 0.22, height: bodyH * 0.26))
        ctx.restoreGState()
        ctx.setStrokeColor(rgb(0.08, 0.10, 0.03))
        ctx.setLineWidth(max(1, bodyW * 0.03))
        ctx.strokeEllipse(in: body)

        // The spoon: from the top of the fuse, out and down the right flank.
        let spoon = CGMutablePath()
        spoon.move(to: CGPoint(x: fuse.minX + fuse.width * 0.3, y: fuse.maxY))
        spoon.addLine(to: CGPoint(x: fuse.maxX + bodyW * 0.05, y: fuse.maxY - h * 0.01))
        spoon.addCurve(to: CGPoint(x: body.maxX + bodyW * 0.04, y: body.minY + bodyH * 0.42),
                       control1: CGPoint(x: body.maxX + bodyW * 0.08, y: fuse.maxY - h * 0.02),
                       control2: CGPoint(x: body.maxX + bodyW * 0.1, y: body.midY + bodyH * 0.2))
        ctx.addPath(spoon)
        ctx.setStrokeColor(rgb(0.12, 0.13, 0.12))
        ctx.setLineWidth(bodyW * 0.13)
        ctx.strokePath()
        ctx.addPath(spoon)
        ctx.setStrokeColor(rgb(0.62, 0.63, 0.6))
        ctx.setLineWidth(bodyW * 0.08)
        ctx.strokePath()

        // The ring, hanging off the left of the fuse.
        let ringR = bodyW * 0.16
        let ringC = CGPoint(x: fuse.minX - ringR * 0.85, y: fuse.midY + h * 0.005)
        let ring = CGRect(x: ringC.x - ringR, y: ringC.y - ringR, width: 2 * ringR, height: 2 * ringR)
        ctx.setStrokeColor(rgb(0.15, 0.15, 0.15))
        ctx.setLineWidth(bodyW * 0.075)
        ctx.strokeEllipse(in: ring)
        ctx.setStrokeColor(rgb(0.82, 0.82, 0.78))
        ctx.setLineWidth(bodyW * 0.04)
        ctx.strokeEllipse(in: ring)

        let img = ctx.makeImage()
        grenadeCache[key] = img
        return img
    }
    private static var grenadeCache: [String: CGImage] = [:]

    // MARK: The blast

    /// A soft disc that fades from `colors[0]` in the middle to clear at the
    /// rim — the one picture every puff of fire and smoke is made of. Soft, so
    /// drawn at 1× (`docs/overlay-effects.md`, *what a full-screen effect may
    /// cost*), and cached by name.
    static func softDisc(_ name: String, colors: [CGColor], locations: [CGFloat], size: Int = 256) -> CGImage? {
        if let hit = discCache[name] { return hit }
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: EmojiAnimator.nativeBitmapInfo),
              let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors as CFArray, locations: locations) else { return nil }
        let c = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        let img = ctx.makeImage()
        discCache[name] = img
        return img
    }
    private static var discCache: [String: CGImage] = [:]

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    static var fireDisc: CGImage? {
        softDisc("fire", colors: [rgba(1, 1, 0.9, 1), rgba(1, 0.85, 0.3, 1), rgba(1, 0.45, 0.05, 0.9),
                                  rgba(0.75, 0.12, 0.02, 0.5), rgba(0.5, 0.05, 0, 0)],
                 locations: [0, 0.2, 0.5, 0.78, 1])
    }
    static var smokeDisc: CGImage? {
        softDisc("smoke", colors: [rgba(0.22, 0.2, 0.19, 0.85), rgba(0.3, 0.28, 0.27, 0.55), rgba(0.35, 0.33, 0.32, 0)],
                 locations: [0, 0.55, 1])
    }
    static var scorchDisc: CGImage? {
        softDisc("scorch", colors: [rgba(0.05, 0.03, 0.02, 0.9), rgba(0.1, 0.06, 0.03, 0.6), rgba(0.15, 0.1, 0.05, 0)],
                 locations: [0, 0.5, 1])
    }
    /// Hot core with an orange rim, NOT additive: added light vanishes on a
    /// white slide, and most of what this lands on is a white slide.
    static var sparkDot: CGImage? {
        softDisc("spark", colors: [rgba(1, 0.97, 0.7, 1), rgba(1, 0.6, 0.05, 1), rgba(0.9, 0.3, 0, 0)],
                 locations: [0, 0.45, 1], size: 32)
    }
    static var debrisChip: CGImage? {
        if let hit = discCache["debris"] { return hit }
        let s = 16
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: EmojiAnimator.nativeBitmapInfo) else { return nil }
        let chip = CGMutablePath()
        chip.addLines(between: [CGPoint(x: 2, y: 3), CGPoint(x: 13, y: 1), CGPoint(x: 15, y: 10),
                                CGPoint(x: 7, y: 15), CGPoint(x: 1, y: 11)])
        chip.closeSubpath()
        ctx.addPath(chip)
        ctx.setFillColor(rgba(0.2, 0.22, 0.12, 1))
        ctx.fillPath()
        let img = ctx.makeImage()
        discCache["debris"] = img
        return img
    }

    /// Seeded so the same press looks the same in a recording, varied so the
    /// puffs are not a ring of identical circles.
    struct Rand {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 33) / CGFloat(1 << 31)
        }
        mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo + (hi - lo) * next() }
    }

    /// Build the whole blast at `center`, every animation un-begun so they all
    /// start in the caller's transaction on one clock. `bounds` is the full
    /// overlay (for the flash). Returns the container; it does not remove
    /// itself — the effect's `trackEffect` does.
    static func makeBlast(at center: CGPoint, in bounds: CGRect, seed: UInt64 = 87) -> CALayer {
        let container = CALayer()
        container.frame = bounds
        let d = min(bounds.width, bounds.height) * blastDiameterFraction
        var rnd = Rand(state: seed)

        func layer(_ image: CGImage?, size: CGSize, at p: CGPoint) -> CALayer {
            let l = CALayer()
            l.contents = image
            l.bounds = CGRect(origin: .zero, size: size)
            l.position = p
            l.opacity = 0
            container.addSublayer(l)
            return l
        }
        func keys(_ path: String, _ values: [Any], _ times: [NSNumber], _ dur: Double,
                  ease: CAMediaTimingFunctionName = .easeOut) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values
            a.keyTimes = times
            a.duration = dur
            a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: ease), count: max(1, values.count - 1))
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            return a
        }

        // Scorch on the floor, under everything — what is left when the smoke clears.
        let scorch = layer(scorchDisc, size: CGSize(width: d * 0.75, height: d * 0.32),
                           at: CGPoint(x: center.x, y: center.y - d * 0.06))
        scorch.add(keys("opacity", [0, 0.75, 0.75, 0], [0, 0.1, 0.6, 1], blastDuration), forKey: "o")

        // Smoke: rises out of the fire as it dies, grows and thins.
        for i in 0..<9 {
            let p = CGPoint(x: center.x + rnd.range(-0.22, 0.22) * d, y: center.y + rnd.range(-0.08, 0.15) * d)
            let s = d * rnd.range(0.35, 0.55)
            let l = layer(smokeDisc, size: CGSize(width: s, height: s), at: p)
            let lift = d * rnd.range(0.25, 0.5)
            let dur = blastDuration * Double(rnd.range(0.8, 1))
            let delay = 0.12 + 0.02 * Double(i % 3)
            let f = NSNumber(value: delay / dur)
            l.add(keys("opacity", [0, 0, 0.8, 0.6, 0], [0, f, NSNumber(value: (delay + 0.25) / dur), 0.6, 1], dur), forKey: "o")
            l.add(keys("transform.scale", [0.3, 0.3, 1.7], [0, f, 1], dur), forKey: "s")
            l.add(keys("position", [NSValue(point: p), NSValue(point: p),
                                    NSValue(point: CGPoint(x: p.x + rnd.range(-0.1, 0.1) * d, y: p.y + lift))],
                       [0, f, 1], dur), forKey: "p")
        }

        // Fireball: a cluster of hot puffs blooming out from the grenade.
        for i in 0..<10 {
            let off = i == 0 ? CGPoint.zero : CGPoint(x: rnd.range(-0.26, 0.26) * d, y: rnd.range(-0.1, 0.28) * d)
            let s = d * (i == 0 ? 0.8 : rnd.range(0.38, 0.62))
            let l = layer(fireDisc, size: CGSize(width: s, height: s),
                          at: CGPoint(x: center.x + off.x, y: center.y + off.y))
            let dur = Double(rnd.range(0.7, 0.95))
            l.add(keys("transform.scale", [0.05, 1, 1.18], [0, 0.28, 1], dur), forKey: "s")
            l.add(keys("opacity", [1, 1, 0], [0, 0.4, 1], dur, ease: .easeIn), forKey: "o")
        }

        // Shockwave: one thin bright ring racing out past the fire.
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        ring.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: d, height: d), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = rgba(1, 0.95, 0.85, 1)
        ring.lineWidth = 3
        ring.opacity = 0
        container.addSublayer(ring)
        ring.add(keys("transform.scale", [0.1, 1.9], [0, 1], 0.5), forKey: "s")
        ring.add(keys("opacity", [0.9, 0], [0, 1], 0.5, ease: .easeIn), forKey: "o")

        // White-hot core: the first frame of the blast is a flash, not a ball.
        let core = layer(fireDisc, size: CGSize(width: d * 0.5, height: d * 0.5), at: center)
        core.add(keys("transform.scale", [0.2, 1.6, 1.8], [0, 0.35, 1], 0.3), forKey: "s")
        core.add(keys("opacity", [1, 1, 0], [0, 0.3, 1], 0.3, ease: .easeIn), forKey: "o")

        // Sparks and shrapnel: one burst from the grenade, falling back under gravity.
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterPosition = center
        emitter.emitterShape = .point
        let spark = CAEmitterCell()
        spark.contents = sparkDot
        spark.birthRate = 2500
        spark.lifetime = 0.8
        spark.lifetimeRange = 0.35
        spark.velocity = d * 1.6
        spark.velocityRange = d * 0.9
        spark.emissionRange = 2 * .pi
        spark.yAcceleration = -d * 1.6
        spark.scale = 0.45
        spark.scaleRange = 0.25
        spark.scaleSpeed = -0.35
        spark.alphaSpeed = -1.1
        let chips = CAEmitterLayer()
        chips.frame = bounds
        chips.emitterPosition = center
        chips.emitterShape = .point
        let chip = CAEmitterCell()
        chip.contents = debrisChip
        chip.birthRate = 500
        chip.lifetime = 1.1
        chip.lifetimeRange = 0.3
        chip.velocity = d * 1.2
        chip.velocityRange = d * 0.6
        chip.emissionRange = 2 * .pi
        chip.yAcceleration = -d * 2.2
        chip.spin = 8
        chip.spinRange = 12
        chip.scale = 1.3
        chip.scaleRange = 0.6
        chip.alphaSpeed = -0.6
        emitter.emitterCells = [spark]
        chips.emitterCells = [chip]
        container.addSublayer(chips)
        container.addSublayer(emitter)
        // One burst: on for a few frames, then the emitters go quiet. Animated
        // rather than timed from the main thread, so it cannot over-run a stall.
        for e in [emitter, chips] {
            e.birthRate = 0
            e.add(keys("birthRate", [1, 1, 0], [0, 0.99, 1], 0.06, ease: .linear), forKey: "burst")
        }

        // The flash over the whole screen, warm and brief.
        let flash = CALayer()
        flash.frame = bounds
        flash.backgroundColor = rgba(1, 0.93, 0.75, 1)
        flash.opacity = 0
        container.addSublayer(flash)
        flash.add(keys("opacity", [0.55, 0], [0, 1], 0.3, ease: .easeIn), forKey: "o")

        return container
    }
}
