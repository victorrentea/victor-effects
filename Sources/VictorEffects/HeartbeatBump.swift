import CoreGraphics

/// 💓 Pure geometry for the **local** bulge that the heartbeat beats with.
///
/// The effect used to scale the whole captured screen 1.0 → 1.30 around the
/// cursor. That put the biggest displacement exactly where the eye is *not*
/// looking: a corner 1500 pt away from the pivot swept ~450 pt on every thump,
/// so the periphery lurched while the thing under the pointer barely moved.
/// Two beats of that reads as vertigo rather than as a pulse.
///
/// So the zoom is gone and a `CIBumpDistortion` took its place: a convex lens
/// that magnifies a disc under the cursor and is **exactly identity outside its
/// radius** — the periphery is not merely moved less, it is not moved at all.
/// What is left of the old zoom is a `breatheScale` hair of whole-screen
/// motion, pivoted at the centre so it stays symmetric.
///
/// Same bargain as `HeartbeatDogFollow` and `CropFlashGeometry`: every decision
/// here is a function of the overlay bounds, so it lives out where it can be
/// tested without a screen. `HeartbeatDogFollow` reads `radius(in:)` to know
/// what the dog has to stand clear of, so the two sizes cannot drift apart.
enum HeartbeatBump {

    /// How wide the lens reads, as a fraction of the screen **height** — its
    /// diameter, so the radius is half of this.
    ///
    /// The size has now been asked for three different ways, and the units moved
    /// each time. It began as "those 10 % of the screen under the mouse", which
    /// is an **area** (πr² = fraction · W · H). On 2026-08-27 Victor asked for it
    /// **twice as big — the size, not the amplitude**; the size of a disc is how
    /// wide it reads, so the radius doubled and the area quadrupled, 10 % → 40 %.
    /// On 2026-09-06 he pinned it outright: **diameter = half the screen height**.
    /// On 2026-09-09 he asked for **20 % larger** — again the size, not the
    /// amplitude — so 0.5 → 0.6 of the screen height.
    ///
    /// That is the better anchor and it is why the area formula is gone. A share
    /// of the *area* is a share of `W · H`, so the same lens grew and shrank with
    /// the aspect ratio of whatever display it landed on; a share of the height
    /// reads the same on the retina, on the projector and on the wide external.
    /// On the built-in (1728 × 1117 pt) it is a 558 pt disc — r ≈ 279, which
    /// lands back near the original tenth of the area, ~12.7 %.
    static let diameterFraction: CGFloat = 0.6

    /// Peak `inputScale` of the bump, i.e. how convex the lens gets at the top
    /// of a lub or a dub. 0.5 roughly doubles the middle of the disc — the same
    /// punch the old 1.30 zoom had, minus the swept periphery. Past ~0.7 the
    /// centre stretches into a fisheye smear.
    ///
    /// This is the *amplitude* Victor explicitly did NOT want changed when the
    /// lens grew: `inputScale` is relative to the radius, so a lens of twice the
    /// size bulges by the same factor over twice the distance — bigger, not
    /// punchier. It survived the shrink back to `diameterFraction` on the same
    /// grounds. Leave it where it is when resizing the lens.
    static let peakScale: CGFloat = 0.5

    /// The residual whole-screen breathe, kept deliberately tiny (the old value
    /// was 1.30). It is what stops the screen from looking frozen between the
    /// lens pulses; at 1.02 a corner travels well under 20 pt, which registers
    /// as the screen being alive rather than as the room tilting.
    static let breatheScale: CGFloat = 1.02

    /// Radius of the lens, in the overlay's points: half of `diameterFraction`
    /// of the screen height. On the retina (1728 × 1117 pt) that is ~335 pt, a
    /// 670 pt disc — three fifths of the screen tall, just under 40 % of it wide.
    ///
    /// Width is still checked, but only as a guard: a zero-sized overlay (no
    /// screen attached yet) must give 0 rather than a lens over nothing.
    static func radius(in bounds: CGRect) -> CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 0 }
        return bounds.height * diameterFraction / 2
    }

    /// The lens centre in layer points, from the unit-square cursor anchor that
    /// `layerAnchor(forGlobalMouse:…)` already computes for the effect.
    ///
    /// Deliberately **not** clamped away from the edges: with the cursor in a
    /// corner the right answer is a quarter-lens in that corner, not a whole
    /// one that has drifted inward off the pointer.
    static func center(forAnchor anchor: CGPoint, bounds: CGRect) -> CGPoint {
        CGPoint(x: anchor.x * bounds.width, y: anchor.y * bounds.height)
    }
}
