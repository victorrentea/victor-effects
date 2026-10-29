import AppKit

/// 🐕 Tile #44's barking dog (`44_small_dog.mp3`): where he stands and when he
/// jumps.
///
/// The dog is Maresch&Sturm's "Basti is barking" (Dribbble), cut out with a
/// BiRefNet matte per frame and **re-timed to this clip**: his mouth opens on
/// every one of its ten barks (onsets measured from the clip's RMS on a 20 ms
/// grid). The GIF lasts the clip's 5.05 s, so it must never be looped or
/// stretched: frame time is the sync. It lives in `assetsDir`, not in this repo.
/// The jump is NOT in the GIF — baked in, every frame became a different
/// picture and the decoded GIF ~170 MB; here it is one keyframe animation over
/// the same `barks`, started on the same clock as the frames.
enum SmallDogBark {

    struct Bark: Equatable {
        /// Seconds into the clip, on the 20 ms grid the GIF was cut on.
        let start: Double
        let end: Double
        /// √(peak RMS / loudest bark's): how high this one jumps, 0…1.
        let strength: Double
    }

    /// Measured from `44_small_dog.mp3` by the same script that re-timed the
    /// GIF (RMS > 1300 on 16 kHz mono, 20 ms steps, gaps ≤ 20 ms merged).
    static let barks: [Bark] = [
        Bark(start: 0.22, end: 0.34, strength: 0.83),
        Bark(start: 0.44, end: 0.58, strength: 0.88),
        Bark(start: 0.74, end: 0.88, strength: 0.86),
        Bark(start: 1.06, end: 1.08, strength: 0.35),
        Bark(start: 1.20, end: 1.24, strength: 0.52),
        Bark(start: 2.62, end: 2.74, strength: 0.90),
        Bark(start: 3.08, end: 3.22, strength: 0.93),
        Bark(start: 3.42, end: 3.48, strength: 0.59),
        Bark(start: 3.60, end: 3.74, strength: 0.94),
        Bark(start: 4.24, end: 4.36, strength: 1.00),
    ]

    /// The loudest bark lifts him this share of his own height. Was 0.12;
    /// Victor cut it to 30 % of that on 2026-10-29, once the hops were slow.
    static let jumpFraction: CGFloat = 0.036

    /// Height of the dog as a share of the screen's — the box Victor marked on
    /// screen (1072 of 2234 px), the same 48 % the 🐺 wolf stands in.
    static let heightFraction: CGFloat = 0.48

    /// Gap between the dog and the left edge, as a share of the width — the
    /// wolf's 4 %. Bottom-LEFT (Victor, 2026-10-26, after a first try on the
    /// right): the dog faces right, so from this corner he barks into the
    /// desktop instead of at the screen's edge.
    static let leftInsetFraction: CGFloat = 0.04

    /// The dog's frame in overlay coordinates (bottom-origin, y up): feet on
    /// the bottom edge, left side 4 % in from the left edge, the GIF's aspect.
    static func frame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let h = bounds.height * heightFraction
        let w = imageSize.height > 0 ? h * imageSize.width / imageSize.height : h
        return CGRect(x: bounds.minX + bounds.width * leftInsetFraction,
                      y: bounds.minY, width: w, height: h)
    }

    /// Shortest time a hop spends in the air. A bark lasts 40–140 ms, and a hop
    /// that long (the first version) threw him up and down five times in a
    /// second — dizzying on a projector. Same height, slower (Victor,
    /// 2026-10-29): every hop now takes at least this long, centred on its
    /// bark, so the rise and the fall are 2.5–5× gentler. In a volley the hops
    /// overlap and the higher one wins, so he stays up and bobs instead of
    /// slamming back to the floor between barks.
    static let minAirtime: Double = 0.45

    /// The lift (0…1 of `jumpFraction`) every 20 ms over the clip: a half-sine
    /// per bark, apex on the bark's middle, at least `minAirtime` wide (wider
    /// if the bark itself is), scaled by the bark's strength.
    static func jumpCurve(duration: Double, step: Double = 0.02) -> (times: [Double], lift: [Double]) {
        let n = Int((duration / step).rounded(.up))
        var lift = [Double](repeating: 0, count: n + 1)
        for bark in barks {
            let airtime = max(minAirtime, bark.end - bark.start + 2 * step)
            let takeoff = (bark.start + bark.end) / 2 - airtime / 2
            let a = max(Int((takeoff / step).rounded(.up)), 0)
            let b = min(Int(((takeoff + airtime) / step).rounded(.down)), n)
            guard b > a else { continue }
            for i in a...b {
                let phase = (Double(i) * step - takeoff) / airtime
                lift[i] = max(lift[i], bark.strength * sin(.pi * phase))
            }
        }
        let times = (0...n).map { min(Double($0) * step, duration) }
        return (times, lift)
    }
}
