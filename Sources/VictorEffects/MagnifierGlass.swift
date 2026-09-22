import CoreGraphics
import Foundation

/// 🔍 The detective's magnifying glass (sfx #6, the Pink Panther theme): the
/// geometry of the prop and the drawing of it, with no screen in sight.
///
/// Same bargain as `HeartbeatBump` and `RainStorm`: everything here is a
/// function of the overlay bounds or of the lens's own diameter, so the numbers
/// can be tested on a machine with no display attached and the effect in
/// `EmojiAnimator` is left with nothing but wiring.
///
/// **The glass is drawn, not photographed.** Every fraction below is relative
/// to the lens's OUTER diameter `D`, so the whole prop — rim, ferrule, handle,
/// glare — scales as one thing when the lens is resized, and it stays crisp on
/// a retina at any size a bitmap would have had to be re-cut for.
enum MagnifierGlass {

    // MARK: - How big, and how much bigger

    /// Outer diameter of the lens as a fraction of the screen **height**. It
    /// started at a third (Victor, 2026-09-22: *"cam la o treime din înălțimea
    /// ecranului"*) and was **doubled the same day** — *"trebuie să fie de două
    /// ori mai mare"*: from the back of the room a third of the height is a
    /// prop you notice, not a lens you can read through.
    ///
    /// Doubled as the **diameter**, not as the area: "twice as big" about a
    /// thing on a screen is how wide it looks, and doubling the area would have
    /// grown it by only 1.41 — visibly less than what was asked for.
    ///
    /// A share of the height rather than of the area or the width, for
    /// `HeartbeatBump`'s reason: a fraction of `W · H` grows and shrinks with
    /// the aspect ratio of whatever display it lands on, while a fraction of the
    /// height reads the same on the retina, on the projector and on the wide
    /// external. On the built-in (1728 × 1117 pt) that is a 745 pt lens.
    static let diameterFraction: CGFloat = 2.0 / 3.0

    /// How much bigger the desktop looks inside the glass. 2× is what the word
    /// "magnifier" promises and what fits: at 2× the 745 pt lens shows a 372 pt
    /// square of desktop, a good handful of lines of code — enough to be the
    /// point of the gesture. Past ~3× the room sees pixels rather than content
    /// and loses track of where on the screen it is looking. The zoom is
    /// deliberately **unchanged** by the resize: a bigger lens was asked for,
    /// not a closer one, and raising both would have shown the same few pixels
    /// twice as coarsely.
    static let zoom: CGFloat = 2.0

    // MARK: - The prop, in fractions of the outer diameter D

    /// Thickness of the metal rim, so the clear glass is `D - 2·0.085·D` across.
    static let ringFraction: CGFloat = 0.085
    /// The black cartoon outline around every part, as in the reference drawing.
    static let strokeFraction: CGFloat = 0.017
    /// The collar between rim and handle.
    static let ferruleLengthFraction: CGFloat = 0.15
    static let ferruleWidthFraction: CGFloat = 0.24
    /// The wooden handle: length along the axis, width at the collar, width at
    /// the rounded tip. Slightly tapered — a parallel bar reads as a pipe.
    static let handleLengthFraction: CGFloat = 0.80
    static let handleWidthFraction: CGFloat = 0.20
    static let handleTipWidthFraction: CGFloat = 0.165

    /// Which way the handle points: down and to the right, at 45°, the way the
    /// inspector holds it on the tile's own artwork. Negative because the layer
    /// (and the drawing context) are y-up.
    static let tiltRadians: CGFloat = -.pi / 4

    /// Transparent slack around the prop so the black outline and the layer's
    /// shadow are not clipped by the canvas edge.
    static let paddingFraction: CGFloat = 0.05

    // MARK: - Derived geometry

