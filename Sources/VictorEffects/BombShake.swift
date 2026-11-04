import Foundation
import QuartzCore

/// ☢️ The full-screen bomb's blast shakes the whole picture, for half a second.
///
/// An overlay cannot move the display, so the picture that shakes is a
/// **photograph of the desktop** laid over the real one, with the fireball on
/// top of it — the skull boom's trick, at a fraction of its size. Three things
/// keep it that small:
///
/// - **No backdrop and no zoom.** A photograph at rest is pixel-identical to the
///   desktop under it, so it arrives and leaves without a seam, and the sliver a
///   shake opens at the screen's edge shows that same desktop rather than black.
/// - **One keyframe animation on an absolute clock.** It is added in the same
///   transaction as the fireball's first frame, so CoreAnimation stamps both with
///   the same begin time, and the window server runs the rest: nothing here costs
///   the main thread a frame, and no `asyncAfter` can put jitter on the screen.
/// - **Offsets are a pure function of time**, stated as a fraction of the screen
///   width, so the fireball (on the zoom stage) and the photograph (on its slice)
///   land on the glass with the same shake under a zoom too.
///
/// What runs the clock is `explosionBlastOnset`: the fireball starts there, this
/// starts with the fireball, and neither has a second opinion about it.
enum BombShake {

    /// From the blast, as Victor asked: *"a bit after the explosion"*, and gone
    /// long before the fireball is.
    static let seconds: Double = 0.5

    /// Peak displacement as a fraction of the screen width: ~12 pt on a laptop.
    /// **A little**: the picture is a live demo that has just been bombed, not
    /// the skull boom's punch, and text has to be readable again the moment it
    /// stops.
    static let amplitude: CGFloat = 0.007

    /// Where it sits inside `03_explosion.mp3`. Derived, never typed: there is one
    /// measurement of that clip.
    static let startsInClip: Double = EmojiAnimator.explosionBlastOnset

    /// How long before the big bomb enters the screen the photograph is taken.
    ///
    /// **It cannot be taken at the blast**: by then the bomb is on the glass and
    /// would hang in the picture as a ghost, under the fireball, for the whole
    /// shake. And the capture is not instant, so "the instant before the bomb
    /// enters" is not enough either. A quarter of a second covers what the
    /// capture costs; the price is a picture ~1 s old when it is shown, which only
    /// a playing video could give away, for half a second, under a fireball.
    static let captureLead: Double = 0.25

    /// Seconds after the press to take the photograph.
    static let captureDelay: Double = EmojiAnimator.bombAutoDropDelay - captureLead

    /// Keyframes per second: one a frame, CoreAnimation interpolating on a faster
    /// panel.
    static let fps: Double = 60

    static let animationKey = "bombShake"

    /// 1 on the blast, exactly 0 at `seconds`: the shake dies with no last twitch,
    /// and the moment the photograph leaves it is already at rest.
    static func envelope(_ t: Double) -> Double {
        guard t >= 0, t < seconds else { return 0 }
        return pow(1 - t / seconds, 1.5)
    }

    /// The picture's offset `t` seconds after the blast, in points.
    ///
    /// Zero on the blast's first frame, so the photograph lands exactly on the
    /// desktop, and at full swing a frame or two later. The frequencies share no
    /// multiple, so the path is a rattle in every direction and not a circle.
    static func offset(at t: Double, width: CGFloat) -> CGPoint {
        let reach = Double(width * amplitude) * envelope(t)
        return CGPoint(x: reach * sin(2 * .pi * 13 * t) * cos(2 * .pi * 5.3 * t),
                       y: reach * sin(2 * .pi * 17 * t))
    }

    /// The whole shake, for any layer resting where it belongs. **Additive**, so
    /// the same animation fits a fireball and a photograph without knowing where
    /// either one is, and it leaves nothing behind: no fill, the model value was
    /// never touched.
    static func animation(width: CGFloat) -> CAKeyframeAnimation {
        let frames = Int((seconds * fps).rounded())
        let a = CAKeyframeAnimation(keyPath: "position")
        a.values = (0...frames).map { NSValue(point: offset(at: Double($0) / fps, width: width)) }
        a.keyTimes = (0...frames).map { NSNumber(value: Double($0) / Double(frames)) }
        a.calculationMode = .linear
        a.duration = seconds
        a.isAdditive = true
        return a
    }
}
