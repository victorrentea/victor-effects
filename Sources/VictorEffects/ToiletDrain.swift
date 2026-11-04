import Foundation
import simd

/// 🚽 The flush, as numbers: the whole screen shrinks into a round bowl in the
/// middle, with black around it, and what it was turns into the water in the bowl.
///
/// **The design is Victor's, 2026-11-04**, after a screen-filling whirlpool and a
/// drain that he turned down. In order:
///
/// 1. The whole desktop shrinks into a circle, on clean black. It turns only a
///    little: a spiral filling the screen is exactly what this is not.
/// 2. Inside the circle it keeps turning and is washed over by blue water.
/// 3. The bowl: water trembling gently with small waves, black still around it.
/// 4. The whole screen fades back to the desktop at once, one alpha for every pixel.
///
/// **Black is true black.** Outside the circle every pixel is `(0, 0, 0)` and opaque:
/// no glow, no vignette, nothing that fades towards it. All the shading of the bowl
/// lives inside the rim, and the rim is a pixel and a half of antialiasing.
///
/// **The whole screen fits.** A rectangle does not fit in a circle by scaling:
/// scaled to its diagonal it leaves gaps, scaled to its height it is cropped. So each
/// direction is squeezed by how far the screen's edge is that way (`extent`,
/// `squeeze`), which puts the edge of the desktop on the rim all the way around. It
/// is 1 until the rim gets there, so at rest the warp is the identity.
///
/// **Against the clip.** `66_toilet.mp3` is measured, 5.08 s: a valve, a long hiss, a
/// gurgle cut dead. The shrink runs through the hiss and lands on the gurgle, whose
/// three pulses tighten the circle the last of the way and wash the picture out.
/// The picture is gone the instant the clip's noise is. The bowl then has to be seen,
/// which the 0.6 s of room tone cannot do alone: the end runs 0.82 s past the audio.
enum ToiletDrain {

    // MARK: - The clip (measured with ffmpeg in 100 ms and 20 ms windows)

    /// The whole clip. A new recording on the tile means measuring all of these
    /// again.
    static let clipSeconds: Double = 5.08
    /// The handle: −32 dB climbing to −15 dB, the first swell of water. Before it
    /// the screen is the desktop, pixel for pixel.
    static let valve: Double = 0.45
    /// Broadband noise jumps in at −13 dB: the bowl is rushing.
    static let rush: Double = 1.3
    /// The hiss gives way to a low boom (zero crossings fall from 2 kHz to 300 Hz).
    static let gurgle: Double = 3.72
    /// Where each of the gurgle's three pulses starts and ends, between the dips
    /// at 3.96 and 4.24.
    static let gulps: [(from: Double, to: Double)] = [(3.72, 3.98), (4.03, 4.26), (4.30, 4.47)]
    /// −12.6 dB to −35 dB inside 40 ms: the last of the picture is gone with it.
    static let drained: Double = 4.47

    // MARK: - The ending (past the clip's 5.08 s: this part is silent on purpose)

    /// The bowl alone on the screen for 0.93 s, long enough to be seen as one.
    static let settled: Double = 5.40
    /// The whole screen is the desktop again, 0.82 s after the clip's last sound.
    static let fadeEnds: Double = 5.90
    /// The layer outlives the last visible frame by this much, so the frame it
    /// leaves on is an empty one and the removal is never what gives the desktop
    /// back.
    static let tailAllowance: Double = 0.15
    /// What `trackEffect` is given: the rule that every show ends itself.
    static let totalSeconds: Double = fadeEnds + tailAllowance

    // MARK: - The screen and the bowl

    /// The bowl's radius, of the screen's short side: a circle 62 % of the screen's
    /// height across, ~19 % of a 16:10 screen's area. Big enough to read as a bowl
    /// of water from the back of a room, small enough that the black is a frame.
    static let bowlShare: Double = 0.31

