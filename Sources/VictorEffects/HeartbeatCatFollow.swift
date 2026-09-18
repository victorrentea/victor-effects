import AppKit
import ImageIO
import QuartzCore

/// 🐶/🐱 Which companion keeps the 💓 heartbeat company on this run.
///
/// The dog (`HeartbeatDogFollow`) and the cat (`HeartbeatCatFollow`) take turns:
/// run 1 the dog, run 2 the cat, run 3 the dog again. In memory only — a restart
/// starting over at the dog is not worth a `UserDefaults` key (Victor,
/// 2026-09-11), and the alternation exists so the same tile stops being the same
/// joke twice, not as a setting anybody tunes.
///
/// **This is the only place the choice is made.** `showHeartbeat` asks once and
/// does what it is told; the fallback when the cat's asset is missing lives at
/// that one call site too.
enum HeartbeatCompanion {
    enum Choice { case dog, cat }

    /// Seeded to `.cat` so the very first `next()` answers `.dog` — the dog is
    /// the original and stays the one a cold start shows.
    private static var previous: Choice = .cat

    static func next() -> Choice {
        previous = (previous == .dog) ? .cat : .dog
        return previous
    }

    /// Tests (and only tests) need to start from a known phase.
    static func resetForTesting() { previous = .cat }
}

/// 🐱 Pure geometry for the scared cat that keeps the heartbeat company **from
/// the floor of the screen, beside the beat**. Same bargain as
/// `HeartbeatDogFollow` and `HeartbeatBump`: every decision is a function of the
/// overlay bounds and the image's own aspect, so it can be tested without a
/// screen.
///
/// **It was `HeartbeatCatCorner` until 2026-09-14**, and the rename is the
/// history. The cat arrived on 2026-09-11 as the dog's opposite — it "has no
/// long neck", so it did not follow anything, it was parked in the far bottom
/// corner for the whole beat. Two asks later that is all gone: it slid toward
/// the beat, and then Victor asked for it to **translate the way the dog does**
/// and to **keep a similar distance to the beat**. So the cat now polls the
/// mouse like the dog (`watchHeartbeatCat`) and this file computes the same
/// circle the dog stands on — what is left of "no long neck" is only that the
/// cat stays flat on the floor instead of riding up to the cursor's height.
///
/// The one thing that survives from the corner era: the side is still chosen
/// once, at the first poll, and never re-decided — the dog's 2026-09-09 lesson
/// (a companion leaping across the beat mid-effect reads as a glitch).
enum HeartbeatCatFollow {

    /// The asset, expected in `EffectsConfig.assetsDir` — a downloaded GIF, so
    /// it is deliberately **not in this repo** (same rule as `brother_full.gif`).
    /// Missing ⇒ the heartbeat quietly shows the dog instead.
    static let assetName = "scared_cat.gif"

    /// The box the cat is fitted into: **a quarter of the screen's area**, i.e.
    /// half the width by half the height. The GIF keeps its aspect ratio inside
    /// that box, so it fills one dimension and falls short on the other.
    static let boxWidthFraction: CGFloat = 0.5
    static let boxHeightFraction: CGFloat = 0.5

    /// Taken off the aspect-fit afterwards (Victor, 2026-09-11): the quarter-area
    /// box put a cat 690 pt wide in the corner, which read as the subject rather
    /// than as company for the beat — the dog's own lesson (`heartbeatDogScale`),
    /// learned again one screen-corner over. 0.7 brings it to ~483 × 344.
    ///
    /// It spent a few minutes at 1.4 on 2026-09-14 ("de două ori mai mare") and
    /// came straight back ("și să fie totuși 2x mai mică"): at 1.4 the cat was
    /// 1098 pt wide on the built-in panel, which cannot both stay on screen and
    /// stay off the lens — a companion that large stops being company. **The
    /// follow is what the size was really buying**: a cat that walks over to the
    /// beat does not need to be huge to be near it. Same linear unit as every
    /// "twice as big" in this effect — see `HeartbeatBump.diameterFraction`.
    ///
    /// **1.5× on 2026-09-19** (Victor: "make the cat one point five X larger"),
    /// so 0.7 → 1.05 and the cat draws ~724 × 516 instead of ~483 × 344. That is
    /// deliberately short of the 1.4 that was rejected: it is the same linear
    /// unit, and half way there is where a cat still reads as company rather than
    /// as the subject. What makes the extra size affordable now is the live
    /// re-capture — the screen under the cat keeps moving, so a bigger silhouette
    /// no longer covers a frozen picture.
    static let scale: CGFloat = 1.05

