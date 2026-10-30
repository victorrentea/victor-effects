import AppKit
import AVFoundation
import CoreImage
import QuartzCore

/// 🌊 Tile 55b (`55b_tsunami.mp3`, folded under #55 Star Wars): **a wall of
/// water sweeps the screen left to right, tears the desktop off in pieces and
/// leaves it washed clean** — the text gone, the background a blurred grey
/// ghost of itself (2026-10-30, Victor: *"un tsunami să mă măture ecranul și
/// să-mi curețe textul, să lase fundalul cumva gri … un val mare să rupă tot"*).
///
/// One capture, two pictures of it. The screen as it is, cut into a grid of
/// pieces that cover the glass exactly, so the first frame looks like nothing
/// happened; and under them a WASHED copy — blurred past legibility, drained of
/// colour, pulled toward grey. As the breaker's lip reaches a piece it is
/// ripped off and tumbles ahead in the crest; what it uncovers is the washed
/// copy, wet for a moment, then dry. Clean until the clip ends, then the real
/// screen fades back.
///
/// The clip is the tablet's (routed, so the visual is silent), and it was made
/// for this timeline: the roar starts and pans left → right exactly while the
/// lip crosses the glass (`frontEnters` … + `frontCrosses`). Re-cut the clip
/// and those two numbers move with it.
enum Tsunami {
    static let sound = "55b_tsunami.mp3"
    /// The clip's length when the file cannot be read.
    static let fallbackClip: Double = 7.3
    /// The lip touches the left edge this long after the press…
    static let frontEnters: Double = 0.35
    /// …and the right edge this long after that. Constant speed: a wave that
    /// eased in would read as a curtain, not as water.
    static let frontCrosses: Double = 2.5
    /// The breaker's length behind its lip, as a share of the screen width.
    static let bodyShare: CGFloat = 0.42
    /// Pieces per row; rows follow from the screen's aspect so they stay square.
    static let columns = 18
    /// How long a ripped piece tumbles before it has gone under.
    static let pieceFlight: Double = 1.15
    /// The wet sheen over the washed screen dries off in this window.
    static let wetFadeStart: Double = 3.4
    static let wetFadeDuration: Double = 1.6
    /// The washed screen hands back to the real one over the clip's last stretch.
    static let fadeOut: Double = 0.8

    /// On-screen length: the clip, but never shorter than the wave needs to
    /// cross, leave and dry.
    static func totalDuration(clip: Double) -> Double {
        max(clip, wetFadeStart + wetFadeDuration + fadeOut)
    }

    /// The clip's real length, read off the file in `soundsDir`.
    static func clipLength() -> Double {
        guard let url = SoundManager.shared.soundURL(for: sound) else { return fallbackClip }
        let d = AVURLAsset(url: url).duration
        return d.isNumeric && CMTimeGetSeconds(d) > 0 ? CMTimeGetSeconds(d) : fallbackClip
    }

    /// Seconds after the press at which the wave reaches a piece whose left
    /// edge is at `x` and whose centre is at height `y`. The lip (high up) is
    /// the frontmost point; the concave face below it trails, so low pieces go
    /// a little later — the breaker plunges, it does not push a flat wall.
    static func launchTime(x: CGFloat, y: CGFloat, size: CGSize) -> Double {
        guard size.width > 0, size.height > 0 else { return frontEnters }
        let trail = bodyShare * size.width * 0.25 * max(0, 1 - y / (0.75 * size.height))
        return frontEnters + frontCrosses * Double((x + trail) / size.width)
    }

    // MARK: Preparation (off the main thread)

    struct Piece { let frame: CGRect; let image: CGImage }
    struct Prepared { let washed: CGImage?; let pieces: [Piece] }

    private static let ci = CIContext(options: [.cacheIntermediates: false])

