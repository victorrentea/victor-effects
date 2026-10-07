import AppKit
import CoreImage
import QuartzCore

/// 💀 Skull boom (tile #39) — the TikTok/Shorts "skull edit": the desktop
/// freezes and trembles with the bass, then on the drop a skull's cranium
/// BLOWS OFF — a mushroom cloud
/// and bone shards burst out of the crack, the jaw drops — on a white blow-out
/// with a punch-in zoom, zoom blur, a hard shake, a giant ghost of the skull
/// flying outward and white light rays fanning from it. The screen then stays
/// milky and drained of colour while the smoke clears in patches (edges first,
/// the middle last), the camera still creeping in, and the skull hangs on with
/// a pulsing glow until it swells once and shrinks away.
///
/// The beat is INSIDE the clip — the phonk drop of `39_skull_boom.mp3` lands
/// `dropInClip` in — so, like the FBI knock, the visual owns the audio and
/// hangs off its clock, `visualLead` behind it (`EmojiAnimator.showSkullBoom`).
///
/// This is a **pure builder**, the `CrtShutdown` way: `makeLayer` returns one
/// container with every animation already attached on that clock (`fillMode`
/// `.both`, never removed on completion), so the caller only adds it and hands
/// it to `trackEffect`. Every curve is a plain function of time, sampled at
/// 60 Hz into keyframes — the same functions the approved preview was rendered
/// from, so what was signed off is what plays.
///
/// The art is not in the repo (third-party emoji art, and the repo is public):
/// `assetsDir/skull-boom/{whole,base,jaw,blast}.png` are the exploded skull cut
/// into layers on one shared 421 px canvas, `shard1…3.png` the loose bone
/// pieces.
enum SkullBoom {

    // MARK: - Timing (seconds from the clock)

    /// The drop: white blow-out, the cranium goes. Before it, only the frozen
    /// desktop trembling with the bass — the intact 💀 that used to slam in
    /// here went on 2026-10-08 with the build-up it played over.
    static let boomAt: Double = 0.32
    /// Where the drop sits in `39_skull_boom.mp3`. The Shorts' music is
    /// "Sonne (Best part) (Slowed to perfection)" (youtube.com/watch?v=2aSHYRN3AVU,
    /// found by Shazam + cross-correlation). The clip starts 0.5 s before the
    /// drop (34.94 s, bass only under a 450 Hz low-pass) and runs 3 s past it;
    /// the drop's high-band onset is at 35.44 s. Her sung line before it was
    /// cut on Victor's ask: from the bass drop only. **Re-cutting the clip
    /// means re-measuring this.**
    static let dropInClip: Double = 0.5
    /// How long after the audio's first sample the visual's clock starts, so
    /// that `boomAt` lands on the drop.
    static var visualLead: Double { dropInClip - boomAt }
    /// The whole effect, exit included, from the visual's clock.
    static let totalDuration: Double = 3.7
    /// The skull's exit (a last swell, then it shrinks into the middle).
    static var exitAt: Double { totalDuration - 0.45 }
    /// Keyframe sampling rate. 60 Hz is what the preview was signed off at.
    static let fps: Double = 60

    // MARK: - Geometry (all on the art's 421 px canvas, y DOWN as drawn)

    static let canvas: CGFloat = 421
    /// Where the cranium broke: the blast grows out of this point.
    static let crack = CGPoint(x: 225, y: 163)
    /// The heart of the explosion: the rays and the ghost come from here.
    static let burst = CGPoint(x: 225, y: 230)
    /// The skull is this share of the screen's height.
    static let heightShare: CGFloat = 0.48
    /// The preview frame these pixel constants (shake, …) were tuned on.
    static let referenceWidth: CGFloat = 1280

    // MARK: - The art

    struct Art {
        let whole: CGImage, base: CGImage, jaw: CGImage, blast: CGImage
        let shards: [CGImage]

        static func load(from dir: URL) -> Art? {
            func png(_ name: String) -> CGImage? {
                let url = dir.appendingPathComponent(name)
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(src, 0, nil)
            }
            guard let whole = png("whole.png"), let base = png("base.png"),
                  let jaw = png("jaw.png"), let blast = png("blast.png") else { return nil }
            let shards = (1...9).compactMap { png("shard\($0).png") }
            return Art(whole: whole, base: base, jaw: jaw, blast: blast, shards: shards)
        }
    }

