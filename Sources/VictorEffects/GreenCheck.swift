import AppKit
import QuartzCore

/// ✅ Tile #57 (the success chime): one big green tick swiped across the whole
/// desktop, left to right, the way a hand does it with a loaded brush — a short
/// stroke down into the corner, then the long one flung up and out to the right.
///
/// A **pure builder**, `SketchArrow`'s shape: `makeLayer` returns one container
/// with the whole choreography attached, the caller hangs it on the stage and
/// hands it to `trackEffect(duration: totalDuration)`. No timers, no state.
///
/// **Why a filled ribbon under a moving mask, and not a stroked path.** A
/// `CAShapeLayer` stroke has one width from end to end, and that is exactly what
/// makes a drawn line read as a diagram. A hand presses in, leans on the corner
/// and lifts off on the way out, so the ink here is a *polygon* whose width
/// follows that pressure (and whose two edges wander independently, as bristles
/// do); what animates is a mask — a fat stroke along the same centre line whose
/// `strokeEnd` runs 0 → 1 — so the ribbon is uncovered in the order the brush
/// laid it down.
enum GreenCheck {

    // MARK: - Geometry (normalised to the tick's own box, y up)

    /// Box width / height. A tick is wider than tall because of the long stroke.
    static let aspect: CGFloat = 1.2
    /// How much of the visible desktop (menu bar excluded) the box may fill,
    /// in each direction. "On the whole screen", with a margin a brush would keep.
    static let fill: CGFloat = 0.94

    /// Pen down, upper left of the short stroke.
    static let start = CGPoint(x: 0.07, y: 0.52)
    /// The corner, low and left of centre.
    static let vertex = CGPoint(x: 0.37, y: 0.10)
    /// Pen up, top right.
    static let end = CGPoint(x: 0.95, y: 0.94)
    /// Each stroke is a quadratic with its control pulled off the chord: nobody
    /// draws two rulers. The short one sags, the long one bows out and lifts.
    static let downControl = CGPoint(x: 0.19, y: 0.25)
    static let upControl = CGPoint(x: 0.60, y: 0.45)

    /// Brush width at its fullest (the corner), as a fraction of the box height.
    static let brush: CGFloat = 0.16

    // MARK: - Timing

    /// Pen down to pen up. The chime's attack is at 0 and it rings for 1.3 s; the
    /// tick has to be *there* inside the attack, not arrive after it.
    static let drawDuration: Double = 0.45
    /// Share of `drawDuration` spent on the short stroke — it is a third of the
    /// ink but a hand slows into a corner, so it gets more than a third of the time.
    static let downShare: Double = 0.40
    static let hold: Double = 1.05
    static let fadeDuration: Double = 0.7
    static var totalDuration: Double { drawDuration + hold + fadeDuration }

    static let ink = NSColor(srgbRed: 0.05, green: 0.80, blue: 0.20, alpha: 1)
    static let sheen = NSColor(srgbRed: 0.55, green: 1.0, blue: 0.55, alpha: 1)

    // MARK: - Layout

    /// The tick's box: centred on what can be seen (the menu bar's strip is not
    /// desktop), as large as `fill` allows in both directions.
    static func box(in bounds: CGRect, topInset: CGFloat) -> CGRect {
        let visible = CGRect(x: bounds.minX, y: bounds.minY,
                             width: bounds.width, height: max(1, bounds.height - topInset))
        let h = min(visible.height * fill, visible.width * fill / aspect)
        let w = h * aspect
        return CGRect(x: visible.midX - w / 2, y: visible.midY - h / 2, width: w, height: h)
    }

