import AppKit
import QuartzCore

/// 📺 CRT shutdown — the way a cathode-ray television dies when the switch is
/// pulled: the picture is squeezed between two black shutters until only a
/// bright horizontal line is left, the line holds for a blink, then collapses
/// from both ends into a dot that burns off.
///
/// This is a **pure builder**: `makeLayer(in:scale:)` returns ONE container
/// layer with the whole choreography already attached, so the caller adds it to
/// the host layer and hands it to `trackEffect(duration: totalDuration)` — the
/// self-termination rule is then satisfied by the ordinary machinery, and
/// `stop-all` tears it down like any other tracked effect. No timers, no
/// callbacks, no state: everything it knows about the screen is the bounds it
/// was handed, which is what makes the geometry testable headlessly.
///
/// **The mechanics are the 🕳️ iris close's** (`EmojiAnimator.showIrisClose`),
/// reused as-is: plain `CALayer`s on the overlay panel's `hostLayer`; one
/// `CABasicAnimation` per phase, all on a single `CACurrentMediaTime()` clock
/// via `beginTime`, with `fillMode` set and `isRemovedOnCompletion = false` so a
/// finished phase HOLDS its end state while the next one runs; and a closing
/// opacity fade that gives the desktop back exactly the way `cancelIris` does.
/// The difference is only the shape: the iris shrinks a circle in from the
/// corners, this one brings two rectangles in from the top and bottom edges.
enum CrtShutdown {

    // MARK: - Timing (one clock, all offsets measured from t0)

    /// Top and bottom edge → centre. Ease-in, because the shutters do not start
    /// at speed: the picture folds slowly and then goes.
    static let closeDuration: CFTimeInterval = 0.7
    /// The last ~0.1 s of the close is when the white line lights up, so the
    /// shutters appear to *squeeze* the picture into it rather than reveal it.
    static let lineFadeIn: CFTimeInterval = 0.10
    /// The bright line dwells — long enough to read as an afterimage, short
    /// enough that nobody thinks the overlay is stuck.
    static let lineHold: CFTimeInterval = 0.15
    /// The line collapses from both ends towards the centre. Ease-in again: the
    /// ends rush in at the finish.
    static let collapseDuration: CFTimeInterval = 0.4
    /// The last white dot burning off.
    static let dotFade: CFTimeInterval = 0.18
    /// Black screen after the dot — the tube is off, nothing has come back yet.
    static let blackHold: CFTimeInterval = 0.2
    /// Fade the black away: the same gentle reveal `cancelIris` uses for the
    /// iris's auto-reveal, and for the same reason — an instant cut back to the
    /// desktop reads as a glitch, a fade reads as the end of the gag.
    static let revealDuration: CFTimeInterval = 0.45

    /// When the white line lights up.
    static var lineOnAt: CFTimeInterval { closeDuration - lineFadeIn }
    /// When the line starts collapsing sideways.
    static var collapseAt: CFTimeInterval { closeDuration + lineHold }
    /// When the leftover dot flashes.
    static var dotAt: CFTimeInterval { collapseAt + collapseDuration }
    /// When the black starts fading back to the desktop.
    static var revealAt: CFTimeInterval { dotAt + dotFade + blackHold }
    /// The whole effect, teardown included — what `trackEffect` is given.
    static var totalDuration: CFTimeInterval { revealAt + revealDuration }

    // MARK: - Geometry

    /// The white line's height in points. ~10 px is the thinnest that still
    /// reads as a *line* on a projector rather than as a scratch on the screen.
    static let lineHeight: CGFloat = 10
    /// The dot the line collapses into.
    static let dotSize: CGFloat = 16