    /// How far the cat is pushed **below** the floor of the screen, as a fraction
    /// of its own height. The GIF's tail sweeps the bottom of its frame, and a cat
    /// sitting exactly on the edge reads as a sticker laid on the desktop; letting
    /// the tail run off the edge puts it *in* the room instead. The clipping is
    /// the effect, not a bug to clamp away.
    static let sinkFraction: CGFloat = 0.09

    /// Which side of the beat, decided **once** at the first poll: the cat takes
    /// the half the mouse is *not* in, so it leans in from the roomy side instead
    /// of standing on the pointer. Never re-evaluated afterwards, for the dog's
    /// reason — the cat is mirrored per side, so a mid-effect switch would be a
    /// cat flipping and teleporting across the beat in one frame.
    static func onRight(cursorX: CGFloat, boundsWidth: CGFloat) -> Bool {
        cursorX < boundsWidth / 2
    }

    /// The radius of the circle the cat's near top corner stands on — **the
    /// dog's own circle**, `(lens radius + clearMargin) × closeness`, borrowed
    /// whole rather than copied so the two companions cannot drift apart. That is
    /// what "a similar distance to the dog's" (Victor, 2026-09-14) means here:
    /// not a similar *gap*, the identical rule. Under the lens radius on purpose
    /// — `closeness` pulls the silhouette 30 % inside the strict clearance, and
    /// the overlap costs nothing because the outer ring of a `CIBumpDistortion`
    /// barely moves a pixel.
    static func nearGap(in bounds: CGRect) -> CGFloat {
        (HeartbeatBump.radius(in: bounds) + HeartbeatDogFollow.clearMargin)
            * HeartbeatDogFollow.closeness
    }

    /// The cat's bottom edge: always sunk, never lifted. The vertical is not a
    /// decision at all — it is the one thing the cat does *not* copy from the dog
    /// (whose face rides at the cursor's height), because Victor pinned it on
    /// 2026-09-14: "rămâne pe partea de jos a ecranului".
    static func originY(height h: CGFloat) -> CGFloat { -h * sinkFraction }

    /// The top of the cat's box, i.e. how high its near corner reaches. This is
    /// the point the clearance circle is measured to — the same choice the dog
    /// makes with its ear tip.
    static func topY(height h: CGFloat) -> CGFloat { h * (1 - sinkFraction) }

    /// The cat's left edge, for a cat of size `size`, with the beat at `cursor`.
    ///
    /// The dog's trade, applied to a cat: **standing below the beat already pays
    /// part of the clearance**, so only the leftover has to be paid sideways.
    /// A beat high on the screen therefore lets the cat walk in almost directly
    /// underneath it, and a beat down near the floor pushes it out to the full
    /// `nearGap` — which is exactly how the dog behaves, and the reason the two
    /// now read as the same effect with a different animal in it.
    ///
    /// Where the two part company is the failure case: the dog may hang its rump
    /// off the edge rather than give up the distance, the cat may not. **The
    /// frame wins** — a tail clipped by the floor reads as a cat in the room, a
    /// body clipped by the side edge reads as half a cat. Since the cat came back
    /// down to `scale` 0.7 there is room for both on any real screen.
    static func originX(size: CGSize, in bounds: CGRect,
                        onRight: Bool, cursor: CGPoint) -> CGFloat {
        let want = nearGap(in: bounds)
        // How far the near corner has dropped below the beat. Clamped at zero:
        // while the cat's top is above the cursor, its near edge spans the
        // cursor's own height and none of that separation is real clearance.
        let below = max(0, cursor.y - topY(height: size.height))
        let sidestep = (max(0, want * want - below * below)).squareRoot()
        return onRight ? min(bounds.width - size.width, cursor.x + sidestep)
                       : max(0, cursor.x - sidestep - size.width)
    }

    /// The size the GIF is drawn at: aspect-fit into the quarter-area box, then
    /// `scale`. Split out from `frame` because the follow needs it once, at
    /// build time, and then re-positions a layer whose size never changes.
    static func size(imageSize: CGSize, in bounds: CGRect) -> CGSize {
        let box = CGSize(width: bounds.width * boxWidthFraction,
                         height: bounds.height * boxHeightFraction)
        guard imageSize.width > 0, imageSize.height > 0,
              box.width > 0, box.height > 0 else { return box }
        let aspect = imageSize.width / imageSize.height
        var w = box.width
        var h = w / aspect
        if h > box.height {
            h = box.height
            w = h * aspect
        }
        return CGSize(width: w * scale, height: h * scale)
    }

