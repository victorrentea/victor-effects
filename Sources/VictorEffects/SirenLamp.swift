import AppKit
import QuartzCore

/// 🚨 The rotating red lamp that stands in the bottom-left corner while the
/// siren tile (`02_siren.mp3`) is on. It is the whole alarm overlay: the red
/// vignette around the screen is drawn only when this asset is missing.
///
/// The asset is a 4-frame animated PNG with real alpha: a ceiling beacon GIF
/// flipped upside down so its base sits on the floor, its black background
/// turned into transparency (the glow fades into the desktop instead of a black
/// box), the grey base kept opaque. It came off Pinterest, so it is NOT in this
/// public repo — it lives in `EffectsConfig.assetsDir` like `scared_cat.gif`,
/// and without it the alarm falls back to the red vignette.
///
/// It has no lifetime of its own: it is a layer of the alarm overlay, which is
/// the one deliberate unbounded toggle (`docs/overlay-effects.md`, lifecycle
/// rule) — it goes when `/alarm/stop`, a stop-all, or the next `/alarm/start`
/// takes the overlay down.
enum SirenLamp {

    static let assetName = "siren_lamp.png"

    /// One full turn of the lamp (all four frames, one flash toward the room)
    /// per wail of the siren. Measured on `02_siren.mp3`: 5.17 s holding eight
    /// identical bursts, i.e. 0.647 s each — the loudness envelope repeats so
    /// cleanly that the autocorrelation peaks at 0.87 on that lag.
    static let period: Double = 0.647

    /// Where in its cycle the lamp starts, so the flash frame (the last one,
    /// beam pointing at the room) lands on the LOUD part of each burst rather
    /// than on the silence between two: every burst is loud for its first
    /// ~0.4 s, peaking ~0.15 s in, and the flash frame spans 0.485–0.647 of the
    /// cycle. Starting 0.415 s in puts the flash at 0.07–0.23 s of each wail.
    static let phase: Double = 0.415

    /// The box Victor drew on the screen for it (2026-10-05), as fractions of
    /// the overlay: from 13.9 % to 45 % of the width, the bottom 29.5 % of the
    /// height. Not flush with the left edge — the 🔔 fire alarm (#65) owns that
    /// corner.
    static let boxLeft: CGFloat = 0.139
    static let boxRight: CGFloat = 0.45
    static let boxHeight: CGFloat = 0.295

    /// The lamp's frame inside `bounds` (bottom-origin): aspect-fit into the
    /// box, centred across it, standing on the bottom edge.
    static func frame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let box = CGRect(x: bounds.minX + bounds.width * boxLeft,
                         y: bounds.minY,
                         width: bounds.width * (boxRight - boxLeft),
                         height: bounds.height * boxHeight)
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: box.midX - size.width / 2, y: box.minY, width: size.width, height: size.height)
    }

    private static var cache: (frames: [CGImage], modDate: Date?)?

    private static func decodedFrames() -> [CGImage]? {
        guard let url = EffectsConfig.shared.assetURL(assetName) else { return nil }
        let modDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if let cache = cache, cache.modDate == modDate { return cache.frames }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let frames = (0..<CGImageSourceGetCount(source)).compactMap {
            CGImageSourceCreateImageAtIndex(source, $0, nil)
        }
        guard !frames.isEmpty else { return nil }
        cache = (frames, modDate)
        return frames
    }

    /// The spinning lamp, ready to add — or `nil` when the asset is not in
    /// `assetsDir`, in which case the alarm stays a vignette only. The frame
    /// timing ignores the file's own delays on purpose: the tempo belongs to
    /// the siren, not to whoever exported the GIF.
    static func makeLayer(bounds: CGRect) -> CALayer? {
        guard let frames = decodedFrames(), let first = frames.first else {
            overlayInfo("🚨 \(assetName) not in assetsDir — alarm without the lamp")
            return nil
        }
        let layer = CALayer()
        layer.frame = frame(imageSize: CGSize(width: first.width, height: first.height), in: bounds)
        layer.contentsGravity = .resizeAspect
        layer.contents = first

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = frames
        anim.calculationMode = .discrete
        // Discrete takes one key time more than values: each frame holds an
        // equal quarter of the turn, no cross-fade between beam positions.
        anim.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        anim.duration = period
        anim.repeatCount = .infinity
        anim.timeOffset = phase
        layer.add(anim, forKey: "sirenLampFrames")
        return layer
    }
}
