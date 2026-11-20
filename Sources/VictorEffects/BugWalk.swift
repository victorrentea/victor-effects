import CoreGraphics
import Foundation

/// 🪲 ⌘⌃9 (2026-11-19, keyed in `victor-macos-addons`): a beetle walks across the
/// projected Retina, legs going the whole way, and stops where Victor pointed.
///
/// Victor's brief, dictated over four screenshots of the Retina: *"have this walk
/// from somewhere here, somewhere here, to somewhere here"* — three boxes dragged
/// on a 3456×2234 capture. Read as: it **starts** in the small box low on the
/// right (`startBox`), **ends** in the box up on the left (`endBox`), and the big
/// box in between (`routeBox`) is the ground it crosses: the curve's control point
/// is drawn from it, so every press takes a different arc and the whole walk stays
/// inside start ∪ route ∪ end (a quadratic curve never leaves the triangle of its
/// three points).
///
/// The picture is `assetsDir/bug-walk.png`, a strip of 13 frames (a 1.3 s walk
/// cycle in place) cut out of a GIPHY GIF Victor copied off Google Images —
/// licence unknown, so it stays out of the repo. `tools/make-bug-walk.py` turns
/// the white background into alpha and keeps the soft shadow as translucent
/// black, so it reads on a dark editor as well as on a slide. The legs loop
/// for as long as the walk lasts; the GIF itself does not move, the layer does.
///
/// Everything here is arithmetic, tested without a screen (`BugWalkTests`).
enum BugWalk {
    /// Key in `activeEffects`, and the name `fireEffect` answers to.
    static let effectName = "bug"
    static let spriteName = "bug-walk.png"
    static let frameCount = 13
    /// The GIF's own 100 ms per frame.
    static let frameDuration: Double = 0.1
    /// Where the beetle's head points in the strip, as an angle in AppKit's
    /// y-up space: up-left, measured as the principal axis of its body
    /// (`tools/make-bug-walk.py` prints it). The sprite is turned by minus this
    /// so its head points along +x, which is what `.rotateAuto` steers.
    static let spriteHeading: CGFloat = 132.5 * .pi / 180
    /// Its height on the screen: 1.5× the first edition's 0.085 (2026-11-20,
    /// Victor: the room should see it without looking for it).
    static let heightShare: CGFloat = 0.1275
    /// Points per second. A beetle, not a cockroach: it should take a few
    /// seconds to cross, long enough for the room to notice it.
    static let speed: CGFloat = 170
    static let minWalk: Double = 2.5
    static let maxWalk: Double = 9
    static let fadeIn: Double = 0.25
    /// Standing still at the destination before it fades.
    static let rest: Double = 0.9
    static let fadeOut: Double = 0.6

    /// The three boxes, as fractions of the screen with a **top-left** origin
    /// (the screenshot's), from the pixels Victor dragged on the 3456×2234 capture.
    static let startBox = unit(2364, 1522, 2822, 1748)
    static let routeBox = unit(316, 504, 2696, 1552)
    static let endBox = unit(782, 678, 1248, 998)

    private static func unit(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
        CGRect(x: x0 / 3456, y: y0 / 2234, width: (x1 - x0) / 3456, height: (y1 - y0) / 2234)
    }

    struct Route: Equatable {
        var start: CGPoint
        var control: CGPoint
        var end: CGPoint
    }

    /// A unit point (top-left origin) placed in `bounds` (AppKit, y up).
    static func place(_ u: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + u.x * bounds.width, y: bounds.maxY - u.y * bounds.height)
    }

    static func randomUnit<G: RandomNumberGenerator>(in box: CGRect, using rng: inout G) -> CGPoint {
        CGPoint(x: CGFloat.random(in: box.minX...box.maxX, using: &rng),
                y: CGFloat.random(in: box.minY...box.maxY, using: &rng))
    }

    static func route<G: RandomNumberGenerator>(in bounds: CGRect, using rng: inout G) -> Route {
        Route(start: place(randomUnit(in: startBox, using: &rng), in: bounds),
              control: place(randomUnit(in: routeBox, using: &rng), in: bounds),
              end: place(randomUnit(in: endBox, using: &rng), in: bounds))
    }

    /// The quadratic Bézier at `t` ∈ [0, 1].
    static func point(on r: Route, at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * r.start.x + 2 * u * t * r.control.x + t * t * r.end.x,
                       y: u * u * r.start.y + 2 * u * t * r.control.y + t * t * r.end.y)
    }

    static func length(of r: Route, segments: Int = 48) -> CGFloat {
        var total: CGFloat = 0
        var last = r.start
        for i in 1...segments {
            let p = point(on: r, at: CGFloat(i) / CGFloat(segments))
            total += hypot(p.x - last.x, p.y - last.y)
            last = p
        }
        return total
    }

    static func walkDuration(_ r: Route) -> Double {
        min(max(Double(length(of: r) / speed), minWalk), maxWalk)
    }

    static func size(in bounds: CGRect, sprite: CGSize) -> CGSize {
        guard sprite.width > 0, sprite.height > 0 else { return .zero }
        let h = bounds.height * heightShare
        return CGSize(width: h * sprite.width / sprite.height, height: h)
    }

    /// The strip cut into its frames, left to right.
    static func frames(from strip: CGImage) -> [CGImage] {
        let w = strip.width / frameCount
        guard w > 0 else { return [] }
        return (0..<frameCount).compactMap {
            strip.cropping(to: CGRect(x: $0 * w, y: 0, width: w, height: strip.height))
        }
    }
}