    /// Where the layer's `position` (its centre) goes for a given beat — what
    /// `watchHeartbeatCat` slides to on every poll. The mirror in `facing` is a
    /// scale about the layer's own centre, so it leaves this untouched.
    static func position(size: CGSize, in bounds: CGRect,
                         onRight: Bool, cursor: CGPoint) -> CGPoint {
        CGPoint(x: originX(size: size, in: bounds, onRight: onRight, cursor: cursor) + size.width / 2,
                y: originY(height: size.height) + size.height / 2)
    }

    /// The cat's frame in overlay coordinates (bottom-origin, y up): `size`,
    /// placed by `originX` beside the beat and sunk by `sinkFraction`.
    static func frame(imageSize: CGSize, in bounds: CGRect,
                      onRight: Bool, cursor: CGPoint) -> CGRect {
        let s = size(imageSize: imageSize, in: bounds)
        guard imageSize.width > 0, imageSize.height > 0, s.width > 0, s.height > 0 else {
            return CGRect(origin: .zero, size: s)
        }
        return CGRect(x: originX(size: s, in: bounds, onRight: onRight, cursor: cursor),
                      y: originY(height: s.height), width: s.width, height: s.height)
    }

    /// The GIF's cat faces left-ish out of its own frame, which is what makes the
    /// left of the screen the natural side. Placed to the *right* of the beat it
    /// has to be mirrored about its own centre, so it sits the same way relative
    /// to the edge it came from rather than facing off it.
    static func facing(onRight: Bool) -> CATransform3D {
        onRight ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }

    // MARK: - The layer

    /// Decoded once per file modification date. The heartbeat builds this layer
    /// on the main thread right after the screen capture returns, which is the
    /// worst possible moment for a 30-frame decode — so every run after the
    /// first pays nothing.
    private static var cache: (frames: [CGImage], duration: Double, modDate: Date?)?

    private static func decodedFrames() -> (frames: [CGImage], duration: Double)? {
        guard let url = EffectsConfig.shared.assetURL(assetName) else { return nil }
        let modDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if let cache = cache, cache.modDate == modDate {
            return (cache.frames, cache.duration)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [CGImage] = []
        var duration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            duration += gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.1
        }
        guard !frames.isEmpty, duration > 0 else { return nil }

        cache = (frames, duration, modDate)
        return (frames, duration)
    }

    /// The cat, ready to be added to the heartbeat container — or `nil` when the
    /// GIF is not in `assetsDir`, which is the caller's cue to show the dog.
    ///
    /// Hands back the **side** along with the layer: it is baked into the mirror
    /// here, so `watchHeartbeatCat` has to be told rather than allowed to ask
    /// again. The cat is placed from this same cursor before its first frame, so
    /// the follow timer never has to slide it in from somewhere nobody saw.
    ///
    /// The GIF animation loops for as long as the layer lives; it never schedules
    /// a stop of its own, because it has no lifetime of its own. It is a SIBLING
    /// of the captured screen for the dog's reason: `CALayer.filters` apply to a
    /// layer *and its sublayers*, so a cat parented to the capture would bulge
    /// along with every lub-dub.
    static func makeLayer(bounds: CGRect, cursor: CGPoint) -> (layer: CALayer, onRight: Bool)? {
        guard let decoded = decodedFrames(), let first = decoded.frames.first else { return nil }

        let right = onRight(cursorX: cursor.x, boundsWidth: bounds.width)
        let box = frame(imageSize: CGSize(width: first.width, height: first.height),
                        in: bounds, onRight: right, cursor: cursor)
        let layer = CALayer()
        // Order matters: `frame` is only well defined while the transform is
        // identity, so the mirror goes on after. It scales about the layer's own
        // centre, which leaves the box it was just given alone.
        layer.frame = box
        layer.transform = facing(onRight: right)
        layer.contentsGravity = .resizeAspect
        layer.contents = first
        overlayInfo(String(format: "💓 🐱 cat: %@ of the beat, %.0f×%.0f at (%.0f, %.0f)",
                           right ? "RIGHT (mirrored)" : "left",
                           box.width, box.height, box.minX, box.minY))

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = decoded.frames
        anim.duration = decoded.duration
        anim.repeatCount = .infinity
        anim.calculationMode = .discrete
        layer.add(anim, forKey: "catFrames")
        return (layer, right)
    }
}