    /// The white line: full width, `lineHeight` tall, centred.
    static func lineFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.midY - lineHeight / 2,
               width: bounds.width, height: lineHeight)
    }

    /// `position.y` the shutter coming down from the **top** edge travels
    /// between. Each shutter is a full-screen-sized black rectangle parked
    /// entirely off-screen, so it slides exactly half a screen and lands with
    /// its inner edge on the middle — the two then cover the screen with no
    /// seam to align and no size animation to interpolate.
    static func topShutterTravel(in bounds: CGRect) -> (from: CGFloat, to: CGFloat) {
        (from: bounds.midY + bounds.height, to: bounds.midY + bounds.height / 2)
    }

    /// The mirror of `topShutterTravel` for the shutter coming up from the
    /// bottom edge. Symmetric on purpose: it makes the effect independent of
    /// whether the host layer's geometry is flipped.
    static func bottomShutterTravel(in bounds: CGRect) -> (from: CGFloat, to: CGFloat) {
        (from: bounds.midY - bounds.height, to: bounds.midY - bounds.height / 2)
    }

    // MARK: - The layer

    /// Builds the effect. Returns nil for a degenerate screen (the overlay panel
    /// can be mid-resize), same guard `showIrisClose` makes.
    static func makeLayer(in bounds: CGRect, scale: CGFloat = 2) -> CALayer? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let t0 = CACurrentMediaTime()
        let container = CALayer()
        container.frame = bounds
        container.contentsScale = scale

        // --- the two shutters ---
        for travel in [topShutterTravel(in: bounds), bottomShutterTravel(in: bounds)] {
            let shutter = CALayer()
            shutter.bounds = CGRect(origin: .zero, size: bounds.size)
            shutter.position = CGPoint(x: bounds.midX, y: travel.to)   // model = closed
            shutter.backgroundColor = NSColor.black.cgColor
            shutter.contentsScale = scale
            container.addSublayer(shutter)

            let slide = CABasicAnimation(keyPath: "position.y")
            slide.fromValue = travel.from
            slide.toValue = travel.to
            slide.beginTime = t0
            slide.duration = closeDuration
            slide.timingFunction = CAMediaTimingFunction(name: .easeIn)
            slide.fillMode = .both
            slide.isRemovedOnCompletion = false
            shutter.add(slide, forKey: "crtClose")
        }

        // --- the line the picture is squeezed into ---
        // Drawn ON TOP of the closed shutters, not in a gap between them: the
        // shutters can then simply meet in the middle, and the line owns its own
        // appearance and its own collapse.
        let line = CALayer()
        line.bounds = CGRect(origin: .zero, size: lineFrame(in: bounds).size)
        line.position = CGPoint(x: bounds.midX, y: bounds.midY)
        line.backgroundColor = NSColor.white.cgColor
        line.shadowColor = NSColor.white.cgColor
        line.shadowOpacity = 0.9
        line.shadowRadius = 12
        line.shadowOffset = .zero
        line.contentsScale = scale
        container.addSublayer(line)

        let lineOn = CABasicAnimation(keyPath: "opacity")
        lineOn.fromValue = 0.0
        lineOn.toValue = 1.0
        lineOn.beginTime = t0 + lineOnAt
        lineOn.duration = lineFadeIn
        lineOn.fillMode = .both          // .backwards is what keeps it dark during the close
        lineOn.isRemovedOnCompletion = false
        line.add(lineOn, forKey: "crtLineOn")

        // Scaling on x (anchor point 0.5) collapses it towards the centre from
        // BOTH ends at once, which a width animation would not do without also
        // animating the position.
        let collapse = CABasicAnimation(keyPath: "transform.scale.x")
        collapse.fromValue = 1.0
        collapse.toValue = 0.0
        collapse.beginTime = t0 + collapseAt
        collapse.duration = collapseDuration
        collapse.timingFunction = CAMediaTimingFunction(name: .easeIn)
        collapse.fillMode = .both
        collapse.isRemovedOnCompletion = false
        line.add(collapse, forKey: "crtLineCollapse")

        // --- the dot left behind ---
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = NSColor.white.cgColor
        dot.shadowColor = NSColor.white.cgColor
        dot.shadowOpacity = 1.0
        dot.shadowRadius = 18
        dot.shadowOffset = .zero
        dot.opacity = 0
        dot.contentsScale = scale
        container.addSublayer(dot)

        let dotFlash = CAKeyframeAnimation(keyPath: "opacity")
        dotFlash.values = [0.0, 1.0, 0.0]
        dotFlash.keyTimes = [0.0, 0.12, 1.0]
        dotFlash.beginTime = t0 + dotAt
        dotFlash.duration = dotFade
        dotFlash.fillMode = .both
        dotFlash.isRemovedOnCompletion = false
        dot.add(dotFlash, forKey: "crtDotFlash")

        let dotShrink = CABasicAnimation(keyPath: "transform.scale")
        dotShrink.fromValue = 1.0
        dotShrink.toValue = 0.2
        dotShrink.beginTime = t0 + dotAt
        dotShrink.duration = dotFade
        dotShrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        dotShrink.fillMode = .both
        dotShrink.isRemovedOnCompletion = false
        dot.add(dotShrink, forKey: "crtDotShrink")

        // --- give the desktop back ---
        // The container keeps opacity 1 in the model and the fill holds it at 0
        // after the fade, so the caller's `trackEffect` removal at
        // `totalDuration` lands on an already-invisible layer.
        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 1.0
        reveal.toValue = 0.0
        reveal.beginTime = t0 + revealAt
        reveal.duration = revealDuration
        reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        reveal.fillMode = .both
        reveal.isRemovedOnCompletion = false
        container.add(reveal, forKey: "crtReveal")

        return container
    }
}
