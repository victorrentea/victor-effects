import CoreGraphics

/// 🧠 Pure geometry for the brain that drives the #15 EKG trace.
///
/// The trace is `ecg_line.png` stretched over the whole overlay and revealed by
/// a mask that grows left → right at a constant speed. So "the brain leaves the
/// green line behind it" means: at every instant the brain sits where the line
/// is being uncovered — x is the mask's edge, y is the line at that x.
///
/// The line is not a function of x on the QRS strokes (one column of the PNG
/// covers ~1000 px of a near-vertical stroke), so `penPath` is not a per-column
/// average: it was traced off the PNG following the run of opaque pixels and
/// keeping the pen at the **leading end** in the direction of travel, inset by
/// half the stroke's thickness so the brain rides the line's centre. Then
/// Ramer–Douglas–Peucker (6 px of the 4400 × 2264 PNG) cut it to the points
/// below. Regenerate it the same way if `ecg_line.png` ever changes.
enum PulseBrain {
    /// The pen's path over the PNG, normalised: x ∈ [0,1] left → right,
    /// y ∈ [0,1] measured from the image's TOP. x is strictly increasing.
    static let penPath: [(x: CGFloat, y: CGFloat)] = [
        (0.0000,0.5530), (0.1509,0.5548), (0.1591,0.5669), (0.1691,0.6178),
        (0.1737,0.6286), (0.1755,0.6275), (0.1846,0.5073), (0.1873,0.4971),
        (0.1919,0.4949), (0.2000,0.5678), (0.2046,0.5802), (0.2164,0.2174),
        (0.2182,0.2042), (0.2219,0.1993), (0.2246,0.5930), (0.2282,0.7910),
        (0.2301,0.8369), (0.2355,0.8453), (0.2455,0.5718), (0.2501,0.4967),
        (0.2537,0.4825), (0.2573,0.4797), (0.2591,0.4825), (0.2655,0.5462),
        (0.2701,0.5577), (0.2728,0.5563), (0.2764,0.5179), (0.2810,0.5117),
        (0.2910,0.5444), (0.2964,0.5524), (0.4128,0.5548), (0.4210,0.5672),
        (0.4310,0.6182), (0.4356,0.6288), (0.4374,0.6275), (0.4465,0.5068),
        (0.4492,0.4971), (0.4537,0.4949), (0.4619,0.5683), (0.4665,0.5802),
        (0.4783,0.2174), (0.4801,0.2042), (0.4837,0.1993), (0.4883,0.7026),
        (0.4910,0.8281), (0.4919,0.8369), (0.4965,0.8449), (0.4983,0.8449),
        (0.5074,0.5722), (0.5119,0.4967), (0.5147,0.4848), (0.5183,0.4801),
        (0.5210,0.4825), (0.5283,0.5506), (0.5338,0.5586), (0.5383,0.5183),
        (0.5429,0.5117), (0.5547,0.5488), (0.5619,0.5532), (1.0000,0.5519)
    ]

    /// Glyph size, as a fraction of the overlay's height — the spikes swing over
    /// ~65 % of it, so a ~10 % brain reads as the thing drawing, not a dot on it.
    static let sizeRatio: CGFloat = 0.10

    static func fontSize(in bounds: CGRect) -> CGFloat {
        max(24, bounds.height * sizeRatio)
    }

    /// Keyframes for a linear `position` animation that spans the whole reveal.
    /// The mask's edge is at `t · width` (linear timing), so a point's key time
    /// is just its x. The overlay layer is bottom-origin, the PNG top-origin,
    /// hence the flip.
    static func keyframes(in bounds: CGRect) -> (positions: [CGPoint], keyTimes: [Double]) {
        let positions = penPath.map {
            CGPoint(x: bounds.minX + $0.x * bounds.width,
                    y: bounds.minY + (1 - $0.y) * bounds.height)
        }
        return (positions, penPath.map { Double($0.x) })
    }
}
