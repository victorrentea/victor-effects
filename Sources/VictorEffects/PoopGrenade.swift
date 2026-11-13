import AppKit
import QuartzCore

/// 💩 Tile 87b (layer B under the 💣 grenade, 2026-11-13): the same grenade,
/// the same throw, blast and broken glass, but it was full of shit. On the
/// blast the shit goes everywhere — brown splats slapped onto the glass all
/// over the screen, some of them running down it, a burst of 💩 tumbling out
/// under gravity — and a big 💩 is left sitting in the black hole where it went
/// off, steaming, until the broken glass fades.
///
/// Every animation is un-begun, as `makeCrack`'s are: the caller adds the layer
/// in the blast's own transaction, so the splatter shares its clock and its
/// shake. It goes OVER the glass — the shit is on the screen's surface, in
/// front of everything.
extension GrenadeToss {

    /// Splats slapped onto the glass, near and far from the hole.
    static let poopSplats = 22
    /// 💩 thrown out of the blast, falling back under gravity.
    static let poopFlyers = 26
    /// How long a splat takes to fly from the blast to where it sticks.
    static let splatFlightRange: ClosedRange<Double> = 0.10...0.30
    /// The big 💩 rises out of the hole this long after the blast — once the
    /// white-hot core has gone, so it is seen arriving, not hidden in the flash.
    static let poopSitAt: Double = 0.30
    static let poopSitGrow: Double = 0.45
    /// The big 💩, as a fraction of the hole's radius (capped by the screen).
    static let poopSitFraction: CGFloat = 0.85

