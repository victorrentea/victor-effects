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
}
