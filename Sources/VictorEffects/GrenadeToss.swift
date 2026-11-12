import AppKit
import QuartzCore

/// 💣 Tile #87 "Fire in the hole!": a pineapple grenade is lobbed in from a
/// bottom corner, tumbles through an arc, bounces twice, rattles, and blows up
/// **where the pointer was at the press** (Victor, 2026-11-12: "să ajungă
/// grenada unde era mouse-ul la începutul efectului") — the middle of the
/// screen when the pointer is on another display.
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
    /// The glass cracks where it fell — once the shake has died (Victor,
    /// 2026-11-12: "ulterior să crape o parte din ecran unde a căzut, după ce
    /// zguduie un pic ecranul"). Derived from the shake, so the two can't overlap.
    static let crackAt: Double = blastAt + BombShake.seconds
    /// How long the crack stays, whole, before it fades.
    static let crackHold: Double = 2.6
    static let crackFade: Double = 0.6
    /// The crack runs out from the impact over this long — fast, as glass does.
    static let crackSpread: Double = 0.12
    /// When everything is gone. `trackEffect` removes the container here.
    static let totalDuration: Double = max(blastAt + blastDuration, crackAt + crackHold + crackFade)

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
    /// Where it first touches down, short of where it comes to rest — the
    /// bounces carry it the rest of the way to the target.
    static let land1OffsetFraction: CGFloat = 0.09
    static let land2OffsetFraction: CGFloat = 0.03
    /// Fireball diameter, as a fraction of the screen's shorter side.
    static let blastDiameterFraction: CGFloat = 0.75

    /// Turns it tumbles through, in the direction it flies (clockwise to the
    /// right). The total, 4¼ turns, leaves it lying on its side.
    static let flightTurns: Double = 3.3
    static let bounce1Turns: Double = 0.6
    static let bounce2Turns: Double = 0.35

    /// The rattle before the blast: angle amplitude (radians) and frequency.
    static let rattleAmplitude: Double = 0.10
    static let rattleHz: Double = 14

    /// Where it lands and explodes: the pointer at the press, kept far enough
    /// inside the screen that the grenade and its first bounce stay on the
    /// glass. nil (the pointer is on another display) → the middle.
    static func target(pointer: CGPoint?, in b: CGRect) -> CGPoint {
        guard let p = pointer, b.contains(p) else { return CGPoint(x: b.midX, y: b.midY) }
        let m = restHeight(in: b)
        return CGPoint(x: min(max(p.x, b.minX + m), b.maxX - m),
                       y: min(max(p.y, b.minY + m), b.maxY - m - bounce1HeightFraction * b.height))
    }

    /// +1 thrown to the right (from the bottom-left corner), -1 to the left.
    /// From the bottom corner on the FAR side of the target, so a pointer near
    /// a corner still gets a throw across the screen instead of a drop.
    static func direction(toward target: CGPoint, in b: CGRect) -> CGFloat {
        target.x >= b.midX ? 1 : -1
    }

    /// Just outside that bottom corner: at `startScale` the grenade already
    /// overlaps the corner on the first frame, so the room sees it come IN from
    /// there rather than appear on the side edge.
    static func startPoint(toward target: CGPoint, in b: CGRect) -> CGPoint {
        direction(toward: target, in: b) > 0
            ? CGPoint(x: b.minX - 0.02 * b.width, y: b.minY - 0.04 * b.height)
            : CGPoint(x: b.maxX + 0.02 * b.width, y: b.minY - 0.04 * b.height)
    }

    static func restHeight(in b: CGRect) -> CGFloat { min(b.width, b.height) * restHeightFraction }

    struct Pose: Equatable {
        var position: CGPoint
        /// Radians, y-up (negative = clockwise).
        var angle: Double
        var scale: CGFloat
    }

    /// Where the grenade is, how it is turned and how big it is, `t` seconds
    /// after the press, on its way to `rest` (a `target(pointer:in:)`).
    /// Clamped: before 0 it is at the corner, after the blast it stays where it
    /// went off.
    static func pose(at t: Double, to rest: CGPoint, in b: CGRect) -> Pose {
        let dir = direction(toward: rest, in: b)
        let start = startPoint(toward: rest, in: b)
        let land1 = CGPoint(x: rest.x - dir * land1OffsetFraction * b.width, y: rest.y)
        let land2 = CGPoint(x: rest.x - dir * land2OffsetFraction * b.width, y: rest.y)
        // Never through the top: the arc's peak is at most `arc` above the
        // target (the straight line only climbs towards it).
        let arc = min(arcHeightFraction * b.height, max(0, b.maxY - restHeight(in: b) - rest.y))
        let turn = -2 * Double.pi * Double(dir)
        let t = max(0, min(t, blastAt))

        func lerp(_ a: CGFloat, _ b: CGFloat, _ u: CGFloat) -> CGFloat { a + (b - a) * u }
        func hop(_ s: CGFloat) -> CGFloat { 4 * s * (1 - s) }

        if t < flight {
            let s = CGFloat(t / flight)
            // Eased: fast out of the hand, slowing as it travels away — gently,
            // or the corner is crossed in a frame and never seen.
            let u = 1 - pow(1 - s, 1.2)
            let x = lerp(start.x, land1.x, u)
            let y = lerp(start.y, land1.y, u) + arc * hop(u)
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
    static func flightAnimations(to rest: CGPoint, in b: CGRect) -> [String: CAKeyframeAnimation] {
        let fps = 60.0
        let n = Int((blastAt * fps).rounded())
        let poses = (0...n).map { pose(at: Double($0) / fps, to: rest, in: b) }
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

    // MARK: The crack

    /// How much of the screen the blast leaves black and broken (Victor,
    /// 2026-11-12: "cam 25% din ecran să devină negru/stricat"). Counted ON
    /// the glass: next to an edge the hole grows to make up for what the edge
    /// cuts off.
    static let brokenAreaFraction: CGFloat = 0.25
    /// The cracked-but-whole glass reaches this far past the hole's radius.
    static let webReach: CGFloat = 1.7
    /// The hole's pieces: 16 slices around, 4 per slice.
    static let crackSlices = 16

    /// The radius of a disc at `c` whose part inside `b` is `brokenAreaFraction`
    /// of `b`. Bisection over a sampled grid — exact enough, and a few ms.
    static func holeRadius(at c: CGPoint, in b: CGRect) -> CGFloat {
        let target = brokenAreaFraction
        func covered(_ r: CGFloat) -> CGFloat {
            let n = 60
            var inside = 0
            for i in 0..<n { for j in 0..<n {
                let p = CGPoint(x: b.minX + (CGFloat(i) + 0.5) / CGFloat(n) * b.width,
                                y: b.minY + (CGFloat(j) + 0.5) / CGFloat(n) * b.height)
                if hypot(p.x - c.x, p.y - c.y) <= r { inside += 1 }
            } }
            return CGFloat(inside) / CGFloat(n * n)
        }
        var lo: CGFloat = 0, hi = hypot(b.width, b.height)
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            if covered(mid) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// One piece of the hole, and where its middle is (the way it flies out).
    struct Shard {
        var path: CGPath
        var centroid: CGPoint
    }

    /// The broken glass around the impact: `hole` is the jagged black region,
    /// `shards` the pieces it is made of (they fly out of it), `lines` every
    /// crack in the glass that stays (radials on from the hole's rim, and
    /// rings linking some of them).
    struct Crack {
        var lines: CGPath
        var hole: CGPath
        var shards: [Shard]
    }

    /// Seeded, so a recording looks the same twice; the seed is per press in
    /// the app, so two presses don't crack the same way.
    static func crack(at c: CGPoint, holeRadius rh: CGFloat, seed: UInt64) -> Crack {
        var rnd = Rand(state: seed)
        let n = crackSlices
        let angles = (0..<n).map { (CGFloat($0) + rnd.range(-0.3, 0.3)) / CGFloat(n) * 2 * .pi }
        // Inside the hole: points on each radial at three distances, the last
        // one the rim. Jittered, so the pieces are not a dartboard.
        let inner: [CGFloat] = [0.3, 0.62, 1.0]
        var pts: [[CGPoint]] = []
        for a in angles {
            var row: [CGPoint] = []
            var heading = a
            for f in inner {
                heading += rnd.range(-0.08, 0.08)
                let d = rh * f * rnd.range(0.88, 1.08)
                row.append(CGPoint(x: c.x + cos(heading) * d, y: c.y + sin(heading) * d))
            }
            pts.append(row)
        }
        // A jag in the rim between each pair of radials, shared by the hole's
        // outline and the outer shard, so they fit edge to edge.
        var jags: [CGPoint] = []
        for i in 0..<n {
            let p = pts[i][2], q = pts[(i + 1) % n][2]
            let out = rnd.range(-0.06, 0.1) * rh
            let mid = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            let len = max(1, hypot(mid.x - c.x, mid.y - c.y))
            jags.append(CGPoint(x: mid.x + (mid.x - c.x) / len * out, y: mid.y + (mid.y - c.y) / len * out))
        }

        func poly(_ ps: [CGPoint]) -> Shard {
            let path = CGMutablePath()
            path.addLines(between: ps); path.closeSubpath()
            let cx = ps.map(\.x).reduce(0, +) / CGFloat(ps.count)
            let cy = ps.map(\.y).reduce(0, +) / CGFloat(ps.count)
            return Shard(path: path, centroid: CGPoint(x: cx, y: cy))
        }
        var shards: [Shard] = []
        for i in 0..<n {
            let j = (i + 1) % n
            shards.append(poly([c, pts[i][0], pts[j][0]]))
            shards.append(poly([pts[i][0], pts[i][1], pts[j][1], pts[j][0]]))
            // The outer ring is the biggest: split corner to corner, two pieces.
            shards.append(poly([pts[i][1], pts[i][2], jags[i]]))
            shards.append(poly([pts[i][1], jags[i], pts[j][2], pts[j][1]]))
        }

        let hole = CGMutablePath()
        hole.move(to: pts[0][2])
        for i in 0..<n { hole.addLine(to: jags[i]); hole.addLine(to: pts[(i + 1) % n][2]) }
        hole.closeSubpath()

        // The glass that stays: radials from the rim outward, then rings.
        let rw = rh * webReach
        var outer: [[CGPoint]] = []
        let ringFractions: [CGFloat] = [0.3, 0.65]   // of the way from the rim to `rw`
        let lines = CGMutablePath()
        for (i, a) in angles.enumerated() {
            let reach = rnd.range(0.35, 1.0)
            var heading = a
            var row: [CGPoint] = [pts[i][2]]
            for f in ringFractions + [reach] where f <= reach {
                heading += rnd.range(-0.1, 0.1)
                let d = rh + (rw - rh) * f
                row.append(CGPoint(x: c.x + cos(heading) * d, y: c.y + sin(heading) * d))
            }
            outer.append(row)
            lines.move(to: row[0])
            for p in row.dropFirst() { lines.addLine(to: p) }
            // Now and then a crack forks.
            if rnd.next() < 0.4, row.count > 2 {
                let fork = heading + rnd.range(0.25, 0.5) * (rnd.next() < 0.5 ? -1 : 1)
                let from = row[1], d = (rw - rh) * rnd.range(0.2, 0.45)
                lines.move(to: from)
                lines.addLine(to: CGPoint(x: from.x + cos(fork) * d, y: from.y + sin(fork) * d))
            }
        }
        for i in 0..<n {
            let j = (i + 1) % n
            for k in 0..<ringFractions.count where outer[i].count > k + 1 && outer[j].count > k + 1 {
                guard rnd.next() < (k == 0 ? 0.85 : 0.5) else { continue }
                let p = outer[i][k + 1], q = outer[j][k + 1]
                let mid = CGPoint(x: (p.x + q.x) / 2 + rnd.range(-0.03, 0.03) * rw,
                                  y: (p.y + q.y) / 2 + rnd.range(-0.03, 0.03) * rw)
                lines.move(to: p); lines.addLine(to: mid); lines.addLine(to: q)
            }
        }
        return Crack(lines: lines, hole: hole, shards: shards)
    }

    /// Every shard as its own small picture, cut out of `shot` (the desktop
    /// photograph, laid over `bounds`) with a bright glass edge — or, with no
    /// photograph, as smoked glass. Pictures, not masked full-screen layers:
    /// 64 masks moving at once would each cost an offscreen pass per frame.
    /// Safe off the main thread.
    static func shardImages(_ crack: Crack, shot: CGImage?, bounds: CGRect,
                            scale: CGFloat) -> [(image: CGImage, frame: CGRect)] {
        crack.shards.compactMap { shard in
            let box = shard.path.boundingBoxOfPath.insetBy(dx: -2, dy: -2).integral
            let pw = Int(ceil(box.width * scale)), ph = Int(ceil(box.height * scale))
            guard pw > 0, ph > 0,
                  let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: EmojiAnimator.nativeBitmapInfo) else { return nil }
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.saveGState()
            ctx.addPath(shard.path)
            ctx.clip()
            if let shot {
                ctx.draw(shot, in: bounds)
                ctx.setFillColor(rgba(1, 1, 1, 0.08))   // a sheen: it is glass now
                ctx.fill(box)
            } else {
                ctx.setFillColor(rgba(0.55, 0.62, 0.66, 0.55))
                ctx.fill(box)
            }
            ctx.restoreGState()
            ctx.addPath(shard.path)
            ctx.setStrokeColor(rgba(1, 1, 1, 0.75))
            ctx.setLineWidth(1.5)
            ctx.strokePath()
            guard let img = ctx.makeImage() else { return nil }
            return (img, box)
        }
    }

    /// Where a shard flying out of the hole is, `t` seconds after the glass
    /// broke: thrown away from the impact (and a little upward), then down
    /// under gravity. Pure, so the tests can ask it.
    static func shardPosition(from p: CGPoint, velocity v: CGVector, at t: Double) -> CGPoint {
        let g: CGFloat = 2600
        let t = CGFloat(t)
        return CGPoint(x: p.x + v.dx * t, y: p.y + v.dy * t - g * t * t / 2)
    }
    static let shardFlight: Double = 1.5

    /// The crack as layers, every animation un-begun (they start in the
    /// caller's transaction): the black hole with a few dead-LCD bleed lines,
    /// the shards bursting out of it, and the cracked glass around it — dark
    /// lines on a bright edge so they read on a white slide and on a dark one,
    /// revealed from the impact outward.
    static func makeCrack(_ crack: Crack, at c: CGPoint, holeRadius rh: CGFloat, in bounds: CGRect,
                          shards: [(image: CGImage, frame: CGRect)], scale: CGFloat, seed: UInt64) -> CALayer {
        let container = CALayer()
        container.frame = bounds
        var rnd = Rand(state: seed ^ 0x5eed)

        let hole = CAShapeLayer()
        hole.frame = bounds
        hole.path = crack.hole
        hole.fillColor = rgba(0.01, 0.01, 0.01, 0.97)
        hole.strokeColor = rgba(0.85, 0.88, 0.9, 0.6)   // the broken edge catches the light
        hole.lineWidth = 1.5
        container.addSublayer(hole)

        // A dead panel bleeds: a few thin stripes of stuck colour running from
        // the hole to the screen's edge. What says "broken screen", not "black blob".
        let bleed: [CGColor] = [rgba(1, 0.1, 0.8, 0.85), rgba(0.1, 0.95, 1, 0.8),
                                rgba(0.2, 1, 0.3, 0.75), rgba(1, 1, 1, 0.8)]
        for i in 0..<8 {
            let x = c.x + rnd.range(-0.85, 0.85) * rh
            let up = i % 2 == 0
            let edgeY = c.y + (up ? 1 : -1) * sqrt(max(0, rh * rh - (x - c.x) * (x - c.x))) * 0.8
            let far = up ? bounds.maxY : bounds.minY
            let len = abs(far - edgeY) * rnd.range(0.35, 1)
            let w = rnd.range(1, 3.5)
            let stripe = CALayer()
            stripe.frame = CGRect(x: x, y: up ? edgeY : edgeY - len, width: w, height: len)
            stripe.backgroundColor = bleed[i % bleed.count]
            container.addSublayer(stripe)
        }

        // The shards: out in every direction from the impact, spinning,
        // growing as they come at the viewer, fading as they go.
        let fps = 30.0
        let steps = Int(shardFlight * fps)
        for (image, frame) in shards {
            let p = CGPoint(x: frame.midX, y: frame.midY)
            var dx = p.x - c.x, dy = p.y - c.y
            let len = hypot(dx, dy)
            if len < 1 { let a = rnd.range(0, 2 * .pi); dx = cos(a); dy = sin(a) } else { dx /= len; dy /= len }
            let turn = rnd.range(-0.5, 0.5)
            let dir = CGVector(dx: dx * cos(turn) - dy * sin(turn), dy: dx * sin(turn) + dy * cos(turn))
            let speed = rnd.range(500, 1500) * (0.7 + 0.6 * min(1, len / rh))
            let v = CGVector(dx: dir.dx * speed, dy: dir.dy * speed + rnd.range(150, 600))

            let l = CALayer()
            l.contents = image
            l.contentsScale = scale
            l.frame = frame
            container.addSublayer(l)

            let pos = CAKeyframeAnimation(keyPath: "position")
            pos.values = (0...steps).map { NSValue(point: shardPosition(from: p, velocity: v, at: Double($0) / fps)) }
            pos.duration = shardFlight
            pos.calculationMode = .linear
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = rnd.range(-9, 9)
            spin.duration = shardFlight
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = rnd.range(1.1, 1.7)
            grow.duration = shardFlight
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.7, 1]
            fade.duration = shardFlight
            for a in [pos, spin, grow, fade] as [CAAnimation] {
                a.fillMode = .forwards
                a.isRemovedOnCompletion = false
            }
            l.add(pos, forKey: "fly"); l.add(spin, forKey: "spin")
            l.add(grow, forKey: "grow"); l.add(fade, forKey: "fade")
        }

        // Bright edge under, dark crack over it, a hair to the side: glass.
        // In their own layer, the only one the reveal masks — the shards fly
        // far outside it and must not be clipped on the way.
        let web = CALayer()
        web.frame = bounds
        container.addSublayer(web)
        // Wide enough to survive a projector: 2.2 pt of crack on 4 pt of edge.
        for (color, width, dx) in [(rgba(1, 1, 1, 0.85), CGFloat(4), CGFloat(1)),
                                   (rgba(0.08, 0.08, 0.1, 0.9), CGFloat(2.2), CGFloat(0))] {
            let l = CAShapeLayer()
            l.frame = bounds.offsetBy(dx: dx, dy: -dx)
            l.path = crack.lines
            l.fillColor = nil
            l.strokeColor = color
            l.lineWidth = width
            l.lineJoin = .miter
            l.lineCap = .butt
            web.addSublayer(l)
        }
        let rw = rh * webReach * 1.1
        let reveal = CAShapeLayer()
        reveal.frame = bounds
        reveal.path = CGPath(ellipseIn: CGRect(x: c.x - rw, y: c.y - rw, width: rw * 2, height: rw * 2), transform: nil)
        reveal.anchorPoint = .zero
        reveal.position = .zero
        web.mask = reveal
        let spread = CABasicAnimation(keyPath: "transform")
        spread.fromValue = NSValue(caTransform3D: CATransform3DConcat(
            CATransform3DConcat(CATransform3DMakeTranslation(-c.x, -c.y, 0), CATransform3DMakeScale(0.3, 0.3, 1)),
            CATransform3DMakeTranslation(c.x, c.y, 0)))
        spread.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spread.duration = crackSpread
        spread.timingFunction = CAMediaTimingFunction(name: .easeOut)
        reveal.add(spread, forKey: "spread")

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        let total = crackHold + crackFade
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, NSNumber(value: crackHold / total), 1]
        fade.duration = total
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        container.add(fade, forKey: "fade")
        return container
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
