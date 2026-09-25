import AppKit
import QuartzCore

/// The 🫖 that stands in for the pointer while it pours — its layer, where its
/// spout IS, and how far it leans. Geometry only, so the aim can be tested
/// without a screen.
///
/// The spout used to be a hand-measured offset from the pot's centre, and it
/// was wrong: the glyph's tip sits in the UPPER left of its box, not the lower
/// left, so after the tilt the stream left the pot ~30 pt below and right of
/// its tip, and every resize moved the error (2026-09-25). Now the tip is FOUND
/// — the leftmost opaque pixel of the glyph, rendered by the same layer the
/// screen shows — and made the layer's `anchorPoint`: the cursor is the spout,
/// and the pot pivots around it, so no tilt can ever pull the tip off the
/// stream.
enum CoffeePot {

    /// The same text layer the overlay draws, so what is measured is what is
    /// shown.
    static func makeLayer(size: CGFloat, scale: CGFloat) -> CATextLayer {
        let pot = CATextLayer()
        pot.string = "🫖"
        pot.fontSize = size * 0.8
        pot.alignmentMode = .center
        pot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        pot.contentsScale = scale
        return pot
    }

    /// Where the tip and the belly sit in the pot's box, in unit coordinates
    /// (layer space, y up) — ready to be an `anchorPoint`.
    struct Geometry: Equatable {
        var spout: CGPoint
        var belly: CGPoint
        /// Which way the spout points on an untilted pot, belly → tip, radians.
        var spoutAngle: CGFloat {
            atan2(spout.y - belly.y, spout.x - belly.x)
        }
    }

    /// What the glyph looked like when this was written (macOS 15 Apple Color
    /// Emoji, 252 pt box) — used if the render finds nothing.
    static let fallback = Geometry(spout: CGPoint(x: 0.111, y: 0.647),
                                   belly: CGPoint(x: 0.498, y: 0.488))

    /// Render the glyph once and find its tip: the leftmost opaque column (the
    /// spout is the pot's leftmost part), the middle of that column's opaque
    /// run. The belly is the centre of the glyph's opaque bounding box.
    static func measure(size: CGFloat = 252) -> Geometry {
        let w = Int(size)
        guard w > 0,
              let ctx = CGContext(data: nil, width: w, height: w, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return fallback }
        makeLayer(size: size, scale: 1).render(in: ctx)
        guard let raw = ctx.data else { return fallback }
        let px = raw.assumingMemoryBound(to: UInt8.self)
        // Memory row 0 is the TOP of the picture; layer space has y up.
        var minX = w, maxX = -1, minRow = w, maxRow = -1
        var tipRows: [Int] = []
        for x in 0..<w {
            for row in 0..<w where px[row * w * 4 + x * 4 + 3] > 128 {
                if x < minX { minX = x; tipRows = [] }
                if x == minX { tipRows.append(row) }
                maxX = max(maxX, x)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0, !tipRows.isEmpty else { return fallback }
        let tipRow = CGFloat(tipRows[tipRows.count / 2])
        let s = CGFloat(w)
        return Geometry(
            spout: CGPoint(x: CGFloat(minX) / s, y: 1 - tipRow / s),
            belly: CGPoint(x: CGFloat(minX + maxX) / 2 / s, y: 1 - CGFloat(minRow + maxRow) / 2 / s))
    }

    /// How far the pot leans (radians, counter-clockwise) to point its spout
    /// at `cup` from `spout`: the spout's own direction, turned onto the line
    /// to the cup — clamped to `range`, because a cup straight below (or to
    /// the right, under the belly) would otherwise stand the pot on its lid.
    /// A cup right at the tip has no direction; the pot then pours at
    /// `range.upperBound`, straight into it.
    static func aimTilt(spout: CGPoint, cup: CGPoint, spoutAngle: CGFloat,
                        range: ClosedRange<CGFloat>) -> CGFloat {
        let dx = cup.x - spout.x, dy = cup.y - spout.y
        guard dx * dx + dy * dy > 12 * 12 else { return range.upperBound }
        var tilt = atan2(dy, dx) - spoutAngle
        // Into (−π, π]: the lean is the SHORT way round.
        while tilt <= -.pi { tilt += 2 * .pi }
        while tilt > .pi { tilt -= 2 * .pi }
        // A cup behind the pot (tilt past −π/2) would read as "lean back";
        // there is no pouring backwards, so it gets the full forward lean.
        if tilt < -.pi / 2 { return range.upperBound }
        return min(max(tilt, range.lowerBound), range.upperBound)
    }

    /// One tick of the lean easing toward `target` — a pot that snapped to a
    /// new angle 60 times a second would twitch with every pixel of the hand.
    static func ease(_ tilt: CGFloat, toward target: CGFloat, dt: Double,
                     rate: Double = 9) -> CGFloat {
        tilt + (target - tilt) * CGFloat(min(1, max(0, dt * rate)))
    }
}