    /// Everything in pixels of the picture being drawn.
    struct Geometry {
        let width: Double
        let height: Double

        /// Centre to corner.
        var reach: Double { (width * width + height * height).squareRoot() / 2 }
        /// One radius, in pixels on both axes, so it is round on any aspect ratio.
        var bowl: Double { ToiletDrain.bowlShare * min(width, height) }
    }

    /// Smooth 0…1 from `from` to `to`, which may run downhill.
    static func smooth(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let u = to == from ? (x < from ? 0 : 1) : min(1, max(0, (x - from) / (to - from)))
        return u * u * (3 - 2 * u)
    }

    /// Sum of one smooth step per pulse of the gurgle, each worth `share`.
    private static func onGulps(_ t: Double, share: Double) -> Double {
        gulps.reduce(0) { $0 + share * smooth($1.from, $1.to, t) }
    }

    // MARK: - The shrink

    /// What each gulp takes of the way to the bowl: the circle is whole on the
    /// screen well before the gurgle, and each pulse is seen to tighten it.
    private static let gulpShrink: Double = 0.04

    /// How far the shrink has got, 0…1: through the hiss, then the gulps.
    static func shrink(_ t: Double) -> Double {
        (1 - 3 * gulpShrink) * smooth(valve, gurgle, t) + onGulps(t, share: gulpShrink)
    }

    /// The circle's radius at `t`: off the corners until the valve, the bowl from
    /// the moment the clip goes quiet.
    static func radius(_ t: Double, _ g: Geometry) -> Double {
        let start = g.reach * 1.01
        return start + (g.bowl - start) * shrink(t)
    }

    /// Softness of the screen's corners in `extent`. A true rectangle (∞) would
    /// crease the picture along its diagonals; 8 rounds the corners only just.
    static let cornerPower: Double = 8

    /// How far the screen's edge is from the centre along the unit direction
    /// `(dx, dy)`: a rounded rectangle, in polar form.
    static func extent(_ dx: Double, _ dy: Double, _ g: Geometry) -> Double {
        let across = pow(abs(dx) / (g.width / 2), cornerPower) + pow(abs(dy) / (g.height / 2), cornerPower)
        return pow(across, -1 / cornerPower)
    }

    /// How much the picture is squeezed along the turned direction `(tx, ty)`, for
    /// the pixels along the screen direction `(dx, dy)`: the edge of what can be seen
    /// that way, the circle or the screen, whichever is nearer, lands on the edge of
    /// the picture. So there is never a gap inside the circle at any angle, and with
    /// no turn and a circle past the corners it is exactly 1.
    static func squeeze(_ tx: Double, _ ty: Double, along dx: Double, _ dy: Double,
                        _ t: Double, _ g: Geometry) -> Double {
        extent(tx, ty, g) / min(radius(t, g), extent(dx, dy, g))
    }

    // MARK: - Around

    /// Radians the picture has turned by the time it is gone: a little over a turn,
    /// most of it once it is inside the circle. A little is the brief: the eye has
    /// to read a screen shrinking, not a spiral.
    static let totalTurn: Double = 7
    /// How much more the middle has turned than the rim: enough to look like water
    /// carrying it, far too little to wind it up.
    static let twist: Double = 0.35

    /// Turned so far at the rim, counter-clockwise on the glass. Exactly 0 before
    /// the valve, and it stops with the picture.
    static func turn(_ t: Double) -> Double {
        guard t > valve else { return 0 }
        return totalTurn * pow((min(t, drained) - valve) / (drained - valve), 2.6)
    }

    /// The photograph's angle under radius `r` lags the screen by this much.
    static func spin(_ r: Double, _ t: Double, _ g: Geometry) -> Double {
        turn(t) * (1 + twist * max(0, 1 - r / radius(t, g)))
    }

