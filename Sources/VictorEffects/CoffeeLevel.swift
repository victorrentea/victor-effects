import AppKit
import QuartzCore

/// ☕ How full the cup LOOKS (2026-09-29 — Victor: "make the coffee cups get
/// filled progressively as I pour"). The glyph is a full cup, so a cup that
/// only swelled under the pot read as "already full, getting bigger". Now a
/// cup rises EMPTY — the coffee's ellipse is painted over with the china of
/// the cup's inside — and the pot fills it: the liquid comes up from the
/// bottom, small and low, widening and climbing until at `fill == 1` it is
/// the glyph's own coffee, pixel for pixel, and the overlay is gone.
///
/// Where the coffee is, and what it looks like, is MEASURED from the glyph
/// (the same rule `CoffeeSurface` uses for the stream) — nothing is typed in
/// from one macOS release's emoji font. The liquid is the glyph's own coffee
/// pixels, cropped, so the last frame of the fill matches the real cup.
enum CoffeeInterior {

    /// The coffee's ellipse inside the glyph box (layer space, y up) and its
    /// pixels, or nil for a glyph with no coffee in it — which then just
    /// swells, as before.
    struct Shape {
        let rect: CGRect
        let coffee: CGImage
    }

    /// How far below the full level the liquid sits in an empty cup, as a
    /// fraction of the ellipse's height. The front rim hides a low surface,
    /// which is exactly what a nearly empty cup looks like from above.
    static let emptyDrop: CGFloat = 0.55
    /// An empty cup's surface is this much of the full one's width (the cup
    /// narrows toward its bottom).
    static let emptyWidth: CGFloat = 0.6

    static func measure(emoji: String = "☕", box: CGFloat = 91, fontSize: CGFloat = 78) -> Shape? {
        let scale = 4
        let w = Int(box) * scale
        guard w > 0,
              let ctx = CGContext(data: nil, width: w, height: w, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let layer = CATextLayer()
        layer.string = emoji
        layer.fontSize = fontSize
        layer.alignmentMode = .center
        layer.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        layer.contentsScale = CGFloat(scale)
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        layer.render(in: ctx)
        guard let raw = ctx.data, let image = ctx.makeImage() else { return nil }
        let px = raw.assumingMemoryBound(to: UInt8.self)

        // Dark, warm, opaque pixels, upper half only — `CoffeeSurface`'s rule.
        var left = [Int](repeating: Int.max, count: w / 2)
        var right = [Int](repeating: -1, count: w / 2)
        var perRow = [Int](repeating: 0, count: w / 2)
        for row in 0..<(w / 2) {
            for x in 0..<w {
                let i = row * w * 4 + x * 4
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2]), a = Int(px[i + 3])
                guard a > 200, r + g + b < 240, r > b else { continue }
                perRow[row] += 1
                left[row] = min(left[row], x)
                right[row] = max(right[row], x)
            }
        }
        guard let widest = perRow.max(), widest >= 4 * scale else { return nil }
        let band = perRow.indices.filter { perRow[$0] * 4 >= widest }
        guard let top = band.first, let bottom = band.last else { return nil }
        let minX = band.map { left[$0] }.min()!, maxX = band.map { right[$0] }.max()!

        // Pixels (row 0 at the top) → points, grown by a point all round so
        // the rim's anti-aliasing is under the paint too.
        let pad = 1 * scale
        let pxRect = CGRect(x: minX - pad, y: top - pad,
                            width: maxX - minX + 1 + 2 * pad, height: bottom - top + 1 + 2 * pad)
        guard let crop = image.cropping(to: pxRect),
              let coffee = ellipse(crop, inset: CGFloat(pad)) else { return nil }
        let s = CGFloat(scale)
        let rect = CGRect(x: pxRect.minX / s, y: box - pxRect.maxY / s,
                          width: pxRect.width / s, height: pxRect.height / s)
        return Shape(rect: rect, coffee: coffee)
    }

    /// Just the liquid: the crop's corners are the cup's white rim, which a
    /// shrunk surface low in the cup must not carry down with it.
    private static func ellipse(_ image: CGImage, inset: CGFloat) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.addEllipse(in: full.insetBy(dx: inset, dy: inset))
        ctx.clip()
        ctx.draw(image, in: full)
        return ctx.makeImage()
    }

    /// Where the liquid's ellipse sits inside the coffee rect at `fill`
    /// (0…1), in the rect's own coordinates (y up): full = the rect itself;
    /// emptier = narrower and lower, down behind the front rim.
    static func liquidFrame(in size: CGSize, fill: CGFloat) -> CGRect {
        let f = min(1, max(0, fill))
        let k = emptyWidth + (1 - emptyWidth) * f
        let w = size.width * k, h = size.height * k
        let cy = size.height / 2 - (1 - f) * emptyDrop * size.height
        return CGRect(x: (size.width - w) / 2, y: cy - h / 2, width: w, height: h)
    }

    /// How far the surface sits below the full level at `fill`, as a
    /// fraction of the glyph box — the stream ends on the liquid, not in the
    /// air above an empty cup.
    static func surfaceDrop(rectHeight: CGFloat, box: CGFloat, fill: CGFloat) -> CGFloat {
        (1 - min(1, max(0, fill))) * emptyDrop * rectHeight / box
    }
}

/// The layers that paint one cup's fill level, inside its glyph (so they
/// swell, shake and fly with it). The china covers the glyph's coffee; the
/// liquid on top of it is clipped to the same ellipse, so a low surface
/// disappears behind the front rim.
final class CoffeeLevelLayer {
    let layer: CAGradientLayer
    private let liquid: CALayer

    init(shape: CoffeeInterior.Shape, contentsScale: CGFloat) {
        let r = shape.rect
        let inside = CAGradientLayer()
        inside.frame = r
        // The inside of white china: the back wall under the rim is in the
        // rim's shadow, the middle catches the light, the bottom is shaded.
        inside.colors = [
            NSColor(calibratedRed: 0.80, green: 0.78, blue: 0.75, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.93, green: 0.92, blue: 0.90, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.72, green: 0.70, blue: 0.67, alpha: 1).cgColor,
        ]
        inside.locations = [0, 0.45, 1]
        inside.startPoint = CGPoint(x: 0.5, y: 1)
        inside.endPoint = CGPoint(x: 0.5, y: 0)
        let mask = CAShapeLayer()
        mask.path = CGPath(ellipseIn: CGRect(origin: .zero, size: r.size), transform: nil)
        inside.mask = mask
        inside.contentsScale = contentsScale

        let liquid = CALayer()
        liquid.contents = shape.coffee
        liquid.contentsGravity = .resize
        liquid.contentsScale = contentsScale
        liquid.isHidden = true
        inside.addSublayer(liquid)

        layer = inside
        self.liquid = liquid
    }

    /// Paint `fill` (0…1). Model values, no implicit animation: this runs at
    /// 60 Hz under the pot, and "empties at once" means at once.
    func set(fill: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Full: the glyph's own coffee shows, untouched.
        layer.isHidden = fill >= 1
        liquid.isHidden = fill <= 0
        liquid.frame = CoffeeInterior.liquidFrame(in: layer.bounds.size, fill: fill)
        CATransaction.commit()
    }
}
