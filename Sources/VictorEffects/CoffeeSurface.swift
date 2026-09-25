import AppKit
import QuartzCore

/// Where the coffee IS inside a ☕: the height of the liquid's surface in the
/// glyph, so the pot's stream can end ON it instead of running through the
/// cup and out of its bottom (2026-09-25 — Victor: "it's very hard to stop the
/// coffee stream at the coffee surface").
///
/// Measured, not hand-set, for the same reason the pot's spout is
/// (`CoffeePot.measure`): the glyph is drawn by the system emoji font, and a
/// number typed in from one macOS release is a number that drifts on the next.
/// The coffee is the only dark band in the upper half of the picture (the cup
/// and saucer are white china), so the surface is the middle of the rows that
/// carry a real run of dark-brown pixels.
enum CoffeeSurface {

    /// What the glyph looked like when this was written (macOS 15 Apple Color
    /// Emoji, 78 pt in the 91 pt box): the dark band spans rows 34–46 from the
    /// top, so its middle sits ≈5 pt above the box's centre. Used if the render
    /// finds nothing (a configured `chargeEmoji` with no coffee in it).
    static let fallback: CGFloat = 0.055

    /// The surface's height above the box's centre, as a fraction of the box
    /// (layer space, y up), for `emoji` drawn the way the overlay draws a cup:
    /// a centred `CATextLayer` at `fontSize` in a `box`-wide square.
    static func measure(emoji: String = "☕", box: CGFloat = 91, fontSize: CGFloat = 78) -> CGFloat {
        let scale = 2
        let w = Int(box) * scale
        guard w > 0,
              let ctx = CGContext(data: nil, width: w, height: w, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return fallback }
        let layer = CATextLayer()
        layer.string = emoji
        layer.fontSize = fontSize
        layer.alignmentMode = .center
        layer.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        layer.contentsScale = CGFloat(scale)
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        layer.render(in: ctx)
        guard let raw = ctx.data else { return fallback }
        let px = raw.assumingMemoryBound(to: UInt8.self)

        // Dark, warm, opaque pixels per row — upper half only: the saucer's
        // shadow and the handle's inside are dark too, but lower down.
        var perRow = [Int](repeating: 0, count: w / 2)
        for row in 0..<(w / 2) {
            for x in 0..<w {
                let i = row * w * 4 + x * 4
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2]), a = Int(px[i + 3])
                if a > 200, r + g + b < 240, r > b { perRow[row] += 1 }
            }
        }
        guard let widest = perRow.max(), widest >= 4 * scale else { return fallback }
        // The band: rows at least a quarter as wide as the widest (drops the
        // stray pixels of the steam and the rim's anti-aliasing).
        let band = perRow.indices.filter { perRow[$0] * 4 >= widest }
        guard let top = band.first, let bottom = band.last else { return fallback }
        let middleFromTop = CGFloat(top + bottom + 1) / 2 / CGFloat(scale)
        return (box / 2 - middleFromTop) / box
    }

    /// The surface's y on screen for a cup whose box is centred at `centerY`,
    /// `box` wide at scale 1 and drawn at `scale` (the carrier's growth times
    /// the glyph's). The glyph scales about its centre, so the surface climbs
    /// as the cup swells under the pot.
    static func surfaceY(centerY: CGFloat, box: CGFloat, scale: CGFloat, lift: CGFloat) -> CGFloat {
        centerY + lift * box * scale
    }
}