    /// The whole splatter, at `c` (the blast), its life ending with the crack's.
    static func makePoopSplatter(at c: CGPoint, holeRadius rh: CGFloat, in bounds: CGRect,
                                 scale: CGFloat, seed: UInt64) -> CALayer {
        let container = CALayer()
        container.frame = bounds
        var rnd = Rand(state: seed ^ 0x9009)
        let side = min(bounds.width, bounds.height)
        let total = crackHold + crackFade

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

        // 1. The splats, flung out of the blast and stuck to the glass. Half land
        //    round the hole, half anywhere on the screen — "all around".
        for i in 0..<poopSplats {
            let near = i % 2 == 0
            let a = rnd.range(0, 2 * .pi)
            let dist = near ? rh * rnd.range(0.55, 1.5) : rh * rnd.range(1.3, 4)
            var p = CGPoint(x: c.x + cos(a) * dist, y: c.y + sin(a) * dist)
            p.x = min(max(p.x, bounds.minX + side * 0.03), bounds.maxX - side * 0.03)
            p.y = min(max(p.y, bounds.minY + side * 0.03), bounds.maxY - side * 0.03)
            let s = side * (near ? rnd.range(0.07, 0.14) : rnd.range(0.04, 0.10))
            let splatSeed = UInt64(i) &+ seed
            guard let image = splatImage(size: s, scale: scale, seed: splatSeed) else { continue }
            let l = CALayer()
            l.contents = image
            l.contentsScale = scale
            l.bounds = CGRect(x: 0, y: 0, width: s * splatBoxRatio, height: s * splatBoxRatio)
            l.position = p
            l.opacity = 0
            container.addSublayer(l)

            let fly = Double(rnd.range(CGFloat(splatFlightRange.lowerBound), CGFloat(splatFlightRange.upperBound)))
                * Double(0.6 + 0.4 * min(1, dist / (rh * 3)))
            let f = NSNumber(value: fly / total)
            l.add(keys("position", [NSValue(point: c), NSValue(point: p), NSValue(point: p)], [0, f, 1], total,
                       ease: .easeOut), forKey: "fly")
            // Small in the air, then the slap: over-wide for a frame, settling.
            let slap = NSNumber(value: (fly + 0.08) / total)
            l.add(keys("transform.scale", [0.2, 1.25, 1.0, 1.0], [0, f, slap, 1], total), forKey: "slap")
            l.add(keys("opacity", [1, 1], [0, 1], total, ease: .linear), forKey: "o")

            // One in three runs down the glass: a drip growing from under it.
            if i % 3 == 0 {
                let w = s * rnd.range(0.12, 0.2)
                let len = s * rnd.range(0.9, 2.2)
                let drip = CAShapeLayer()
                drip.bounds = CGRect(x: 0, y: 0, width: w, height: len)
                drip.anchorPoint = CGPoint(x: 0.5, y: 1)   // grows DOWN from the splat
                drip.position = CGPoint(x: p.x + rnd.range(-0.2, 0.2) * s, y: p.y)
                let path = CGMutablePath()
                path.addRoundedRect(in: CGRect(x: 0, y: w * 0.5, width: w, height: len - w * 0.5),
                                    cornerWidth: w / 2, cornerHeight: w / 2)
                path.addEllipse(in: CGRect(x: -w * 0.15, y: 0, width: w * 1.3, height: w * 1.3))
                drip.path = path
                drip.fillColor = poopColor(rnd.range(0, 1))
                drip.opacity = 0
                container.insertSublayer(drip, below: l)
                let start = NSNumber(value: (fly + 0.12) / total)
                drip.add(keys("transform.scale.y", [0.0, 0.0, 1.0], [0, start, NSNumber(value: min(0.8, (fly + 2.0) / total))],
                              total, ease: .easeOut), forKey: "run")
                drip.add(keys("opacity", [0, 0, 1, 1], [0, start, NSNumber(value: (fly + 0.13) / total), 1], total,
                              ease: .linear), forKey: "o")
            }
        }

        // 2. The 💩 thrown out of it, the shards' way: away from the blast and a
        //    little up, then down under gravity, tumbling, coming at the viewer.
        let fps = 30.0
        let flight = shardFlight * 1.1
        let steps = Int(flight * fps)
        for _ in 0..<poopFlyers {
            let s = side * rnd.range(0.05, 0.10)
            guard let image = poopEmojiImage(size: s, scale: scale) else { continue }
            let a = rnd.range(0, 2 * .pi)
            let speed = side * rnd.range(0.8, 2.0)
            let v = CGVector(dx: cos(a) * speed, dy: sin(a) * speed + side * rnd.range(0.2, 0.7))
            let l = CALayer()
            l.contents = image
            l.contentsScale = scale
            l.bounds = CGRect(x: 0, y: 0, width: s, height: s)
            l.position = c
            l.opacity = 0
            container.addSublayer(l)
            let pos = CAKeyframeAnimation(keyPath: "position")
            pos.values = (0...steps).map { NSValue(point: shardPosition(from: c, velocity: v, at: Double($0) / fps)) }
            pos.duration = flight
            pos.calculationMode = .linear
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = rnd.range(-12, 12)
            spin.duration = flight
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.4
            grow.toValue = rnd.range(1.2, 2.0)
            grow.duration = flight
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.75, 1]
            fade.duration = flight
            for anim in [pos, spin, grow, fade] as [CAAnimation] {
                anim.fillMode = .forwards
                anim.isRemovedOnCompletion = false
            }
            l.add(pos, forKey: "fly"); l.add(spin, forKey: "spin")
            l.add(grow, forKey: "grow"); l.add(fade, forKey: "fade")
        }

