import Foundation
import simd

/// 🚽 The flush, as numbers: the desktop is the surface of the water, and it goes
/// down a round hole in the middle of the screen.
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
///   picture is not scaled down: the rings nearest the hole go first, and the
///   outer ones crowd in behind them.
/// - *Around:* a vortex turns faster the nearer the middle (`spin`), so straight
///   lines wind up into spirals. A rotation would keep them straight, and this
///   difference is the whole gag.
/// - *The shoreline:* what the hole has swallowed is gone from the outer edge, so
///   the water's edge closes in from the corners (`shoreline`) and leaves the bowl
///   dry behind it.
///
/// **Against the clip.** `66_toilet.mp3` is measured, 5.08 s, and it has three
/// parts you can see in a spectrogram: a valve, a long hiss, a gurgle cut dead.
/// The picture goes down on the gurgle's three gulps, and the last of it is gone
/// the instant the clip's noise is.
enum ToiletDrain {

    // MARK: - The clip (measured with ffmpeg in 100 ms and 20 ms windows)

    /// The whole clip. A new recording on the tile means measuring all of these
    /// again.
    static let clipSeconds: Double = 5.08
    /// The handle: −32 dB climbing to −15 dB, the first swell of water. Before it
    /// the screen is the desktop, pixel for pixel.
    static let valve: Double = 0.45
    /// Broadband noise jumps in at −13 dB: the bowl is rushing. The hole is fully
    /// open by here.
    static let rush: Double = 1.3
    /// The hiss gives way to a low boom (zero crossings fall from 2 kHz to 300 Hz).
    static let gurgle: Double = 3.72
    /// Where each of the gurgle's three pulses starts and ends, between the dips
    /// at 3.96 and 4.24. Each one is a swallow of picture.
    static let gulps: [(from: Double, to: Double, share: Double)] = [
        (3.72, 3.98, 0.16), (4.03, 4.26, 0.15), (4.30, 4.47, 0.13),
    ]
    /// −12.6 dB to −35 dB inside 40 ms: the bowl is empty, and so is the screen.
    static let drained: Double = 4.47
    /// The room tone left after it is the desktop's time to come back, so it is
    /// back when the clip ends and nobody waits for it in silence.
    static let refillEnds: Double = clipSeconds
    /// The layer outlives the last visible frame by this much, so the frame it
    /// leaves on is an empty one and the removal is never what gives the desktop
    /// back.
    static let tailAllowance: Double = 0.15
    /// What `trackEffect` is given: the rule that every show ends itself.
    static let totalSeconds: Double = refillEnds + tailAllowance

    // MARK: - The hole

    /// As Victor asked: round, 10 % of the screen.
    static let holeAreaFraction: Double = 0.10

    /// Everything in pixels of the picture being drawn.
    struct Geometry {
        let width: Double
        let height: Double

        /// The hole's radius once open. An area, so it is a circle of the same
        /// tenth of the screen on any aspect ratio.
        var holeRadius: Double { (ToiletDrain.holeAreaFraction * width * height / .pi).squareRoot() }
        /// Centre to corner: the last water to arrive at the hole.
        var reach: Double { (width * width + height * height).squareRoot() / 2 }
    }

    /// Smooth 0…1 from `from` to `to`, which may run downhill.
    static func smooth(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let u = to == from ? (x < from ? 0 : 1) : min(1, max(0, (x - from) / (to - from)))
        return u * u * (3 - 2 * u)
    }

    /// How open the hole is, 0…1 of its radius: it starts with the valve and is
    /// all the way open when the rush arrives.
    static func holeOpening(_ t: Double) -> Double { smooth(valve, rush, t) }

    /// The radius of the hole at `t`.
    static func holeRadius(_ t: Double, _ g: Geometry) -> Double { g.holeRadius * holeOpening(t) }

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

    /// The `r²` that has gone down the hole, in px².
    private static func sunk(_ t: Double, _ g: Geometry) -> Double {
        drain(t) * (g.reach * g.reach - g.holeRadius * g.holeRadius)
    }

    /// Which ring of the photograph is at radius `r` at `t`: every ring has lost
    /// the same `r²`, so the water near the hole has travelled furthest in radius
    /// and the area it covers is conserved. The identity before the valve.
    static func sourceRadius(_ r: Double, _ t: Double, _ g: Geometry) -> Double {
        (r * r + sunk(t, g)).squareRoot()
    }

    /// The radius the water still reaches. Past the screen's corners until the
    /// valve; at the rim of the hole when `drain` is 1.
    static func shoreline(_ t: Double, _ g: Geometry) -> Double {
        (g.reach * g.reach - sunk(t, g)).squareRoot()
    }

    // MARK: - Around

    /// Radians the water at the rim has turned at the end, ~6.5 turns. The corners
    /// do about a third of that, so they are seen to go around too.
    static let rimTurn: Double = 41
    /// The angular speed falls as `1/r^1.15`, softened from the `1/r²` of the
    /// textbook's free vortex: on a 16:10 screen that one leaves the corners nearly
    /// still, and the whole picture has to be seen going around.
    static let vortexFalloff: Double = 1.15
    /// Exponent on the clock: the speed itself grows through the whole clip.
    static let spinUp: Double = 2.7
    /// How tightly the suction alone winds the picture, radians per e-fold of
    /// `r²`. The spiral is what a sink adds to a vortex: lines arrive at the hole
    /// nearly tangential, not along a radius.
    static let suctionWind: Double = 0.9

    /// Turned so far at the rim of the hole, radians.
    static func rimAngle(_ t: Double) -> Double {
        guard t > valve else { return 0 }
        return rimTurn * pow(min(t, drained) - valve, spinUp) / pow(drained - valve, spinUp)
    }