    /// The lens's outer diameter on this overlay. 0 for a zero-sized overlay (no
    /// screen attached yet), which the caller reads as "draw nothing".
    static func outerDiameter(in bounds: CGRect) -> CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 0 }
        return bounds.height * diameterFraction
    }

    /// Radius of the **clear glass** — the disc that actually shows the
    /// magnified desktop, i.e. the outer radius minus the rim.
    static func glassRadius(outerDiameter d: CGFloat) -> CGFloat {
        max(0, d / 2 - d * ringFraction)
    }

    /// Distance from the lens centre to the tip of the handle.
    static func reach(outerDiameter d: CGFloat) -> CGFloat {
        d / 2 + d * (ferruleLengthFraction + handleLengthFraction)
    }

    /// The artwork's canvas: the lens circle and the handle's tip, plus padding.
    /// Square, because the handle leaves at 45°.
    static func canvasSize(outerDiameter d: CGFloat) -> CGSize {
        guard d > 0 else { return .zero }
        let r = d / 2
        let pad = d * paddingFraction
        let halfWidest = d * max(ferruleWidthFraction, handleWidthFraction) / 2
        let tipAlongAxis = reach(outerDiameter: d) * cos(tiltRadians)   // cos(-45°) = sin(45°)
        let side = pad + r + max(r, tipAlongAxis + halfWidest) + pad
        return CGSize(width: side, height: side)
    }

    /// Where the lens centre sits inside that canvas: up and to the left, since
    /// the handle runs down and to the right.
    static func lensCentre(outerDiameter d: CGFloat) -> CGPoint {
        let canvas = canvasSize(outerDiameter: d)
        let inset = d * paddingFraction + d / 2
        return CGPoint(x: inset, y: canvas.height - inset)
    }

    /// The same point as a unit-square `anchorPoint`, so the artwork layer can
    /// simply be given `position = <where the glass is pointed>` and will hang
    /// off its own lens centre — including while it scales on entry.
    static func lensAnchor(outerDiameter d: CGFloat) -> CGPoint {
        let canvas = canvasSize(outerDiameter: d)
        guard canvas.width > 0, canvas.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let centre = lensCentre(outerDiameter: d)
        return CGPoint(x: centre.x / canvas.width, y: centre.y / canvas.height)
    }

    /// Where to park the screenshot **inside the round clip layer** so that the
    /// desktop point `focus` lands exactly under the middle of the glass,
    /// magnified `zoom` times.
    ///
    /// The clip layer is `2r × 2r` with its own origin at its bottom-left, so
    /// the middle of the glass is `(r, r)`: scale the screen by `z` and slide it
    /// until `focus · z` sits there. Nothing is clamped — with the pointer in a
    /// corner the honest answer is a glass half full of desktop and half empty,
    /// not a view that has quietly slid inwards off the thing being pointed at.
    static func shotFrame(screen: CGRect, focus: CGPoint, glassRadius r: CGFloat,
                          zoom z: CGFloat = zoom) -> CGRect {
        CGRect(x: r - focus.x * z,
               y: r - focus.y * z,
               width: screen.width * z,
               height: screen.height * z)
    }

    // MARK: - The drawing

    /// The prop itself: rim, collar, wooden handle and a hint of glare, with the
    /// glass left **transparent** — what shows through it is a separate layer
    /// underneath holding the magnified screenshot.
    ///
    /// `scale` is the backing-store scale of the screen it will be drawn on, so
    /// the outline stays a hairline on a retina instead of a staircase.
    static func image(outerDiameter d: CGFloat, scale: CGFloat) -> CGImage? {
        guard d > 1, scale > 0 else { return nil }
        let canvas = canvasSize(outerDiameter: d)
        let px = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        guard let ctx = CGContext(data: nil,
                                  width: Int(px.width.rounded()), height: Int(px.height.rounded()),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        let space = CGColorSpaceCreateDeviceRGB()
        let centre = lensCentre(outerDiameter: d)
        let r = d / 2
        let stroke = d * strokeFraction

        // 1. Handle and collar, in a frame rotated onto the handle's axis, and
        //    drawn FIRST so the rim overlaps them rather than the other way
        //    round — the glass is in front of the hand holding it.
        ctx.saveGState()
        // …and clipped OUT of the glass disc first. The handle is tucked a few
        // points under the rim so no seam shows between them, and its square
        // shoulder therefore pokes across the inner circle — where it would be
        // drawn straight over the desktop the lens is supposed to be showing,
        // as a dark sliver floating inside the glass.
        let glassHole = CGMutablePath()
        glassHole.addRect(CGRect(origin: .zero, size: canvas))
        glassHole.addEllipse(in: CGRect(x: centre.x - glassRadius(outerDiameter: d),
                                        y: centre.y - glassRadius(outerDiameter: d),
                                        width: glassRadius(outerDiameter: d) * 2,
                                        height: glassRadius(outerDiameter: d) * 2))
        ctx.addPath(glassHole)
        ctx.clip(using: .evenOdd)
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: tiltRadians)

        let handleStart = r * 0.86          // tucked under the rim
        let handleEnd = reach(outerDiameter: d)
        let w0 = d * handleWidthFraction
        let w1 = d * handleTipWidthFraction
        let cap = w1 / 2
        let handle = CGMutablePath()
        handle.move(to: CGPoint(x: handleStart, y: w0 / 2))
        handle.addLine(to: CGPoint(x: handleEnd - cap, y: w1 / 2))
        handle.addArc(center: CGPoint(x: handleEnd - cap, y: 0), radius: cap,
                      startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        handle.addLine(to: CGPoint(x: handleStart, y: -w0 / 2))
        handle.closeSubpath()

        // Wood, lit from the upper edge: flat brown reads as plastic.
        ctx.saveGState()
        ctx.addPath(handle)
        ctx.clip()
        if let wood = CGGradient(colorSpace: space,
                                 colorComponents: [0.48, 0.24, 0.09, 1,
                                                   0.78, 0.45, 0.20, 1,
                                                   0.62, 0.33, 0.13, 1],
                                 locations: [0, 0.45, 1], count: 3) {
            ctx.drawLinearGradient(wood,
                                   start: CGPoint(x: 0, y: -w0 / 2),
                                   end: CGPoint(x: 0, y: w0 / 2), options: [])
        }
        ctx.restoreGState()
        ctx.addPath(handle)
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        ctx.setLineWidth(stroke)
        ctx.strokePath()

        // The collar: a short metal sleeve where the handle meets the rim.
        let ferrule = CGRect(x: r * 0.80, y: -d * ferruleWidthFraction / 2,
                             width: d * ferruleLengthFraction + r * 0.10,
                             height: d * ferruleWidthFraction)
        let collar = CGPath(roundedRect: ferrule,
                            cornerWidth: ferrule.height * 0.28,
                            cornerHeight: ferrule.height * 0.28, transform: nil)
        ctx.saveGState()
        ctx.addPath(collar)
        ctx.clip()
        if let metal = CGGradient(colorSpace: space,
                                  colorComponents: [0.55, 0.55, 0.57, 1,
                                                    0.93, 0.93, 0.94, 1,
                                                    0.66, 0.66, 0.68, 1],
                                  locations: [0, 0.48, 1], count: 3) {
            ctx.drawLinearGradient(metal,
                                   start: CGPoint(x: 0, y: ferrule.minY),
                                   end: CGPoint(x: 0, y: ferrule.maxY), options: [])
        }
        ctx.restoreGState()
        ctx.addPath(collar)
        ctx.setLineWidth(stroke)
        ctx.strokePath()
        ctx.restoreGState()

        // 2. The rim: an annulus filled with brushed metal, outlined inside and
        //    out, exactly as the cartoon draws it.
        let outer = CGRect(x: centre.x - r, y: centre.y - r, width: d, height: d)
        let innerR = glassRadius(outerDiameter: d)
        let inner = CGRect(x: centre.x - innerR, y: centre.y - innerR,
                           width: innerR * 2, height: innerR * 2)
        let ring = CGMutablePath()
        ring.addEllipse(in: outer)
        ring.addEllipse(in: inner)
        ctx.saveGState()
        ctx.addPath(ring)
        ctx.clip(using: .evenOdd)
        if let chrome = CGGradient(colorSpace: space,
                                   colorComponents: [0.98, 0.98, 0.99, 1,
                                                     0.78, 0.78, 0.80, 1,
                                                     0.60, 0.60, 0.63, 1],
                                   locations: [0, 0.55, 1], count: 3) {
            ctx.drawLinearGradient(chrome,
                                   start: CGPoint(x: outer.minX, y: outer.maxY),
                                   end: CGPoint(x: outer.maxX, y: outer.minY), options: [])
        }
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        ctx.setLineWidth(stroke)
        ctx.strokeEllipse(in: outer.insetBy(dx: stroke / 2, dy: stroke / 2))
        ctx.strokeEllipse(in: inner.insetBy(dx: -stroke / 2, dy: -stroke / 2))

        // 3. Glass. Nearly nothing — a breath of white and one diagonal streak
        //    across the upper left, which is what makes a transparent hole read
        //    as a lens. Anything stronger and the desktop underneath (the whole
        //    point of the effect) goes milky.
        ctx.saveGState()
        ctx.addEllipse(in: inner)
        ctx.clip()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.05))
        ctx.fill(inner)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: .pi / 4)
        let streak = CGRect(x: -innerR * 0.95, y: innerR * 0.28,
                            width: innerR * 1.9, height: innerR * 0.22)
        ctx.addPath(CGPath(roundedRect: streak,
                           cornerWidth: streak.height / 2, cornerHeight: streak.height / 2,
                           transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.restoreGState()

        return ctx.makeImage()
    }
}
