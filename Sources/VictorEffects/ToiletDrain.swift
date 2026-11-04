import Foundation
import simd

/// 🚽 The flush, as numbers: the desktop is the surface of the water, and it goes
/// down the middle of the screen.
///
/// **There is no hole** (Victor, 2026-11-04: first a dark disc, then none at all).
/// The eye reads the drain from the motion alone: the picture collapses into its
/// own spiral, which tightens and speeds up into the middle. So nothing here may
/// darken towards the centre: a dark disc or ring would stand in for a hole.
///
/// Everything the picture does depends on **the distance from the centre and the
/// time**, and on nothing else, which is what keeps this file pure and the shader
/// dumb: for each frame `fill` writes a table with one `Row` per ring of pixels,
/// and `ToiletDrainRenderer` only looks the ring up. There is no second copy of
/// this maths in Metal, so what the tests here pin is what lands on the glass.
///
/// **The flow is a bath drain's, not a rotation:**
///
/// - *Inward:* water cannot be compressed, so a sink takes the same area at any
///   radius and `r²` falls by the same amount everywhere (`sourceRadius`). The
///   picture is not scaled down: the rings nearest the middle go first, and the
///   outer ones crowd in behind them.
/// - *Around:* a vortex turns faster the nearer the middle (`spin`), so straight
///   lines wind up into spirals. A rotation would keep them straight, and this
///   difference is the whole gag.
/// - *The shoreline:* what has gone down is gone from the outer edge, so the
///   picture's edge closes in from the corners (`shoreline`) over the water left
///   behind it, and shrinks to a point in the middle.
///
/// **The ending** is that water: its waves calm down (`calm`), and once it has
/// settled a little the whole screen fades to the live desktop at once (`fadeOut`).
///
/// **Against the clip.** `66_toilet.mp3` is measured, 5.08 s, and it has three
/// parts you can see in a spectrogram: a valve, a long hiss, a gurgle cut dead.
/// The picture goes down on the gurgle's three gulps, and the last of it is gone
/// the instant the clip's noise is. The calming cannot fit in the 0.6 s of room tone
/// left, so the end runs ~1 s past the audio, in silence, as settling water does.
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
    /// at 3.96 and 4.24. Each one is a swallow of picture.
    static let gulps: [(from: Double, to: Double, share: Double)] = [
        (3.72, 3.98, 0.16), (4.03, 4.26, 0.15), (4.30, 4.47, 0.13),
    ]
    /// −12.6 dB to −35 dB inside 40 ms: the bowl is empty, and so is the picture.
    static let drained: Double = 4.47

    // MARK: - The ending (past the clip's 5.08 s: this part is silent on purpose)

    /// Seconds for the waves to fall to 1/e after the last of the picture goes.
    static let calmTime: Double = 0.55
    /// "Once the water has settled a little": the fade starts here, with the waves
    /// at ~17 %, still moving, so it does not read as a freeze before the fade.
    static let settled: Double = 5.45
    /// The whole screen is the desktop again, 0.97 s after the clip's last sound.
    static let fadeEnds: Double = 6.05
    /// The layer outlives the last visible frame by this much, so the frame it
    /// leaves on is an empty one and the removal is never what gives the desktop
    /// back.
    static let tailAllowance: Double = 0.15
    /// What `trackEffect` is given: the rule that every show ends itself.
    static let totalSeconds: Double = fadeEnds + tailAllowance

    // MARK: - The screen

    /// Everything in pixels of the picture being drawn.
    struct Geometry {
        let width: Double
        let height: Double

        /// Centre to corner: the last water to arrive at the middle.
        var reach: Double { (width * width + height * height).squareRoot() / 2 }
        /// The vortex's core. Small, and it draws nothing: the rings inside it only
        /// stop speeding up, which keeps the middle's angle finite.
        var core: Double { ToiletDrain.coreShare * reach }
    }

    /// Of `reach`: ~110 px at 3456×2234.
    static let coreShare: Double = 0.055

    /// Smooth 0…1 from `from` to `to`, which may run downhill.
    static func smooth(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let u = to == from ? (x < from ? 0 : 1) : min(1, max(0, (x - from) / (to - from)))
        return u * u * (3 - 2 * u)
    }

    // MARK: - Down

    /// Share of the steady draw in the whole drain; the three gulps are the rest.
    private static var steadyShare: Double { 1 - gulps.reduce(0) { $0 + $1.share } }

    /// How much of the picture has gone, 0…1: a draw that accelerates with the
    /// hiss, and a swallow on each pulse of the gurgle. Strictly the picture's
    /// clock: exactly 0 before the valve, exactly 1 the moment the clip goes quiet.
    static func drain(_ t: Double) -> Double {
        guard t > valve else { return 0 }
        guard t < drained else { return 1 }
        let steady = steadyShare * pow((t - valve) / (drained - valve), 2.0)
        return steady + gulps.reduce(0) { $0 + $1.share * smooth($1.from, $1.to, t) }
    }

    /// The `r²` that has gone down the middle, in px².
    private static func sunk(_ t: Double, _ g: Geometry) -> Double { drain(t) * g.reach * g.reach }

    /// Which ring of the photograph is at radius `r` at `t`: every ring has lost
    /// the same `r²`, so the water near the middle has travelled furthest in radius
    /// and the area it covers is conserved. The identity before the valve.
    static func sourceRadius(_ r: Double, _ t: Double, _ g: Geometry) -> Double {
        (r * r + sunk(t, g)).squareRoot()
    }

    /// The radius the picture still reaches. At the corners until the valve; 0 when
    /// `drain` is 1, so the last of it goes down a point.
    static func shoreline(_ t: Double, _ g: Geometry) -> Double {
        max(0, g.reach * g.reach - sunk(t, g)).squareRoot()
    }

    // MARK: - Around

    /// Radians the water at the very middle has turned at the end, ~13 turns.
    static let centreTurn: Double = 82
    /// The angular speed falls as `1/r^0.85`, far softer than the `1/r²` of the
    /// textbook's free vortex: that one leaves the corners still, and the whole
    /// picture has to be seen going around.
    static let vortexFalloff: Double = 0.85
    /// Exponent on the clock: the speed itself grows through the whole clip.
    static let spinUp: Double = 2.7
    /// How tightly the suction alone winds the picture, radians per e-fold of
    /// `r²`. This term has no core, so it is what keeps the spiral tightening right
    /// into the middle, where a hole used to hide the question.
    static let suctionWind: Double = 1.1

    /// Turned so far at the very middle, radians.
    static func centreAngle(_ t: Double) -> Double {
        guard t > valve else { return 0 }
        return centreTurn * pow(min(t, drained) - valve, spinUp) / pow(drained - valve, spinUp)
    }

    /// What share of the middle's turn the water at `r` does.
    static func vortexShare(_ r: Double, _ g: Geometry) -> Double {
        1 / (1 + pow(r / g.core, vortexFalloff))
    }

    /// The photograph's angle under radius `r` lags the screen by this much,
    /// counter-clockwise on the glass, radians. Exactly 0 before the valve.
    static func spin(_ r: Double, _ t: Double, _ g: Geometry) -> Double {
        let vortex = centreAngle(t) * vortexShare(r, g)
        let wind = suctionWind * log((r * r + sunk(t, g) + 1) / (r * r + 1))
        return vortex + wind
    }

    /// Angular speed of the water at `r`, radians a second, numerically: what the
    /// eye reads, and the promise under test (faster inward, faster later).
    static func angularSpeed(_ r: Double, _ t: Double, _ g: Geometry) -> Double {
        let dt = 1.0 / 240
        return (spin(r, t + dt, g) - spin(r, t, g)) / dt
    }

    /// One pixel of the screen, offset `(x, y)` from the centre with y down, to the
    /// photograph's offset. Only the tests call it: the shader runs the same
    /// rotation on the same two table entries.
    static func source(of x: Double, _ y: Double, _ t: Double, _ g: Geometry) -> (x: Double, y: Double) {
        let r = (x * x + y * y).squareRoot()
        guard r > 0 else { return (0, 0) }
        let scale = sourceRadius(r, t, g) / r
        let a = spin(r, t, g)
        return (scale * (x * cos(a) - y * sin(a)), scale * (x * sin(a) + y * cos(a)))
    }

    // MARK: - The ending

    /// 1 until the last of the picture has gone, then falling away for good.
    static func calm(_ t: Double) -> Double {
        t <= drained ? 1 : exp(-(t - drained) / calmTime)
    }

    /// How hard the whirlpool is working, 0…1: it shows with the rush, is full when
    /// the gurgle starts, and dies down with the water.
    static func funnel(_ t: Double) -> Double { smooth(valve, gurgle, t) * calm(t) }

    /// The whirlpool's foam, gone within a few tenths of the last gulp: left to
    /// fade with the waves it is a pinwheel over the water, and the ending has to
    /// read as a surface settling, not as the spiral dimming.
    static func foamLeft(_ t: Double) -> Double {
        smooth(valve, gurgle, t) * (t <= drained ? 1 : exp(-(t - drained) / 0.16))
    }

    /// Height of the waves on the water left behind, 0…1.
    static func chop(_ t: Double) -> Double { (0.35 + 0.65 * smooth(valve, gurgle, t)) * calm(t) }

    /// How much of the overlay is left, the same number for every pixel on the
    /// screen: that is all "at once, uniformly" asks of this function.
    static func fadeOut(_ t: Double) -> Double { 1 - smooth(settled, fadeEnds, t) }

    /// The ring wave the last of the picture sets off as it goes down: a train
    /// running out from the middle to the corners, as a stone in a pond. Its slope,
    /// which is what lights a wave; 0 before the moment and dying with the water.
    static func ringSlope(_ r: Double, _ t: Double, _ g: Geometry) -> Double {
        guard t > drained else { return 0 }
        let front = (t - drained) * g.reach / 0.7
        let length = 0.15 * g.reach
        let trail = smooth(front, front - length, r)
        return 2.4 * calm(t) * trail * sin(2 * .pi * (front - r) / length)
    }

    // MARK: - The table

    /// One ring of pixels, in the layout the shader reads. Three `float4`s.
    struct Row {
        /// `source radius, spin, light on the picture, water tint`
        var warp = SIMD4<Float>(repeating: 0)
        /// `foam strength, foam phase, ripple px, ripple phase`
        var wave = SIMD4<Float>(repeating: 0)
        /// `picture cover, foam at its edge, alpha, ring wave's slope`
        var mix = SIMD4<Float>(repeating: 0)
    }

    /// The foam's turn: the spin's, and it runs on into the calm instead of
    /// stopping dead when the clock of `centreAngle` does.
    private static func foamTurn(_ t: Double) -> Double {
        guard t > drained else { return centreAngle(t) }
        let speed = centreTurn * spinUp / (drained - valve)
        return centreTurn + speed * calmTime * (1 - calm(t))
    }

    /// Writes one frame's rings. `picture` false is the no-Screen-Recording run:
    /// there is no photograph, so the water fades in over the live desktop instead
    /// of replacing it.
    static func fill(_ rows: UnsafeMutableBufferPointer<Row>, step: Double, t: Double,
                     geometry g: Geometry, picture: Bool) {
        let depth = funnel(t)
        let foam = foamLeft(t)
        let shore = shoreline(t, g)
        let alpha = (picture ? 1 : smooth(0, rush, t) * 0.92) * fadeOut(t)
        let turned = foamTurn(t) * 0.42
        let gone = smooth(drained - 0.05, drained, t)
        let band = g.reach * 0.02
        let edgeShows = smooth(valve, rush, t)

        for i in rows.indices {
            let r = Double(i) * step
            let near = exp(-r / (0.5 * g.reach))
            let tight = 3.2 * log((r + g.core) / (0.5 * g.reach))

            var row = Row()
            row.warp.x = Float(sourceRadius(r, t, g))
            row.warp.y = Float(spin(r, t, g))
            // Evenly over the screen, never more towards the middle: that would be
            // the dark disc this effect is not allowed to have.
            row.warp.z = Float(1 - 0.10 * depth)
            row.warp.w = Float(depth * (0.12 + 0.30 * near))

            row.wave.x = Float(foam * (0.08 + 0.42 * near))
            row.wave.y = Float(-tight * 5 + 3.5 * turned)
            row.wave.z = Float(depth * 0.012 * g.reach * (0.4 + near))
            row.wave.w = Float(-tight * 3 + 9 * t)

            // The picture's edge, parked beyond the corners by `band` at rest so
            // the first frames are the photograph and nothing else.
            let wet = smooth(shore + 2 * band, shore, r)
            let foamLine = exp(-pow((r - shore - band) / (band * 0.9), 2))
            row.mix.x = Float(wet * (1 - gone))
            row.mix.y = Float(foamLine * edgeShows * 0.75 * (1 - gone))
            row.mix.z = Float(alpha)
            row.mix.w = Float(ringSlope(r, t, g))
            rows[i] = row
        }
    }
}
