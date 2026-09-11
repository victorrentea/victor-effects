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
    /// half the width by half the height, in the bottom-left corner. The GIF
    /// keeps its aspect ratio inside that box, so it fills one dimension and
    /// falls short on the other.
    static let boxWidthFraction: CGFloat = 0.5
    static let boxHeightFraction: CGFloat = 0.5

    /// The cat's frame in overlay coordinates (bottom-origin, y up), aspect-fit
    /// into the bottom-left quarter-area box and pinned to the corner: flush to
    /// the left edge and standing on the floor of the screen. Letterboxing is
    /// spent upward/rightward — away from the corner — because the corner is the
    /// placement and the slack is not.
    static func frame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
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
        return CGRect(x: 0, y: 0, width: w, height: h)
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
    static func makeLayer(bounds: CGRect) -> CALayer? {
        guard let decoded = decodedFrames(), let first = decoded.frames.first else { return nil }

        let layer = CALayer()
        layer.frame = frame(imageSize: CGSize(width: first.width, height: first.height), in: bounds)
        layer.contentsGravity = .resizeAspect
        layer.contents = first

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = decoded.frames
        anim.duration = decoded.duration
        anim.repeatCount = .infinity
        anim.calculationMode = .discrete
        layer.add(anim, forKey: "catFrames")
        return layer
    }
}
