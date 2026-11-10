import CoreGraphics

/// 🔔 Where the fire-alarm bell of tile #65 (`65_school_bell.mp3`) stands: the
/// box Victor drew on the screen for it (2026-11-04), top-left, moved up out of
/// the bottom-left corner and down from 31 % of the screen width.
enum FireAlarm {

    /// The box as drawn on the 1920 × 1080 overlay, kept as fractions so it
    /// lands on the same spot of a 16:10 Retina.
    static let boxLeft: CGFloat = 104.0 / 1920
    static let boxRight: CGFloat = 481.0 / 1920
    static let boxTop: CGFloat = 102.0 / 1080
    static let boxBottom: CGFloat = 537.0 / 1080

    /// `fire-alarm.gif` is a 400 × 400 canvas with the bell inside it. This is
    /// the union of the bell over all 92 frames, top-origin: it is the BELL that
    /// has to fit the box, or the drawn size would come out 27 % too small.
    static let canvasSide: CGFloat = 400
    static let bell = CGRect(x: 59, y: 47, width: 290, height: 306)

    /// The GIF layer's frame inside `bounds` (bottom-origin): the bell
    /// aspect-fit into the box and centred on it, the transparent margin around
    /// it hanging outside.
    static func frame(in bounds: CGRect) -> CGRect {
        let box = CGRect(x: bounds.minX + bounds.width * boxLeft,
                         y: bounds.minY + bounds.height * (1 - boxBottom),
                         width: bounds.width * (boxRight - boxLeft),
                         height: bounds.height * (boxBottom - boxTop))
        let scale = min(box.width / bell.width, box.height / bell.height)
        return CGRect(x: box.midX - bell.midX * scale,
                      y: box.midY - (canvasSide - bell.midY) * scale,
                      width: canvasSide * scale,
                      height: canvasSide * scale)
    }

    // MARK: - 📢 Sound waves and the shake (Victor, 2026-11-10)

    /// The bell's dome in `fire-alarm.gif`, top-origin canvas units: the red
    /// disc spans x 65…283, y 48…268. The waves are concentric with it.
    static let domeCenter = CGPoint(x: 175, y: 158)
    static let domeRadius: CGFloat = 110

    /// Three arcs a side, out from the dome. They open up-left and up-right
    /// (±45° off the vertical) so the right-hand ones clear the hammer, which
    /// sits level with the dome's centre at x ≈ 320.
    static let waveRadii: [CGFloat] = [134, 161, 188]
    static let waveSpan: CGFloat = 50 * .pi / 180
    /// Angles in the layer's own (bottom-origin, counter-clockwise) frame.
    static let waveDirections: [CGFloat] = [.pi / 4, 3 * .pi / 4]
    static let waveLineWidth: CGFloat = 11

    /// One wave runs from the dome outward in this long; each ring lights
    /// `period / waveRadii.count` after the one inside it.
    static let wavePeriod: Double = 0.6

    /// The shake: a rattle of ±`shakeDegrees` about the bell's middle, one
    /// back-and-forth every `shakeCycle` — a bell being hammered, not swung.
    static let shakeDegrees: CGFloat = 3
    static let shakeCycle: Double = 0.09

    /// The arcs of one ring at `radius`, in a layer `side` points square that
    /// draws the 400-unit canvas (bottom-origin, as CALayer is).
    static func wavePath(radius: CGFloat, side: CGFloat) -> CGPath {
        let k = side / canvasSide
        let c = CGPoint(x: domeCenter.x * k, y: (canvasSide - domeCenter.y) * k)
        let path = CGMutablePath()
        for dir in waveDirections {
            let start = dir - waveSpan / 2
            path.move(to: CGPoint(x: c.x + radius * k * cos(start),
                                  y: c.y + radius * k * sin(start)))
            path.addArc(center: c, radius: radius * k,
                        startAngle: start, endAngle: dir + waveSpan / 2, clockwise: false)
        }
        return path
    }
}