    /// One pixel of the screen, offset `(x, y)` from the centre with y down, to the
    /// photograph's offset: turn, then squeeze along the turned direction. The
    /// shader runs these same steps on the same `spin`, `extent` and `radius`, and
    /// `testTheShaderSamplesWhereTheMathsSays` holds it to them.
    static func source(of x: Double, _ y: Double, _ t: Double, _ g: Geometry) -> (x: Double, y: Double) {
        let r = (x * x + y * y).squareRoot()
        guard r > 0 else { return (0, 0) }
        let a = spin(r, t, g)
        let qx = x * cos(a) - y * sin(a), qy = x * sin(a) + y * cos(a)
        let s = squeeze(qx / r, qy / r, along: x / r, y / r, t, g)
        return (s * qx, s * qy)
    }

    // MARK: - The water

    /// How much of the picture the water has replaced, 0…1: it creeps in once the
    /// circle is whole on the screen, and each gulp takes a bite. Exactly 1 on the
    /// clip's dead cut.
    static func water(_ t: Double) -> Double {
        0.46 * smooth(2.9, gurgle, t) + onGulps(t, share: 0.18)
    }

    /// Height of the waves that never quite stop: "trembles gently".
    static let gentle: Double = 0.42

    /// Height of the waves, 0…1: at their highest on the last gulp, then falling
    /// to `gentle` and staying there, through the fade.
    static func chop(_ t: Double) -> Double {
        t <= drained ? 1 : gentle + (1 - gentle) * exp(-(t - drained) / 0.35)
    }

    /// The ring the last of the picture sets off in the bowl, running from the
    /// middle to the rim: its slope, which is what lights a wave. Dying with `chop`.
    static func ringSlope(_ r: Double, _ t: Double, _ g: Geometry) -> Double {
        guard t > drained else { return 0 }
        let front = (t - drained) * g.bowl / 0.45
        let length = 0.24 * g.bowl
        let trail = smooth(front, front - length, r)
        let dying = (chop(t) - gentle) / (1 - gentle)
        return 1.4 * dying * trail * smooth(0, 0.14 * g.bowl, r) * sin(2 * .pi * (front - r) / length)
    }

    /// How much of the overlay is left, the same number for every pixel on the
    /// screen: that is all "at once, uniformly" asks of this function.
    static func fadeOut(_ t: Double) -> Double { 1 - smooth(settled, fadeEnds, t) }

    // MARK: - The table

    /// One ring of pixels, in the layout the shader reads. Two `float4`s.
    struct Row {
        /// `spin, inside the circle (1) or outside (0), nearness to the rim, ring slope`
        var warp = SIMD4<Float>(repeating: 0)
        /// `the water's reach on this ring, alpha, 0, 0`
        var wash = SIMD4<Float>(repeating: 0)
    }

    /// Writes one frame's rings. `picture` false is the no-Screen-Recording run:
    /// there is no photograph, so the black and the water fade in over the live
    /// desktop instead of replacing it.
    static func fill(_ rows: UnsafeMutableBufferPointer<Row>, step: Double, t: Double,
                     geometry g: Geometry, picture: Bool) {
        let rim = radius(t, g)
        let alpha = (picture ? 1 : smooth(valve, rush, t) * 0.92) * fadeOut(t)
        let flooded = water(t)

        for i in rows.indices {
            let r = Double(i) * step
            var row = Row()
            row.warp.x = Float(spin(r, t, g))
            // A pixel and a half of antialiasing, and then nothing at all.
            row.warp.y = Float(smooth(rim + 0.75, rim - 0.75, r))
            row.warp.z = Float(smooth(rim * 0.86, rim, r))
            row.warp.w = Float(ringSlope(r, t, g))
            // Comes in from the rim, its front broken up by the waves in the shader.
            row.wash.x = Float(flooded * 1.9 - 0.4 + 0.5 * (min(1, r / rim) - 0.5))
            row.wash.y = Float(alpha)
            rows[i] = row
        }
    }
}
