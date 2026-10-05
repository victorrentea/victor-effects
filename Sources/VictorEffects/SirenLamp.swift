import AppKit
import QuartzCore

/// 🚨 The rotating red lamp that stands on the bottom edge, left of centre,
/// for the length of tile 63's air horn (`63_air_horn.mp3`). It was built for
/// the siren (#2) first; Victor kept #2 as the plain red vignette and moved the
/// lamp here (2026-10-05).
///
/// The asset is a 4-frame animated PNG with real alpha: a ceiling beacon GIF
/// flipped upside down so its base sits on the floor, its black background
/// turned into transparency (the glow fades into the desktop instead of a black
/// box), the grey base kept opaque. It came off Pinterest, so it is NOT in this
/// public repo — it lives in `EffectsConfig.assetsDir` like `scared_cat.gif`,
/// and without it the press logs one line and the horn plays alone.
enum SirenLamp {

    static let assetName = "siren_lamp.png"

    static let soundName = "63_air_horn.mp3"

    /// The clip's measured length, for when the mp3 cannot be read: the lamp
    /// lives exactly as long as the horn (`trackEffect`, the lifecycle rule).
    static let fallbackDuration: Double = 6.19

    /// One full turn of the lamp (all four frames, one flash toward the room)
    /// per 0.647 s. Tuned on `02_siren.mp3` when the lamp lived there: 5.17 s
    /// holding eight identical bursts. The air horn has no beat of its own to
    /// follow, so the lamp keeps the tempo of a real siren.
    static let period: Double = 0.647

    /// Where in its cycle the lamp starts: 0.415 s in puts the flash frame (the
    /// last one, beam pointing at the room) at 0.07–0.23 s of each turn — on
    /// the loud part of a siren burst, from when it lived on #2.
    static let phase: Double = 0.415

    /// The box Victor drew on the screen for it (2026-10-05, for the siren), as fractions of
    /// the overlay: from 13.9 % to 45 % of the width, the bottom 29.5 % of the
    /// height. Not flush with the left edge — the 🔔 fire alarm (#65) owns that
    /// corner.
    static let boxLeft: CGFloat = 0.139
    static let boxRight: CGFloat = 0.45
    static let boxHeight: CGFloat = 0.295

    /// 1.7× the size that fits that box: Victor asked for 2× ("2x larger"),
    /// saw it, and took 15 % back ("-15% mărime"). It grows about the box's
    /// centre line, so it still sits over the spot that was drawn.
    static let growth: CGFloat = 1.7

    /// Then a nudge left, as a fraction of the screen width (Victor: "puțin mai
    /// la stânga"). The glow on the left may run off the glass; the lamp itself
    /// stays well inside.
    static let nudgeLeft: CGFloat = 0.05

    /// How much of the image is glow BELOW the base: the opaque grey base ends
    /// on row 222 of the 301-row asset, and the 78 rows under it are light
    /// spilling onto the floor. The frame is pushed down by that much so the
    /// base itself sits on the bottom edge of the screen and the spill goes
    /// off the glass, instead of the lamp hovering a quarter of its height up.
    static let belowBaseFraction: CGFloat = 78.0 / 301.0

    /// The lamp's frame inside `bounds` (bottom-origin): aspect-fit into the
    /// box, grown by `growth`, centred across the box then nudged left, its BASE on the bottom
    /// edge (the frame starts below the screen by `belowBaseFraction`).
    static func frame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let box = CGRect(x: bounds.minX + bounds.width * boxLeft,
                         y: bounds.minY,
                         width: bounds.width * (boxRight - boxLeft),
                         height: bounds.height * boxHeight)
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height) * growth
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: box.midX - bounds.width * nudgeLeft - size.width / 2,
                      y: box.minY - size.height * belowBaseFraction,
                      width: size.width, height: size.height)
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
    /// `assetsDir`, in which case the horn plays alone. The frame
    /// timing ignores the file's own delays on purpose: the tempo belongs to
    /// the siren, not to whoever exported the GIF.
    static func makeLayer(bounds: CGRect) -> CALayer? {
        guard let frames = decodedFrames(), let first = frames.first else {
            overlayInfo("🚨 \(assetName) not in assetsDir — the air horn plays without the lamp")
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
