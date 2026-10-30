import AppKit
import AVFoundation
import CoreImage
import ImageIO
import QuartzCore

/// 🌊 Tile 55b (`55b_tsunami.mp3`, folded under #55 Star Wars): **a wall of
/// water sweeps the screen left to right and leaves it washed clean** — the text gone, the background a blurred grey
/// ghost of itself (2026-10-30, Victor: *"un tsunami să mă măture ecranul și
/// să-mi curețe textul, să lase fundalul cumva gri … un val mare să rupă tot"*).
///
/// One capture, two pictures of it. The screen as it is, on top, so the first
/// frame looks like nothing happened; and under it a WASHED copy — blurred past
/// legibility, drained of colour, pulled toward grey. The water wipes the one
/// off to the other: the capture is masked to whatever the wave has not reached
/// yet, so what the wave leaves behind is the washed copy, wet for a moment,
/// then dry. Nothing is torn off — the wave sweeps it (Victor, 2026-10-30: "nu
/// mai rupe ecranul ci doar mătură ecranul cu valul"). Clean until the clip
/// ends, then the real screen fades back.
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

    // MARK: The filmed wave (optional drop-in)

    /// A real breaker, when `assetsDir/tsunami-wave/NN.png` is there (made by
    /// `tools/make-tsunami-wave.py` from a GIF we may not publish, 2026-10-30,
    /// Victor: "folosește GIF-ul ăsta"). Without it the drawn breaker below
    /// runs, as before. It curls in place in the frames; the slide carries it.
    static var spriteDir: URL { EffectsConfig.shared.assetsDir.appendingPathComponent("tsunami-wave") }
    static let spriteFPS: Double = 15
    /// The filmed wave's height, as a share of the screen's (bottom-aligned):
    /// tall enough that its crest (a fifth of the frame from the top) reaches
    /// the top edge, so every row of the screen is swept by water, not by sky.
    static let spriteHeightShare: CGFloat = 1.25
    /// Once its front has crossed the glass, the wave leaves this fast, so the
    /// washed screen gets the clip's remaining seconds to itself.
    static let spriteExit: Double = 1.2

    struct Sprite {
        let frames: [CGImage]
        /// Per row, top to bottom: how far right the water reaches, as a share
        /// of the frame's width (its rightmost opaque pixel in most frames).
        let front: [CGFloat]
        var aspect: CGFloat { CGFloat(frames[0].width) / CGFloat(frames[0].height) }
        /// The frontmost point of the wave: what "the front is at x" means.
        var lip: CGFloat { front.max() ?? 1 }

        /// The edge of what the water has not reached yet, in points relative
        /// to the lip (x ≤ 0), for a sprite `size` bottom-aligned at y = 0:
        /// one point per row, top to bottom, held `margin` behind the water so
        /// the foam's frame-to-frame jitter never opens a gap onto the old screen.
        func edge(size: CGSize, margin: CGFloat) -> [CGPoint] {
            let n = CGFloat(front.count)
            return front.enumerated().map { row, f in
                CGPoint(x: (f - lip) * size.width - margin, y: size.height * (1 - (CGFloat(row) + 0.5) / n))
            }
        }
    }

    /// Per row, the rightmost column opaque in at least half the frames; rows
    /// with no water (the sky above the crest) take the crest's value. Pure.
    static func frontProfile(alpha frames: [[UInt8]], width: Int, height: Int) -> [CGFloat] {
        guard !frames.isEmpty, width > 0, height > 0 else { return [] }
        var rows = [CGFloat?](repeating: nil, count: height)
        for y in 0..<height {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let opaque = frames.reduce(0) { $0 + ($1[y * width + x] > 128 ? 1 : 0) }
                if opaque * 2 >= frames.count { rows[y] = CGFloat(x + 1) / CGFloat(width); break }
            }
        }
        let crest = rows.compactMap { $0 }.min() ?? 1
        return rows.map { $0 ?? crest }
    }

    /// The frames, decoded here (off the main thread) so the first ones do not
    /// stutter, plus their front profile. Loaded once.
    private static var _sprite: Sprite??
    static func loadSprite() -> Sprite? {
        if let s = _sprite { return s }
        let files = ((try? FileManager.default.contentsOfDirectory(at: spriteDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var frames: [CGImage] = []
        var alphas: [[UInt8]] = []
        for f in files {
            guard let src = CGImageSourceCreateWithURL(f as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let w = img.width, h = img.height
            if let first = frames.first, first.width != w || first.height != h { continue }
            var px = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let decoded = ctx.makeImage() else { continue }
            frames.append(decoded)
            alphas.append(stride(from: 3, to: px.count, by: 4).map { px[$0] })
        }
        let sprite: Sprite? = frames.isEmpty ? nil
            : Sprite(frames: frames, front: frontProfile(alpha: alphas, width: frames[0].width, height: frames[0].height))
        if sprite == nil, !files.isEmpty { effectsError("🌊 tsunami: \(spriteDir.path) has no readable frames") }
        _sprite = .some(sprite)
        return sprite
    }

    // MARK: Preparation (off the main thread)

    struct Prepared { let washed: CGImage?; let shot: CGImage; var sprite: Sprite? = nil }

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

    static func prepare(shot: CGImage, size: CGSize) -> Prepared {
        Prepared(washed: washed(shot), shot: shot, sprite: loadSprite())
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

        // 3. The breaker, sliding from just off the left edge to well past the right:
        // the filmed one when its frames are there, else the drawn one. `edge` is
        // the line, relative to the lip, behind which the screen has been swept.
        let wave: CALayer
        let slide: CAAnimation
        let edge: [CGPoint]
        if let sprite = prepared.sprite {
            let size = CGSize(width: H * spriteHeightShare * sprite.aspect, height: H * spriteHeightShare)
            wave = makeSpriteWave(sprite, size: size, clock0: clock0)
            let travel = W + sprite.lip * size.width
            wave.position = CGPoint(x: travel, y: 0)
            let s = CAKeyframeAnimation(keyPath: "position.x")
            s.values = [0, W, travel]
            s.keyTimes = [0, NSNumber(value: frontCrosses / (frontCrosses + spriteExit)), 1]
            s.duration = frontCrosses + spriteExit
            slide = s
            edge = sprite.edge(size: size, margin: 0.02 * size.width)
        } else {
            let L = bodyShare * W
            wave = makeWave(height: H, body: L, scale: scale)
            let travel = W * (1 + bodyShare * 1.7)
            wave.position = CGPoint(x: travel, y: 0)
            let s = CABasicAnimation(keyPath: "position.x")
            s.fromValue = 0
            s.toValue = travel
            s.duration = frontCrosses * Double(travel / W)
            slide = s
            // Behind the hollow face's deepest point (−0.32 L), top to bottom.
            edge = [CGPoint(x: -0.36 * L, y: H * 1.1), CGPoint(x: -0.36 * L, y: 0)]
        }
        slide.beginTime = clock0 + frontEnters
        slide.fillMode = .both
        slide.isRemovedOnCompletion = false
        wave.add(slide, forKey: "slide")
        wave.zPosition = 10
        root.addSublayer(wave)

        // 4. The screen as it was, over the washed copy, masked to what the water
        // has not reached yet: the mask's left edge rides with the wave.
        let before = CALayer()
        before.frame = CGRect(origin: .zero, size: bounds.size)
        before.contents = prepared.shot
        before.contentsGravity = .resize
        before.zPosition = 5
        let ahead = aheadPath(edge: edge, width: W, height: H)
        let mask = CAShapeLayer()
        mask.anchorPoint = .zero
        mask.bounds = .zero
        mask.path = ahead
        mask.fillColor = NSColor.black.cgColor
        mask.position = .zero
        mask.add(slide, forKey: "slide")
        before.mask = mask
        root.addSublayer(before)

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

    /// What the water has not reached yet, relative to the lip: one rectangle
    /// per row of `edge` (row centres, any order), from the row's edge out to
    /// past the screen's right side, kept to the glass (the mask rides the lip,
    /// which is never left of the screen, so `width` past it is the whole screen).
    ///
    /// Strips, not one polygon through the edge points: a 540-vertex concave
    /// polygon was tessellated wrong, leaving a diagonal wedge of the screen
    /// already swept before the wave got there (seen offscreen, 2026-10-31, with
    /// the GIF's frames as much as the film's). Each strip overlaps the next by
    /// half a point so no hairline of the old screen shows between them. Pure.
    static func aheadPath(edge: [CGPoint], width W: CGFloat, height H: CGFloat) -> CGPath {
        let top = H + 2, bottom: CGFloat = -2, far = W + 2
        let rows = edge.sorted { $0.y > $1.y }
        let path = CGMutablePath()
        for (k, pt) in rows.enumerated() {
            let hi = min(top, k == 0 ? top : (rows[k - 1].y + pt.y) / 2 + 0.5)
            let lo = max(bottom, k == rows.count - 1 ? bottom : (pt.y + rows[k + 1].y) / 2)
            guard hi > lo, pt.x < far else { continue }
            path.addRect(CGRect(x: pt.x, y: lo, width: far - pt.x, height: hi - lo))
        }
        return path
    }

    /// The filmed breaker: its frames on a loop, bottom-aligned, the anchor on
    /// its lip so `position.x` is where the front is.
    private static func makeSpriteWave(_ sprite: Sprite, size: CGSize, clock0: CFTimeInterval) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.anchorPoint = CGPoint(x: sprite.lip, y: 0)
        layer.contents = sprite.frames[0]
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        let roll = CAKeyframeAnimation(keyPath: "contents")
        roll.values = sprite.frames
        roll.calculationMode = .discrete
        roll.duration = Double(sprite.frames.count) / spriteFPS
        roll.repeatCount = .infinity
        roll.beginTime = clock0
        layer.add(roll, forKey: "roll")
        return layer
    }

    /// The breaker in its own coordinates: x ≤ 0, the lip's tip at x = 0 (the
    /// frontmost point, so "the front is at x" means the lip is), the body
    /// stretching back to −1.7 × `body` and fading out there.
    private static func makeWave(height H: CGFloat, body L: CGFloat, scale: CGFloat) -> CALayer {
        // Sublayers draw in their OWN coordinates, origin zero, so everything
        // is drawn shifted right by `ox`: the lip's tip sits at x = ox, and the
        // anchor puts that point on `position`.
        let ox = 1.7 * L
        let back = -ox
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x, y: y) }
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: ox + 2, height: H)
        container.anchorPoint = CGPoint(x: ox / (ox + 2), y: 0)

        // The breaker's front, foot to crest: the hollow face, the lip thrown
        // forward OVER it (its tip, the frontmost point, at x = 0), and the lip's
        // upper side back to the top of the crest. The foam is drawn along it too.
        let front = CGMutablePath()
        front.move(to: p(-0.05 * L, 0))
        front.addCurve(to: p(-0.30 * L, 0.45 * H),
                       control1: p(-0.25 * L, 0.05 * H), control2: p(-0.32 * L, 0.25 * H))
        front.addCurve(to: p(-0.18 * L, 0.88 * H),
                       control1: p(-0.30 * L, 0.65 * H), control2: p(-0.26 * L, 0.85 * H))
        front.addCurve(to: p(0, 0.70 * H),
                       control1: p(-0.08 * L, 0.93 * H), control2: p(0.02 * L, 0.85 * H))
        front.addCurve(to: p(-0.20 * L, 0.98 * H),
                       control1: p(0.03 * L, 0.86 * H), control2: p(-0.05 * L, 0.99 * H))

        let outline = front.mutableCopy() ?? CGMutablePath()
        outline.addLine(to: p(-0.6 * L, 1.05 * H))
        outline.addLine(to: p(back, 1.05 * H))
        outline.addLine(to: p(back, 0))
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
        for (width, alpha, blur) in [(CGFloat(26), Float(0.28), CGFloat(14)), (5, 0.8, 4)] {
            let foam = CAShapeLayer()
            foam.frame = container.bounds
            foam.path = front
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
        lip.emitterPosition = p(-0.01 * L, 0.72 * H)
        lip.emitterShape = .circle
        lip.emitterSize = CGSize(width: 0.08 * L, height: 0.08 * L)
        lip.emitterCells = [spray(drop, birthRate: 320, velocity: 420, longitude: .pi / 5,
                                  range: .pi / 3, lifetime: 1.3, gravity: -900)]
        container.addSublayer(lip)
        let face = CAEmitterLayer()
        face.frame = container.bounds
        face.emitterPosition = p(-0.22 * L, 0.25 * H)
        face.emitterShape = .rectangle
        face.emitterSize = CGSize(width: 0.12 * L, height: 0.45 * H)
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