        // 3. What is left in the dark: a big 💩 sitting in the hole, on a puddle
        //    of itself, rising out of it with a wobble, then steaming.
        let big = min(rh * poopSitFraction * 2, side * 0.42)
        let seat = CGPoint(x: c.x, y: c.y - big * 0.08)
        if let puddle = splatImage(size: big * 1.1, scale: scale, seed: seed ^ 0xbeef) {
            let l = CALayer()
            l.contents = puddle
            l.contentsScale = scale
            l.bounds = CGRect(x: 0, y: 0, width: big * 1.1 * splatBoxRatio, height: big * 0.45 * splatBoxRatio)
            l.position = CGPoint(x: seat.x, y: seat.y - big * 0.36)
            l.opacity = 0
            container.addSublayer(l)
            let f = NSNumber(value: 0.12 / total)
            l.add(keys("transform.scale", [0.1, 1.15, 1], [0, f, NSNumber(value: 0.2 / total)], total), forKey: "slap")
            l.add(keys("opacity", [1, 1], [0, 1], total, ease: .linear), forKey: "o")
        }
        if let image = poopEmojiImage(size: big, scale: scale) {
            let l = CALayer()
            l.contents = image
            l.contentsScale = scale
            l.bounds = CGRect(x: 0, y: 0, width: big, height: big)
            l.anchorPoint = CGPoint(x: 0.5, y: 0.1)   // it sits: it grows up from its base
            l.position = CGPoint(x: seat.x, y: seat.y - big * 0.4)
            l.opacity = 0
            container.addSublayer(l)
            let t0 = poopSitAt / total, t1 = (poopSitAt + poopSitGrow) / total
            let mid = (poopSitAt + poopSitGrow * 0.6) / total
            let n = { (x: Double) in NSNumber(value: x) }
            l.add(keys("transform.scale", [0.0, 0.0, 1.2, 0.92, 1.0, 1.0],
                       [0, n(t0), n(mid), n(t1 * 0.97 + mid * 0.03), n(t1), 1], total), forKey: "rise")
            l.add(keys("opacity", [0, 0, 1, 1], [0, n(t0), n(t0 + 0.01), 1], total, ease: .linear), forKey: "o")
            l.add(keys("transform.rotation.z", [0, 0, 0.12, -0.08, 0.04, 0, 0],
                       [0, n(t0), n(mid), n(t1 * 0.9 + mid * 0.1), n(t1), n(min(0.99, t1 + 0.1)), 1], total),
                  forKey: "wobble")

            // Stink: three green wavy lines rising off it, again and again.
            for k in 0..<3 {
                let w = big * 0.09, hgt = big * 0.42
                let wave = CGMutablePath()
                wave.move(to: CGPoint(x: w / 2, y: 0))
                for j in 1...12 {
                    let y = hgt * CGFloat(j) / 12
                    wave.addLine(to: CGPoint(x: w / 2 + sin(CGFloat(j) * 1.3) * w / 2, y: y))
                }
                let stink = CAShapeLayer()
                stink.bounds = CGRect(x: 0, y: 0, width: w, height: hgt)
                stink.path = wave
                stink.fillColor = nil
                stink.strokeColor = CGColor(red: 0.45, green: 0.75, blue: 0.2, alpha: 0.9)
                stink.lineWidth = max(2, big * 0.022)
                stink.lineCap = .round
                let base = CGPoint(x: seat.x + (CGFloat(k) - 1) * big * 0.28, y: seat.y + big * 0.55)
                stink.position = base
                stink.opacity = 0
                container.addSublayer(stink)
                let cycle = 1.1
                let group = CAAnimationGroup()
                let up = CABasicAnimation(keyPath: "position")
                up.fromValue = NSValue(point: base)
                up.toValue = NSValue(point: CGPoint(x: base.x, y: base.y + big * 0.3))
                let fadeInOut = CAKeyframeAnimation(keyPath: "opacity")
                fadeInOut.values = [0, 0.9, 0]
                fadeInOut.keyTimes = [0, 0.4, 1]
                group.animations = [up, fadeInOut]
                group.duration = cycle
                group.repeatCount = .infinity
                group.beginTime = CACurrentMediaTime() + poopSitAt + poopSitGrow + Double(k) * cycle / 3
                stink.add(group, forKey: "stink")
            }
        }