    static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                       y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }

    /// The pen's path in layer points: the short stroke, then the long one.
    static func centreline(in box: CGRect, samples: Int = 40) -> (down: [CGPoint], up: [CGPoint]) {
        func place(_ p: CGPoint) -> CGPoint {
            CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
        }
        let ts = (0...samples).map { CGFloat($0) / CGFloat(samples) }
        return (ts.map { place(quad(start, downControl, vertex, $0)) },
                ts.map { place(quad(vertex, upControl, end, $0)) })
    }

    /// Brush width along each stroke, t in 0…1: pressed in on the way down,
    /// fullest at the corner, lifted off to under half by the end of the flick.
    static func downWidth(_ t: CGFloat) -> CGFloat { 0.62 + 0.38 * t }
    static func upWidth(_ t: CGFloat) -> CGFloat { 1 - 0.58 * pow(t, 1.7) }

    /// A stroke as a closed polygon: the centre line pushed out along its normal
    /// by half the width on each side, each edge with its own slow waver.
    static func ribbon(_ pts: [CGPoint], width: (CGFloat) -> CGFloat, phase: CGFloat) -> CGPath {
        var left: [CGPoint] = [], right: [CGPoint] = []
        let n = pts.count
        for i in 0..<n {
            let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
            let len = max(0.001, hypot(b.x - a.x, b.y - a.y))
            let nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len
            let t = CGFloat(i) / CGFloat(n - 1)
            let half = width(t) / 2
            let wl = 1 + 0.07 * sin(t * 9.1 + phase) + 0.035 * sin(t * 23 + phase * 2.3)
            let wr = 1 + 0.07 * sin(t * 7.3 + phase + 2.1) + 0.035 * sin(t * 19 + phase * 1.7)
            left.append(CGPoint(x: pts[i].x + nx * half * wl, y: pts[i].y + ny * half * wl))
            right.append(CGPoint(x: pts[i].x - nx * half * wr, y: pts[i].y - ny * half * wr))
        }
        let path = CGMutablePath()
        path.addLines(between: left + right.reversed())
        path.closeSubpath()
        return path
    }

    static func polyline(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts)
        return p
    }

    static func length(_ pts: [CGPoint]) -> CGFloat {
        zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    // MARK: - The layer

    /// `now` is the media time the pen comes down at.
    static func makeLayer(in bounds: CGRect, topInset: CGFloat, scale: CGFloat,
                          now: CFTimeInterval = CACurrentMediaTime()) -> CALayer {
        let box = self.box(in: bounds, topInset: topInset)
        let line = centreline(in: box)
        let w = brush * box.height

        let container = CALayer()
        container.frame = bounds
        container.actions = ["opacity": NSNull()]
        // The shadow is what keeps a green tick legible on a green slide or a
        // white one. It lives a level ABOVE the mask: a mask cuts its own
        // layer's shadow off with the rest.
        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.55
        container.shadowRadius = w * 0.14
        container.shadowOffset = CGSize(width: 0, height: -w * 0.05)

        let inked = CALayer()
        inked.frame = bounds
        container.addSublayer(inked)

        func shape(_ path: CGPath, _ color: NSColor, alpha: CGFloat = 1) -> CAShapeLayer {
            let s = CAShapeLayer()
            s.frame = bounds
            s.contentsScale = scale
            s.path = path
            s.fillColor = color.withAlphaComponent(alpha).cgColor
            return s
        }
        func disc(_ c: CGPoint, _ r: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
        }
        // Separate layers, not subpaths of one: overlapping subpaths wound
        // opposite ways would punch a hole where the strokes cross at the corner.
        inked.addSublayer(shape(ribbon(line.down, width: { downWidth($0) * w }, phase: 0.4), ink))
        inked.addSublayer(shape(ribbon(line.up, width: { upWidth($0) * w }, phase: 2.9), ink))
        inked.addSublayer(shape(disc(line.down[0], downWidth(0) * w / 2), ink))            // the round start
        inked.addSublayer(shape(disc(line.up[0], w / 2), ink))                             // the corner's join
        inked.addSublayer(shape(disc(line.up[line.up.count - 1], upWidth(1) * w / 2), ink)) // the lifted tip
        // A wet streak down the middle of each stroke: the difference between
        // paint and a vector shape.
        inked.addSublayer(shape(ribbon(line.down, width: { downWidth($0) * w * 0.22 }, phase: 5.1), sheen, alpha: 0.35))
        inked.addSublayer(shape(ribbon(line.up, width: { upWidth($0) * w * 0.22 }, phase: 1.3), sheen, alpha: 0.35))

        // The mask: the same pen path, run on a brush-length past both ends so
        // the round start and the tip are inside it, stroked wider than the ink.
        func extend(_ from: CGPoint, awayFrom other: CGPoint, by d: CGFloat) -> CGPoint {
            let len = max(0.001, hypot(from.x - other.x, from.y - other.y))
            return CGPoint(x: from.x + (from.x - other.x) / len * d, y: from.y + (from.y - other.y) / len * d)
        }
        let lead = extend(line.down[0], awayFrom: line.down[1], by: w)
        let tail = extend(line.up[line.up.count - 1], awayFrom: line.up[line.up.count - 2], by: w)
        let downPts = [lead] + line.down
        let upPts = Array(line.up.dropFirst()) + [tail]
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = polyline(downPts + upPts)
        mask.fillColor = nil
        mask.strokeColor = NSColor.black.cgColor
        mask.lineWidth = w * 1.35
        mask.lineCap = .butt
        mask.lineJoin = .round
        mask.strokeEnd = 1
        inked.mask = mask

        let downLen = length(downPts)
        let corner = downLen / (downLen + length([line.down[line.down.count - 1]] + upPts))
        let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
        draw.values = [0, corner, 1]
        draw.keyTimes = [0, NSNumber(value: downShare), 1]
        // Into the corner slowing, out of it flung: fast at once, easing only
        // as the brush leaves the paper.
        draw.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.4, 0, 0.7, 1),
                                CAMediaTimingFunction(controlPoints: 0.15, 0.6, 0.3, 1)]
        draw.duration = drawDuration
        draw.beginTime = now
        draw.fillMode = .both
        draw.isRemovedOnCompletion = false
        mask.add(draw, forKey: "draw")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = fadeDuration
        fade.beginTime = now + drawDuration + hold
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        container.add(fade, forKey: "fade")
        return container
    }
}