    /// Blurred far past legibility (at quarter resolution — it is going to be a
    /// smear anyway, and that is the expensive filter), saturation nearly gone,
    /// then pulled 40 % of the way to mid-grey: the layout of the screen is
    /// still there as soft light and dark, the text is not.
    static func washed(_ shot: CGImage) -> CGImage? {
        let input = CIImage(cgImage: shot)
        let small = input.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let out = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14])
            .cropped(to: small.extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.15, kCIInputContrastKey: 0.85,
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.6, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.6, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.6, w: 0),
                "inputBiasVector": CIVector(x: 0.2, y: 0.21, z: 0.22, w: 0),
            ])
        return ci.createCGImage(out, from: small.extent)
    }

    /// The capture cut into the grid, each piece's frame in `size` (points,
    /// y up) with its own crop of the image (pixels, y down).
    static func pieces(of shot: CGImage, size: CGSize) -> [Piece] {
        guard size.width > 0, size.height > 0 else { return [] }
        let cw = size.width / CGFloat(columns)
        let rows = max(1, Int((size.height / cw).rounded()))
        let ch = size.height / CGFloat(rows)
        let sx = CGFloat(shot.width) / size.width, sy = CGFloat(shot.height) / size.height
        var out: [Piece] = []
        out.reserveCapacity(rows * columns)
        for r in 0..<rows {
            for c in 0..<columns {
                let frame = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw, height: ch)
                let pixels = CGRect(x: frame.minX * sx, y: (size.height - frame.maxY) * sy,
                                    width: cw * sx, height: ch * sy).integral
                if let crop = shot.cropping(to: pixels) { out.append(Piece(frame: frame, image: crop)) }
            }
        }
        return out
    }

    static func prepare(shot: CGImage, size: CGSize) -> Prepared {
        Prepared(washed: washed(shot), pieces: pieces(of: shot, size: size))
    }

    // MARK: The layers (main thread)

    /// The whole effect in `bounds`, every animation hung off `clock0` (the
    /// press, in media time), the last one ending at `total`.
    static func makeLayer(in bounds: CGRect, prepared: Prepared, clock0: CFTimeInterval,
                          total: Double, scale: CGFloat) -> CALayer {
        let W = bounds.width, H = bounds.height
        let root = CALayer()
        root.frame = bounds

        // 1. The washed screen, under everything.
        let washed = CALayer()
        washed.frame = CGRect(origin: .zero, size: bounds.size)
        washed.contents = prepared.washed
        washed.contentsGravity = .resize
        root.addSublayer(washed)

        // 2. The water left behind: a teal film that grows with the front and dries.
        let wet = CALayer()
        wet.anchorPoint = CGPoint(x: 0, y: 0.5)
        wet.position = CGPoint(x: 0, y: H / 2)
        wet.bounds = CGRect(x: 0, y: 0, width: W, height: H)
        wet.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.40, alpha: 0.45).cgColor
        wet.opacity = 0
        let grow = CABasicAnimation(keyPath: "bounds.size.width")
        grow.fromValue = 0
        grow.toValue = W
        grow.beginTime = clock0 + frontEnters + frontCrosses * Double(bodyShare * 0.2)
        grow.duration = frontCrosses
        grow.fillMode = .both
        grow.isRemovedOnCompletion = false
        wet.add(grow, forKey: "grow")
        let dry = CAKeyframeAnimation(keyPath: "opacity")
        dry.values = [1, 1, 0]
        dry.keyTimes = [0, NSNumber(value: wetFadeStart / (wetFadeStart + wetFadeDuration)), 1]
        dry.beginTime = clock0
        dry.duration = wetFadeStart + wetFadeDuration
        dry.fillMode = .forwards
        dry.isRemovedOnCompletion = false
        wet.add(dry, forKey: "dry")
        root.addSublayer(wet)

        // 3. The breaker, sliding from just off the left edge to well past the right.
        let wave = makeWave(height: H, body: bodyShare * W, scale: scale)
        wave.zPosition = 10
        let travel = W * (1 + bodyShare * 1.7)
        wave.position = CGPoint(x: travel, y: 0)
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = 0
        slide.toValue = travel
        slide.beginTime = clock0 + frontEnters
        slide.duration = frontCrosses * Double(travel / W)
        slide.fillMode = .both
        slide.isRemovedOnCompletion = false
        wave.add(slide, forKey: "slide")
        root.addSublayer(wave)

        // 4. The screen as it was, in pieces, each ripped off as the lip reaches it.
        let speed = W / CGFloat(frontCrosses)
        for piece in prepared.pieces {
            let layer = CALayer()
            layer.frame = piece.frame
            layer.contents = piece.image
            layer.contentsGravity = .resize
            layer.zPosition = 20
            let start = launchTime(x: piece.frame.minX, y: piece.frame.midY, size: bounds.size)
                + Double.random(in: 0...0.06)
            layer.add(rip(from: CGPoint(x: piece.frame.midX, y: piece.frame.midY),
                          speed: speed, height: H, beginTime: clock0 + start), forKey: "rip")
            root.addSublayer(layer)
        }

        // 5. Back to the real screen.
        let out = CABasicAnimation(keyPath: "opacity")
        out.fromValue = 1
        out.toValue = 0
        out.beginTime = clock0 + total - fadeOut
        out.duration = fadeOut
        out.fillMode = .forwards
        out.isRemovedOnCompletion = false
        root.add(out, forKey: "fadeOut")
        return root
    }

    /// One piece torn off: flung forward with the water, up toward the crest
    /// and down again, spinning, shrinking as it goes under.
    private static func rip(from c: CGPoint, speed: CGFloat, height H: CGFloat,
                            beginTime: CFTimeInterval) -> CAAnimationGroup {
        let dx = speed * CGFloat(pieceFlight) * .random(in: 0.75...1.3)
        let crest = H * .random(in: 0.7...1.0)
        let rise = max(H * 0.08, crest - c.y) * .random(in: 0.6...1.1)
        let end = CGPoint(x: c.x + dx, y: c.y + rise * 0.3 - H * .random(in: 0...0.25))
        let path = CGMutablePath()
        path.move(to: c)
        path.addQuadCurve(to: end, control: CGPoint(x: c.x + dx * 0.45, y: c.y + rise * 1.6))

        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.4, 1)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.toValue = Double.random(in: 1.5...4) * .pi * (Bool.random() ? 1 : -1)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = Double.random(in: 0.3...0.65)
        let sink = CAKeyframeAnimation(keyPath: "opacity")
        sink.values = [1, 1, 0]
        sink.keyTimes = [0, 0.45, 1]

        let group = CAAnimationGroup()
        group.animations = [move, spin, shrink, sink]
        group.beginTime = beginTime
        group.duration = pieceFlight
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        // Model values stay at rest: before `beginTime` the backwards fill keeps
        // the piece in place, after it the forwards fill keeps it gone.
        return group
    }

    /// The breaker in its own coordinates: x ≤ 0, the lip's tip at x = 0 (the
    /// frontmost point, so "the front is at x" means the lip is), the body
    /// stretching back to −1.7 × `body` and fading out there.
    private static func makeWave(height H: CGFloat, body L: CGFloat, scale: CGFloat) -> CALayer {
        let back = -1.7 * L
        let container = CALayer()
        container.bounds = CGRect(x: back, y: 0, width: -back + 2, height: H)
        container.anchorPoint = CGPoint(x: -back / (-back + 2), y: 0)

        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: back, y: 0))
        outline.addLine(to: CGPoint(x: -0.08 * L, y: 0))
        // The face, hollow: it falls back under the lip…
        outline.addCurve(to: CGPoint(x: -0.24 * L, y: 0.58 * H),
                         control1: CGPoint(x: -0.26 * L, y: 0.14 * H),
                         control2: CGPoint(x: -0.31 * L, y: 0.40 * H))
        // …then throws forward into the lip.
        outline.addCurve(to: CGPoint(x: 0, y: 0.80 * H),
                         control1: CGPoint(x: -0.16 * L, y: 0.76 * H),
                         control2: CGPoint(x: -0.07 * L, y: 0.86 * H))
        // Over the top of the crest and back.
        outline.addCurve(to: CGPoint(x: -0.38 * L, y: 1.0 * H),
                         control1: CGPoint(x: -0.04 * L, y: 0.95 * H),
                         control2: CGPoint(x: -0.20 * L, y: 1.02 * H))
        outline.addLine(to: CGPoint(x: -1.0 * L, y: 0.94 * H))
        outline.addLine(to: CGPoint(x: back, y: 0.88 * H))
        outline.closeSubpath()

        let water = CAGradientLayer()
        water.frame = container.bounds
        water.startPoint = CGPoint(x: 0, y: 0.5)
        water.endPoint = CGPoint(x: 1, y: 0.5)
        water.colors = [
            NSColor(calibratedRed: 0.05, green: 0.18, blue: 0.26, alpha: 0.0).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.32, alpha: 0.9).cgColor,
            NSColor(calibratedRed: 0.07, green: 0.33, blue: 0.45, alpha: 0.97).cgColor,
            NSColor(calibratedRed: 0.22, green: 0.58, blue: 0.68, alpha: 0.98).cgColor,
            NSColor(calibratedRed: 0.80, green: 0.93, blue: 0.96, alpha: 1.0).cgColor,
        ]
        water.locations = [0, 0.3, 0.62, 0.86, 1]
        let mask = CAShapeLayer()
        mask.frame = container.bounds
        mask.path = outline
        water.mask = mask
        container.addSublayer(water)

        // Foam along the face, the lip and the crest: one soft wide band, one bright edge.
        let edge = CGMutablePath()
        edge.move(to: CGPoint(x: -0.08 * L, y: 0))
        edge.addCurve(to: CGPoint(x: -0.24 * L, y: 0.58 * H),
                      control1: CGPoint(x: -0.26 * L, y: 0.14 * H),
                      control2: CGPoint(x: -0.31 * L, y: 0.40 * H))
        edge.addCurve(to: CGPoint(x: 0, y: 0.80 * H),
                      control1: CGPoint(x: -0.16 * L, y: 0.76 * H),
                      control2: CGPoint(x: -0.07 * L, y: 0.86 * H))
        edge.addCurve(to: CGPoint(x: -0.38 * L, y: 1.0 * H),
                      control1: CGPoint(x: -0.04 * L, y: 0.95 * H),
                      control2: CGPoint(x: -0.20 * L, y: 1.02 * H))
        for (width, alpha, blur) in [(CGFloat(46), Float(0.35), CGFloat(24)), (14, 0.95, 10)] {
            let foam = CAShapeLayer()
            foam.frame = container.bounds
            foam.path = edge
            foam.fillColor = nil
            foam.strokeColor = NSColor.white.cgColor
            foam.lineWidth = width
            foam.lineCap = .round
            foam.opacity = alpha
            foam.shadowColor = NSColor.white.cgColor
            foam.shadowOpacity = 1
            foam.shadowRadius = blur
            foam.shadowOffset = .zero
            container.addSublayer(foam)
        }

        // Spray: off the lip, forward and up; and boiling off the face.
        let drop = droplet(scale: scale)
        let lip = CAEmitterLayer()
        lip.frame = container.bounds
        lip.emitterPosition = CGPoint(x: -0.02 * L, y: 0.82 * H)
        lip.emitterShape = .circle
        lip.emitterSize = CGSize(width: 0.08 * L, height: 0.08 * L)
        lip.emitterCells = [spray(drop, birthRate: 320, velocity: 420, longitude: .pi / 5,
                                  range: .pi / 3, lifetime: 1.3, gravity: -900)]
        container.addSublayer(lip)
        let face = CAEmitterLayer()
        face.frame = container.bounds
        face.emitterPosition = CGPoint(x: -0.16 * L, y: 0.32 * H)
        face.emitterShape = .rectangle
        face.emitterSize = CGSize(width: 0.12 * L, height: 0.6 * H)
        face.emitterCells = [spray(drop, birthRate: 420, velocity: 260, longitude: .pi / 8,
                                   range: .pi / 4, lifetime: 0.9, gravity: -600)]
        container.addSublayer(face)
        return container
    }

    private static func spray(_ image: CGImage?, birthRate: Float, velocity: CGFloat, longitude: CGFloat,
                              range: CGFloat, lifetime: Float, gravity: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        cell.birthRate = birthRate
        cell.lifetime = lifetime
        cell.lifetimeRange = lifetime * 0.4
        cell.velocity = velocity
        cell.velocityRange = velocity * 0.5
        cell.emissionLongitude = longitude
        cell.emissionRange = range
        cell.yAcceleration = gravity
        cell.scale = 0.45
        cell.scaleRange = 0.3
        cell.scaleSpeed = -0.15
        cell.alphaSpeed = -0.7
        return cell
    }

    /// A soft white dot, built once.
    private static var _droplet: CGImage?
    private static func droplet(scale: CGFloat) -> CGImage? {
        if let d = _droplet { return d }
        let side = Int(24 * scale)
        guard side > 0, let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [NSColor(white: 1, alpha: 0.95).cgColor,
                                                 NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                                        locations: [0, 1]) else { return nil }
        let c = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c,
                               endRadius: CGFloat(side) / 2, options: [])
        _droplet = ctx.makeImage()
        return _droplet
    }
}