        // It all fades with the broken glass, one curve.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, NSNumber(value: crackHold / total), 1]
        fade.duration = total
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        container.add(fade, forKey: "fade")
        return container
    }

    // MARK: Pictures

    /// A splat's picture is this much bigger than its `size`: room for the
    /// droplets flung round the blob.
    static let splatBoxRatio: CGFloat = 1.6

    /// Shit's browns, `t` in 0…1 from dark to light.
    static func poopColor(_ t: CGFloat) -> CGColor {
        CGColor(red: 0.30 + 0.14 * t, green: 0.17 + 0.09 * t, blue: 0.06 + 0.04 * t, alpha: 0.96)
    }

    /// One wet splat: a lumpy blob, a few droplets flung round it and a glossy
    /// highlight, drawn in code (no asset), seeded so a recording repeats.
    static func splatImage(size: CGFloat, scale: CGFloat, seed: UInt64) -> CGImage? {
        let box = size * splatBoxRatio
        let px = Int(ceil(box * scale))
        guard px > 0,
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: EmojiAnimator.nativeBitmapInfo) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        var rnd = Rand(state: seed &* 2654435761 &+ 1)
        let c = CGPoint(x: box / 2, y: box / 2)
        let r = size / 2
        let shade = rnd.range(0, 1)

        // The blob: a ring of points at a wobbling radius, smoothed through midpoints.
        let n = 14
        var pts: [CGPoint] = []
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi
            let rr = r * rnd.range(0.7, 1.05) * (i % 3 == 0 ? rnd.range(1.0, 1.25) : 1)
            pts.append(CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr))
        }
        let blob = CGMutablePath()
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        blob.move(to: mid(pts[n - 1], pts[0]))
        for i in 0..<n { blob.addQuadCurve(to: mid(pts[i], pts[(i + 1) % n]), control: pts[i]) }
        blob.closeSubpath()
        // Droplets: flung out round it, the bigger ones nearer.
        for _ in 0..<Int(rnd.range(5, 10)) {
            let a = rnd.range(0, 2 * .pi)
            let d = r * rnd.range(1.05, 1.5)
            let dr = r * rnd.range(0.05, 0.16) * (1.6 - d / r * 0.6)
            blob.addEllipse(in: CGRect(x: c.x + cos(a) * d - dr, y: c.y + sin(a) * d - dr, width: dr * 2, height: dr * 2))
        }

        ctx.addPath(blob)
        ctx.setFillColor(poopColor(shade * 0.5))
        ctx.fillPath()
        // Lighter in the middle, darker at the rim: it has a body.
        ctx.saveGState()
        ctx.addPath(blob)
        ctx.clip()
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [poopColor(0.4 + shade * 0.6), poopColor(shade * 0.3)] as CFArray,
                              locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - r * 0.15, y: c.y + r * 0.15), startRadius: 0,
                                   endCenter: c, endRadius: r * 1.1, options: [])
        }
        ctx.restoreGState()
        // The wet shine, top-left.
        ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.85, alpha: 0.35))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.5, y: c.y + r * 0.2, width: r * 0.35, height: r * 0.2))
        return ctx.makeImage()
    }

    /// 💩 as a picture, cached by its pixel size.
    static func poopEmojiImage(size: CGFloat, scale: CGFloat) -> CGImage? {
        let px = Int(ceil(size * scale))
        let key = "poop|\(px)"
        if let hit = poopCache[key] { return hit }
        guard px > 0,
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: EmojiAnimator.nativeBitmapInfo) else { return nil }
        let font = NSFont.systemFont(ofSize: CGFloat(px) * 0.82)
        let str = NSAttributedString(string: "💩", attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(str)
        let glyphBox = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: (CGFloat(px) - glyphBox.width) / 2 - glyphBox.minX,
                                   y: (CGFloat(px) - glyphBox.height) / 2 - glyphBox.minY)
        CTLineDraw(line, ctx)
        let img = ctx.makeImage()
        poopCache[key] = img
        return img
    }
    private static var poopCache: [String: CGImage] = [:]
}