    /// What share of the rim's turn the water at `r` does: 1 well inside the rim,
    /// falling with the distance. A soft core, so it stays finite while the hole
    /// is still a dimple.
    static func vortexShare(_ r: Double, _ g: Geometry) -> Double {
        1 / (1 + pow(r / g.holeRadius, vortexFalloff))
    }

    /// The photograph's angle under radius `r` lags the screen by this much,
    /// counter-clockwise on the glass, radians. Exactly 0 before the valve.
    static func spin(_ r: Double, _ t: Double, _ g: Geometry) -> Double {
        let vortex = 2 * rimAngle(t) * vortexShare(r, g)
        let wind = suctionWind * log((r * r + sunk(t, g) + 1) / (r * r + 1))
        return vortex + wind
    }

    /// Angular speed of the water at `r`, radians a second, numerically: what the
    /// eye reads, and the promise under test (faster near the hole, faster later).
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

    // MARK: - The look

    /// How deep the funnel has got, 0…1: it shows with the rush and is at full
    /// depth when the gurgle starts.
    static func funnel(_ t: Double) -> Double { smooth(valve, gurgle, t) }

    /// The desktop coming back: 0 until the bowl has stood empty for a beat, 1 at
    /// the clip's end. Fresh water rises out of the hole, as in a real bowl, and
    /// what it brings is the live desktop.
    static func refill(_ t: Double) -> Double { smooth(drained + 0.08, refillEnds, t) }

    /// One ring of pixels, in the layout the shader reads. Four `float4`s.
    struct Row {
        /// `source radius, spin, light on the picture, water tint`
        var warp = SIMD4<Float>(repeating: 0)
        /// `foam strength, foam phase, ripple px, ripple phase`
        var wave = SIMD4<Float>(repeating: 0)
        /// `what is under the water, rgb; the hole is simply its darkest part`
        var under = SIMD4<Float>(repeating: 0)
        /// `water cover, foam at its edge, alpha, 0 inside the hole's rim and 1 outside`
        var mix = SIMD4<Float>(repeating: 0)
    }

    /// The bowl's wall: pale china near the screen's edge going down into the dark,
    /// then the hole: near-black, a little light caught just inside its lip, and
    /// the one hard edge in the picture, because that edge is what makes it read
    /// as a hole and not as a shadow.
    static func bowl(_ r: Double, _ t: Double, _ g: Geometry) -> SIMD3<Float> {
        let hole = holeRadius(t, g)
        let wall = smooth(0, 1, (r - hole) / max(g.reach - hole, 1))
        let china = SIMD3<Float>(0.86, 0.88, 0.90)
        let shadow = SIMD3<Float>(0.09, 0.12, 0.15)
        let lit = shadow + (china - shadow) * Float(pow(wall, 0.55))
        let throat = Float(pow(max(0, r / max(hole, 1)), 6))
        let pit = SIMD3<Float>(0.008, 0.011, 0.016) + SIMD3<Float>(0.07, 0.09, 0.11) * throat
        return lit + (pit - lit) * Float(smooth(hole + 1.2, hole - 1.2, r))
    }

    /// Writes one frame's rings. `picture` false is the no-Screen-Recording run:
    /// there is no photograph, so the water fades in over the live desktop instead
    /// of replacing it, and leaves the same way.
    static func fill(_ rows: UnsafeMutableBufferPointer<Row>, step: Double, t: Double,
                     geometry g: Geometry, picture: Bool) {
        let hole = holeRadius(t, g)
        let depth = funnel(t)
        let shore = shoreline(t, g)
        let back = refill(t)
        // The front of the fresh water, off the corners when `back` is 1.
        let front = (g.reach * 1.18) * back
        let soft = g.reach * 0.14
        let fadeIn = picture ? 1 : smooth(0, rush, t) * 0.92
        let rim = max(g.holeRadius, 1)
        let turned = rimAngle(t)

        for i in rows.indices {
            let r = Double(i) * step
            let near = exp(-max(0, r - hole) / (0.95 * rim))
            let tight = 3.2 * log(max(r, 1) / rim)

            var row = Row()
            row.warp.x = Float(sourceRadius(r, t, g))
            row.warp.y = Float(spin(r, t, g))
            row.warp.z = Float(1 - depth * (0.28 + 0.62 * near))
            row.warp.w = Float(depth * (0.10 + 0.30 * near))

            row.wave.x = Float(depth * (0.06 + 0.34 * near))
            row.wave.y = Float(-tight * 5 + 3.5 * turned)
            row.wave.z = Float(depth * 0.012 * g.reach * (0.4 + near))
            row.wave.w = Float(-tight * 3 + 9 * t)

            let lit = bowl(r, t, g)
            row.under = SIMD4<Float>(lit.x, lit.y, lit.z, 0)

            // The water's edge, parked beyond the corners by `band` at rest so the
            // first frames are the photograph and nothing else.
            let band = g.reach * 0.02
            let wet = smooth(shore + 2 * band, shore, r)
            let foamLine = exp(-pow((r - shore - band) / (band * 0.9), 2))
            let lip = exp(-max(0, r - hole) / (0.05 * rim)) * depth * 0.45
            let gone = smooth(drained - 0.05, drained, t)
            row.mix.x = Float(wet * (1 - gone))
            row.mix.y = Float((foamLine * smooth(valve, rush, t) * 0.75 + lip) * (1 - gone))
            row.mix.z = Float(fadeIn * smooth(front - soft, front + soft, r + (back > 0 ? 0 : soft * 2)))
            row.mix.w = Float(smooth(hole - 1.2, hole + 1.2, r))
            rows[i] = row
        }
    }
}
