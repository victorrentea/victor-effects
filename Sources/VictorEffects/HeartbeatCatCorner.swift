import AppKit
import ImageIO
import QuartzCore

/// 🐶/🐱 Which companion keeps the 💓 heartbeat company on this run.
///
/// The dog (`HeartbeatDogFollow`) and the cat (`HeartbeatCatCorner`) take turns:
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

/// 🐱 Pure geometry for the scared cat that sits out the heartbeat in the
/// **bottom-left corner**. Same bargain as `HeartbeatDogFollow` and
/// `HeartbeatBump`: every decision is a function of the overlay bounds and the
/// image's own aspect, so it can be tested without a screen.
///
/// **The cat is the opposite of the dog on purpose.** The dog is glued to the
/// beat and trots after the cursor; the cat "has no long neck" (Victor,
/// 2026-09-11) and therefore does not follow anything — it is parked in the
/// corner, animating its GIF, and it leaves when the beat does. Nothing here
/// polls the mouse, so there is no timer to cancel: the layer is a sublayer of
/// the tracked heartbeat container and dies with it, which is the whole reason
/// the container exists.
enum HeartbeatCatCorner {

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
    static let scale: CGFloat = 0.7

    /// How far the cat is pushed **below** the floor of the screen, as a fraction
    /// of its own height. The GIF's tail sweeps the bottom of its frame, and a cat
    /// sitting exactly on the edge reads as a sticker laid on the desktop; letting
    /// the tail run off the edge puts it *in* the room instead. The clipping is
    /// the effect, not a bug to clamp away.
    static let sinkFraction: CGFloat = 0.09

    /// Which corner, decided **once** from the cursor at the moment the effect
    /// starts: the cat takes the half the mouse is *not* in, so it never lands
    /// under the pointer — and therefore under the lens the beat is bulging.
    /// Unlike the dog this is never re-evaluated, because the cat never moves.
    static func onRight(cursorX: CGFloat, boundsWidth: CGFloat) -> Bool {
        cursorX < boundsWidth / 2
    }

    /// The cat's frame in overlay coordinates (bottom-origin, y up): aspect-fit
    /// into the quarter-area box, taken down by `scale`, pinned flush to the
    /// chosen corner and sunk by `sinkFraction` of its height. Letterboxing is
    /// spent *away* from that corner — the corner is the placement, the slack is
    /// not.
    static func frame(imageSize: CGSize, in bounds: CGRect, onRight: Bool) -> CGRect {
        let box = CGSize(width: bounds.width * boxWidthFraction,
                         height: bounds.height * boxHeightFraction)
        guard imageSize.width > 0, imageSize.height > 0,
              box.width > 0, box.height > 0 else {
            return CGRect(origin: .zero, size: box)
        }
        let aspect = imageSize.width / imageSize.height
        var w = box.width
        var h = w / aspect
        if h > box.height {
            h = box.height
            w = h * aspect
        }
        w *= scale
        h *= scale
        return CGRect(x: onRight ? bounds.width - w : 0, y: -h * sinkFraction,
                      width: w, height: h)
    }

    /// The GIF's cat faces left-ish out of its own frame, which is what makes the
    /// bottom-left corner the natural one. Standing in the *right* corner it has
    /// to be mirrored about its own centre, so it sits the same way relative to
    /// the corner it is in rather than facing off the edge.
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
    /// The animation loops for as long as the layer lives; it never schedules a
    /// stop of its own, because it has no lifetime of its own. It is a SIBLING of
    /// the captured screen for the dog's reason: `CALayer.filters` apply to a
    /// layer *and its sublayers*, so a cat parented to the capture would bulge
    /// along with every lub-dub.
    static func makeLayer(bounds: CGRect, cursorX: CGFloat) -> CALayer? {
        guard let decoded = decodedFrames(), let first = decoded.frames.first else { return nil }

        let right = onRight(cursorX: cursorX, boundsWidth: bounds.width)
        let box = frame(imageSize: CGSize(width: first.width, height: first.height),
                        in: bounds, onRight: right)
        let layer = CALayer()
        layer.frame = box
        layer.transform = facing(onRight: right)
        layer.contentsGravity = .resizeAspect
        layer.contents = first
        overlayInfo(String(format: "💓 🐱 corner cat: %@ corner, %.0f×%.0f at (%.0f, %.0f)",
                           right ? "bottom-RIGHT (mirrored)" : "bottom-left",
                           box.width, box.height, box.minX, box.minY))

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = decoded.frames
        anim.duration = decoded.duration
        anim.repeatCount = .infinity
        anim.calculationMode = .discrete
        layer.add(anim, forKey: "catFrames")
        return layer
    }
}