    /// What does not depend on the screen: the art and everything derived
    /// from it. Built once (`warm`) — the drop is only 0.5 s into the clip, and
    /// the capture alone has to fit in that.
    struct Statics {
        let art: Art, ghost: CGImage?, glow: CGImage?, rays: CGImage?, puff: CGImage?
    }

    /// Everything a press needs, the capture-dependent part made per press.
    struct Prepared {
        let shot: CGImage, grey: CGImage?, blurred: CGImage?
        let statics: Statics
        var art: Art { statics.art }
    }

    private static let ci = CIContext(options: [.cacheIntermediates: false])
    private static let cacheLock = NSLock()
    private static var cache: (dir: URL, statics: Statics)?

    /// The statics for the art in `dir`, built on first use and kept. Nil when
    /// the art is missing. Thread-safe; call it off the main thread to warm.
    @discardableResult
    static func statics(for dir: URL) -> Statics? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let c = cache, c.dir == dir { return c.statics }
        guard let art = Art.load(from: dir) else { return nil }
        let built = makeStatics(art)
        cache = (dir, built)
        return built
    }

    private static func makeStatics(_ art: Art) -> Statics {
        let wholeCI = CIImage(cgImage: art.whole)
        let ghost = wholeCI.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
            .cropped(to: wholeCI.extent)
        // The glow: a white silhouette of the skull, padded and blurred.
        let pad: CGFloat = 40
        let silhouette = wholeCI.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ]).applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: wholeCI])
        let glowExtent = wholeCI.extent.insetBy(dx: -pad, dy: -pad)
        let glow = silhouette.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18]).cropped(to: glowExtent)
        return Statics(art: art,
                       ghost: ci.createCGImage(ghost, from: wholeCI.extent),
                       glow: ci.createCGImage(glow, from: glowExtent),
                       rays: makeRays(), puff: makePuff())
    }

    static func prepare(shot: CGImage, statics: Statics) -> Prepared {
        let input = CIImage(cgImage: shot)
        let grey = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        // The zoom blur only shows for ~0.3 s under a white blow-out: half
        // resolution is plenty, and it is the expensive one.
        let half = input.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let blur = half.clampedToExtent().applyingFilter("CIZoomBlur", parameters: [
            kCIInputCenterKey: CIVector(x: half.extent.midX, y: half.extent.midY),
            kCIInputAmountKey: half.extent.width * 0.09,
        ]).cropped(to: half.extent)

        return Prepared(shot: shot,
                        grey: ci.createCGImage(grey, from: input.extent),
                        blurred: ci.createCGImage(blur, from: half.extent),
                        statics: statics)
    }

    // MARK: - Curves (functions of t, seconds from the clock)

    static func clamp(_ x: Double) -> Double { max(0, min(1, x)) }
    static func smoothstep(_ x: Double) -> Double { let x = clamp(x); return x * x * (3 - 2 * x) }
    static func easeOutBack(_ x: Double, _ s: Double = 2.2) -> Double { let x = x - 1; return x * x * ((s + 1) * x + s) + 1 }

    /// Screen shake in reference pixels (y DOWN) and degrees: a tremor growing
    /// with the bass, the big kick on the boom, a faint tremor while it hangs.
    static func shake(_ t: Double) -> (dx: Double, dy: Double, rot: Double) {
        let amp = t < boomAt ? 4 + 6 * t / boomAt
                             : max(70 * exp(-(t - boomAt) / 0.2), 2.5 * clamp((exitAt - t) / 0.8))
        let ph = t * 57
        return (amp * sin(ph * 1.7 + 1.3) * cos(ph * 0.9), amp * sin(ph * 2.3), amp * 0.05 * sin(ph * 1.1))
    }

    /// How long the camera takes to glide back to the real desktop at the end.
    static let settleDuration: Double = 0.8

    /// 0 for most of the effect, rising to 1 over the last `settleDuration`:
    /// how far the camera has come back to the live desktop's framing.
    static func settled(_ t: Double) -> Double {
        smoothstep((t - (totalDuration - settleDuration)) / settleDuration)
    }

    /// The desktop's zoom: a 1.32× punch on the boom, then a slow creep in —
    /// and at the end a gentle glide back to exactly 1×, so the layer leaves
    /// over a picture that matches the real desktop instead of snapping from
    /// ~1.1× to 1× (Victor, 2026-10-08: "must come back to normal zoom gently").
    static func cameraZoom(_ t: Double) -> Double {
        let u = t - boomAt
        let z = u < 0 ? 1 : 1 + 0.32 * exp(-u / 0.16) + 0.07 * smoothstep(u / 3.0)
        return 1 + (z - 1) * (1 - settled(t))
    }

    /// How much of the colour is gone (opacity of the grey copy over the colour one).
    static func drained(_ t: Double) -> Double {
        let u = t - boomAt
        return u < 0 ? 0 : 0.7 * (1 - smoothstep((u - 0.4) / 2.6))
    }

    /// The flat white: the full blow-out on the boom.
    static func whiteFlash(_ t: Double) -> Double {
        let u = t - boomAt
        if u < 0 { return 0 }
        if u < 0.05 { return 1 }
        return exp(-(u - 0.05) / 0.1)
    }

    /// The milky film under the smoke puffs.
    static func milk(_ t: Double) -> Double {
        let u = t - boomAt
        return u < 0 ? 0 : 0.3 * (1 - smoothstep((u - 0.2) / 2.6))
    }

    /// The smoke's rising "clear" threshold: a puff whose density is below it is gone.
    static func smokeThreshold(_ u: Double) -> Double { -0.25 + 1.3 * smoothstep((u - 0.15) / 2.8) }

    /// The skull's exit: (scale factor, opacity).
    static func exit(_ t: Double) -> (scale: Double, alpha: Double) {
        let e = clamp((t - exitAt) / (totalDuration - exitAt))
        guard e > 0 else { return (1, 1) }
        let swell = 1 + 0.12 * sin(Double.pi * min(e, 0.35) / 0.35 * 0.5)
        return (max(swell * (1 - smoothstep((e - 0.3) / 0.7)), 0.001), 1 - smoothstep((e - 0.45) / 0.55))
    }

    // MARK: - The layer

    /// `bounds` is the container's own (zero-origin) rect; `scale` its backing
    /// scale; `clock0` the CoreAnimation time the clip's first sample plays at.
    static func makeLayer(in bounds: CGRect, scale: CGFloat, prepared p: Prepared,
                          clock0: CFTimeInterval) -> CALayer? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let W = bounds.width, H = bounds.height
        let px = Double(W / referenceWidth)        // reference pixels → points
        let side = H * heightShare
        let k = side / canvas
        let skullRect = CGRect(x: (W - side) / 2, y: (H - side) / 2, width: side, height: side)
        // canvas (y down) → container (y up)
        func onScreen(_ c: CGPoint) -> CGPoint { CGPoint(x: skullRect.minX + c.x * k, y: skullRect.maxY - c.y * k) }
        let burstPt = onScreen(burst)

        let container = CALayer()
        container.frame = bounds
        container.masksToBounds = true
        container.contentsScale = scale

        // Black under the desktop, so the shake tears a black edge open the
        // way the edits do, instead of uncovering the live desktop.
        let backdrop = CALayer()
        backdrop.frame = bounds
        backdrop.backgroundColor = NSColor.black.cgColor
        container.addSublayer(backdrop)

        // --- the desktop: colour, grey and zoom-blurred copies on one camera ---
        let camera = CALayer()
        camera.frame = bounds
        container.addSublayer(camera)
        func shotLayer(_ img: CGImage?) -> CALayer {
            let l = CALayer()
            l.frame = bounds
            l.contents = img
            l.contentsGravity = .resizeAspectFill
            l.contentsScale = scale
            camera.addSublayer(l)
            return l
        }
        _ = shotLayer(p.shot)
        let grey = shotLayer(p.grey)
        let blurred = shotLayer(p.blurred)

        let n = Int(totalDuration * fps) + 1
        let times = (0..<n).map { Double($0) / fps }
        func animate(_ layer: CALayer, _ keyPath: String, _ values: [Any], key: String) {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.values = values
            a.keyTimes = times.map { NSNumber(value: $0 / totalDuration) }
            a.calculationMode = .linear
            a.duration = totalDuration
            a.beginTime = clock0
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            layer.add(a, forKey: key)
        }

        animate(camera, "transform", times.map { t -> NSValue in
            // 4% spare so small shakes stay black-free — given back with the zoom.
            let s = shake(t), z = CGFloat(cameraZoom(t) * (1 + 0.04 * (1 - settled(t))))
            var m = CATransform3DMakeTranslation(CGFloat(s.dx * px), CGFloat(-s.dy * px), 0)
            m = CATransform3DRotate(m, CGFloat(s.rot * .pi / 180), 0, 0, 1)
            return NSValue(caTransform3D: CATransform3DScale(m, z, z, 1))
        }, key: "skullBoomCamera")
        animate(grey, "opacity", times.map { NSNumber(value: drained($0)) }, key: "skullBoomGrey")
        animate(blurred, "opacity", times.map { t -> NSNumber in
            let u = t - boomAt
            return NSNumber(value: u < 0 ? 0 : exp(-u / 0.14))
        }, key: "skullBoomBlur")

        // --- white: the milky film, the smoke puffs, the flat flash ---
        let milkLayer = CALayer()
        milkLayer.frame = bounds
        milkLayer.backgroundColor = NSColor.white.cgColor
        container.addSublayer(milkLayer)
        animate(milkLayer, "opacity", times.map { NSNumber(value: milk($0)) }, key: "skullBoomMilk")

        if let puff = p.statics.puff { addSmoke(to: container, puff: puff, bounds: bounds, burst: burstPt, clock0: clock0) }

        let flash = CALayer()
        flash.frame = bounds
        flash.backgroundColor = NSColor.white.cgColor
        container.addSublayer(flash)
        animate(flash, "opacity", times.map { NSNumber(value: whiteFlash($0)) }, key: "skullBoomFlash")

        // --- the rays: white wedges fanning out of the burst, turning slowly ---
        if let rays = p.statics.rays {
            let r = 1.3 * max(W, H)
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
            l.position = burstPt
            l.contents = rays
            container.addSublayer(l)
            animate(l, "opacity", times.map { t -> NSNumber in
                let u = t - boomAt
                guard u >= 0 else { return 0 }
                let env = clamp(u / 0.04) * (1 - smoothstep((u - 0.5) / 1.1))
                return NSNumber(value: 0.92 * env * (0.8 + 0.2 * sin(u * 23)))
            }, key: "skullBoomRays")
            animate(l, "transform.rotation.z", times.map { NSNumber(value: -max(0, $0 - boomAt) * 12 * .pi / 180) },
                    key: "skullBoomRaysTurn")
        }

        // --- the ghost: a blurred copy of the skull that blows outward ---
        if let ghost = p.statics.ghost {
            let l = CALayer()
            l.bounds = CGRect(origin: .zero, size: skullRect.size)
            l.position = CGPoint(x: skullRect.midX, y: skullRect.midY)
            l.contents = ghost
            container.addSublayer(l)
            animate(l, "transform.scale", times.map { (t: Double) -> NSNumber in
                let u: Double = clamp((t - boomAt) / 0.5)
                let grown: Double = 1 - (1 - u) * (1 - u)
                return NSNumber(value: 1 + 3.2 * grown)
            }, key: "skullBoomGhostScale")
            animate(l, "opacity", times.map { t -> NSNumber in
                let u = t - boomAt
                return NSNumber(value: u < 0 ? 0 : 0.75 * (1 - clamp(u / 0.5)))
            }, key: "skullBoomGhostFade")
        }

        // --- the white-hot core where the head bursts ---
        if let puff = p.statics.puff {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 240 * px, height: 240 * px)
            l.position = CGPoint(x: burstPt.x, y: burstPt.y + 40 * px)
            l.contents = puff
            container.addSublayer(l)
            animate(l, "transform.scale", times.map { t -> NSNumber in
                let u = clamp((t - boomAt) / 0.35)
                return NSNumber(value: 0.6 + 2.6 * (1 - pow(1 - u, 3)))
            }, key: "skullBoomCoreScale")
            animate(l, "opacity", times.map { t -> NSNumber in
                let u = t - boomAt
                return NSNumber(value: u < 0 ? 0 : 1 - smoothstep(u / 0.35))
            }, key: "skullBoomCoreFade")
        }

        // --- the exploded skull: one rig scaled about the burst ---
        let rig = CALayer()
        rig.bounds = CGRect(origin: .zero, size: skullRect.size)
        rig.anchorPoint = CGPoint(x: burst.x / canvas, y: 1 - burst.y / canvas)
        rig.position = burstPt
        container.addSublayer(rig)
        animate(rig, "transform", times.map { t -> NSValue in
            let u = max(0, t - boomAt)
            let zk = CGFloat((1 + 0.32 * exp(-u / 0.16)) * exit(t).scale)
            let sh = shake(t)
            let float = 6 * sin(u * 3.2) * clamp(u / 0.6)
            let m = CATransform3DMakeTranslation(CGFloat(sh.dx * px * 0.5), CGFloat(-(sh.dy * 0.5 + float) * px), 0)
            return NSValue(caTransform3D: CATransform3DScale(m, zk, zk, 1))
        }, key: "skullBoomRig")
        animate(rig, "opacity", times.map { NSNumber(value: $0 < boomAt ? 0 : exit($0).alpha) }, key: "skullBoomRigFade")

        if let glow = p.statics.glow {
            let pad = 40 * k
            let l = CALayer()
            l.frame = rig.bounds.insetBy(dx: -pad, dy: -pad)
            l.contents = glow
            rig.addSublayer(l)
            animate(l, "opacity", times.map { t -> NSNumber in
                let u = t - boomAt
                return NSNumber(value: u < 0 ? 0 : (0.35 + 0.25 * sin(u * 7)) * clamp(u / 0.2))
            }, key: "skullBoomGlow")
        }
        func part(_ img: CGImage) -> CALayer {
            let l = CALayer()
            l.frame = rig.bounds
            l.contents = img
            l.contentsScale = scale
            rig.addSublayer(l)
            return l
        }
        let jaw = part(p.art.jaw)
        _ = part(p.art.base)
        let blast = part(p.art.blast)
        // The jaw starts shut and drops open with a bounce.
        animate(jaw, "transform.translation.y", times.map { t -> NSNumber in
            let u = max(0, t - boomAt)
            return NSNumber(value: Double(26 * k) * (1 - easeOutBack(clamp(u / 0.18), 3.0)))
        }, key: "skullBoomJaw")
        // The cloud and its shards grow out of the crack, overshoot, billow on.
        blast.anchorPoint = CGPoint(x: crack.x / canvas, y: 1 - crack.y / canvas)
        blast.frame = rig.bounds
        animate(blast, "transform.scale", times.map { (t: Double) -> NSNumber in
            let u: Double = max(0, t - boomAt)
            let burst: Double = 0.25 + 0.75 * easeOutBack(clamp(u / 0.16), 2.6)
            let billow: Double = 1 + 0.03 * u
            return NSNumber(value: burst * billow)
        }, key: "skullBoomBlast")

        // --- the debris: bone pieces thrown out of the crack under gravity ---
        if !p.art.shards.isEmpty {
            addDebris(to: container, shards: p.art.shards, from: onScreen(crack), k: k, px: px, clock0: clock0)
        }
        // The capture is by now framed exactly like the live desktop; fading it
        // off hides whatever changed on screen while the effect ran.
        let handBack = CABasicAnimation(keyPath: "opacity")
        handBack.fromValue = 1.0
        handBack.toValue = 0.0
        handBack.beginTime = clock0 + totalDuration - 0.2
        handBack.duration = 0.2
        handBack.fillMode = .both
        handBack.isRemovedOnCompletion = false
        container.add(handBack, forKey: "skullBoomHandBack")
        return container
    }

    // MARK: - Smoke

    /// ~40 soft white puffs. Each has a density (noise + nearness to the
    /// burst) and goes when the rising threshold passes it — so the haze
    /// clears in patches, edges first and the middle last — while all of them
    /// drift outward from the burst and swell.
    private static func addSmoke(to container: CALayer, puff: CGImage, bounds: CGRect,
                                 burst: CGPoint, clock0: CFTimeInterval) {
        var rng = SystemRandomNumberGenerator()
        let diag = hypot(bounds.width, bounds.height)
        for _ in 0..<42 {
            let p = CGPoint(x: .random(in: bounds.minX...bounds.maxX, using: &rng),
                            y: .random(in: bounds.minY...bounds.maxY, using: &rng))
            let nearness = 1 - min(1, hypot(p.x - burst.x, p.y - burst.y) / (0.6 * diag))
            let density = 0.55 * Double.random(in: 0...1, using: &rng) + 0.45 * Double(nearness)
            // Solve smokeThreshold(u) == density for the moment this puff is gone.
            var gone = 0.15
            while gone < 3.2 && smokeThreshold(gone) < density { gone += 0.02 }
            let size = bounds.width * .random(in: 0.28...0.5, using: &rng)
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            l.position = p
            l.contents = puff
            l.opacity = 0
            container.addSublayer(l)

            let begin = clock0 + boomAt
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.8, 0.8, 0]
            fade.keyTimes = [0, 0.02, NSNumber(value: max(0.03, (gone - 0.35) / gone)), 1]
            fade.duration = gone
            fade.beginTime = begin
            fade.fillMode = .both
            fade.isRemovedOnCompletion = false
            l.add(fade, forKey: "skullBoomSmoke")

            let drift = CABasicAnimation(keyPath: "position")
            drift.fromValue = NSValue(point: p)
            let out = 1 + 0.22 * gone
            drift.toValue = NSValue(point: CGPoint(x: burst.x + (p.x - burst.x) * out, y: burst.y + (p.y - burst.y) * out))
            drift.duration = gone
            drift.beginTime = begin
            drift.fillMode = .both
            drift.isRemovedOnCompletion = false
            l.add(drift, forKey: "skullBoomSmokeDrift")

            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.85
            grow.toValue = 1.25
            grow.duration = gone
            grow.beginTime = begin
            grow.fillMode = .both
            grow.isRemovedOnCompletion = false
            l.add(grow, forKey: "skullBoomSmokeGrow")
        }
    }

    // MARK: - Debris

    private static func addDebris(to container: CALayer, shards: [CGImage], from origin: CGPoint,
                                  k: CGFloat, px: Double, clock0: CFTimeInterval) {
        let span = 1.1
        let steps = 33
        for _ in 0..<26 {
            let img = shards.randomElement()!
            let s = k * .random(in: 0.45...1.0)
            let ang = Double.random(in: 15...165) * .pi / 180     // upward, y up
            let speed = Double.random(in: 500...1500) * px
            let vx = cos(ang) * speed, vy = sin(ang) * speed
            let g = 2600 * px
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: CGFloat(img.width) * s, height: CGFloat(img.height) * s)
            l.position = origin
            l.contents = img
            l.opacity = 0
            container.addSublayer(l)

            let begin = clock0 + boomAt
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.values = (0...steps).map { i -> NSValue in
                let u = span * Double(i) / Double(steps)
                return NSValue(point: CGPoint(x: origin.x + CGFloat(vx * u), y: origin.y + CGFloat(vy * u - 0.5 * g * u * u)))
            }
            fly.duration = span
            fly.beginTime = begin
            fly.fillMode = .both
            fly.isRemovedOnCompletion = false
            l.add(fly, forKey: "skullBoomDebris")

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            let r0 = Double.random(in: 0...(2 * .pi)), w = Double.random(in: -12...12)
            spin.fromValue = r0
            spin.toValue = r0 + w * span
            spin.duration = span
            spin.beginTime = begin
            spin.fillMode = .both
            spin.isRemovedOnCompletion = false
            l.add(spin, forKey: "skullBoomDebrisSpin")

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, NSNumber(value: 0.5 / span), 1]
            fade.duration = span
            fade.beginTime = begin
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            l.add(fade, forKey: "skullBoomDebrisFade")
        }
    }

    // MARK: - Procedural images

    /// 16 white wedges from the centre of a square, softened.
    static func makeRays(size: Int = 512) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let c = CGFloat(size) / 2
        for _ in 0..<16 {
            let a = CGFloat.random(in: 0...(2 * .pi))
            let hw = CGFloat.random(in: 4...11) / 2 * .pi / 180
            let len = c * .random(in: 0.8...1.0)
            ctx.setFillColor(NSColor(white: 1, alpha: .random(in: 0.65...1)).cgColor)
            ctx.move(to: CGPoint(x: c, y: c))
            ctx.addLine(to: CGPoint(x: c + len * cos(a - hw), y: c + len * sin(a - hw)))
            ctx.addLine(to: CGPoint(x: c + len * cos(a + hw), y: c + len * sin(a + hw)))
            ctx.closePath()
            ctx.fillPath()
        }
        guard let sharp = ctx.makeImage() else { return nil }
        let input = CIImage(cgImage: sharp)
        let soft = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3])
            .cropped(to: input.extent)
        return ci.createCGImage(soft, from: input.extent)
    }

    /// A soft white disc fading to nothing at its rim.
    static func makePuff(size: Int = 256) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(),
                                        colorComponents: [1, 1, 1, 1, 1, 1, 1, 0.55, 1, 1, 1, 0],
                                        locations: [0, 0.45, 1], count: 3) else { return nil }
        let c = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c,
                               endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()
    }
}
