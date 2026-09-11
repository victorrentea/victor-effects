import CoreGraphics

/// 🐶 Pure geometry for the dog that keeps the 💓 heartbeat company. Everything
/// the dog has to decide is a function of the overlay bounds, its own box and one
/// point, so it lives out here where it can be tested without a screen — the same
/// bargain as `HeartbeatBump` and `CropFlashGeometry`.
///
/// **It used to be the exact opposite.** Until 2026-09-06 this file was
/// `HeartbeatDogFlee`: the dog bolted to the half of the screen the cursor was
/// not in. That joke stopped working once Victor started *zooming the room's
/// projector in on the beat* — the dog was then reliably in the half nobody was
/// looking at, i.e. off the projected frame entirely. So the rule inverted: the
/// dog is now **adjacent to the beat**, parked right up against the pulsing disc
/// with its **face** — not its centre — as the thing held near the lens. Since
/// 2026-09-10 it stands **30 % closer than the strict clearance** (`closeness`), so
/// the ear leans *into* the disc instead of resting on its edge — "beside the beat"
/// became "up in the beat's face".
///
/// Three decisions, in the order they constrain each other:
///
/// 1. **Which side of the cursor.** The one with more room — decided **once**,
///    on the first poll of a run, and then kept for the whole heartbeat
///    (Victor, 2026-09-09). Re-deciding it every poll is what used to send the
///    dog leaping across the beat whenever the pointer crossed the midline.
/// 2. **How high.** Decided *before* the horizontal, because it is the pinned
///    one: the face rides at the cursor's own height, but the photo's bottom edge
///    is **never lifted off the floor of the screen** — it may go below, never
///    above (Victor, 2026-09-06). A beat low on the screen therefore leaves most
///    of the dog under the frame; a beat high on it does not lift the dog at all,
///    it just leaves the dog standing beneath the beat.
/// 3. **How far along that side.** Only as far as the ear needs to clear the
///    lens, times `closeness` — and standing *below* the beat already pays part of
///    that, so the higher the beat, the closer in the dog tucks. If the frame will not give
///    the rest, the dog's *back* may hang off the outer edge up to
///    `maxBackOverflow`: a cropped rump is a cheaper failure than a face dragged
///    away from the beat.
///
/// Coordinates are the overlay's: bottom-origin, y growing upward.
enum HeartbeatDogFollow {

    // MARK: - The silhouette, measured off the asset

    /// Where the dog's face sits inside `heartbeat-dog.png` (1024 × 1162, muzzle
    /// pointing right), as a fraction of the box: x from the left edge, y from
    /// the **top**. This is the point the whole placement is written around —
    /// "put the dog near the beat" is really "put *this* point near the beat",
    /// and the difference between the two is most of the dog.
    static let faceFracX: CGFloat = 0.60
    static let faceFracYFromTop: CGFloat = 0.15

    /// The far edge of the silhouette on the muzzle's side, at head height — the
    /// ear and cheek reach 0.86 while the muzzle itself stops around 0.72, so the
    /// ear is what actually has to clear the disc. Measured off the alpha channel
    /// at a 60/255 threshold, not eyeballed.
    ///
    /// The chest lower down is wider still (0.99), but it sits ~400 pt below the
    /// face, where the lens circle has already curved away by more than the extra
    /// width — checked against the retina numbers, it clears.
    static let headSideFracX: CGFloat = 0.86

    /// The other ear runs right off the opposite edge of the trimmed PNG, so the
    /// back of the silhouette is the box edge.
    static let backSideFracX: CGFloat = 0.0

    /// Face → near edge of the silhouette, horizontally. This is the slack that
    /// has to be added on top of the lens radius so that the *ear*, not the face,
    /// is what sits on the circle.
    static func faceToNearEdge(boxWidth: CGFloat) -> CGFloat {
        boxWidth * (headSideFracX - faceFracX)
    }

    /// Face → back edge of the silhouette. What decides how far the dog can be
    /// pushed outward before its rump leaves the frame.
    static func faceToBackEdge(boxWidth: CGFloat) -> CGFloat {
        boxWidth * (faceFracX - backSideFracX)
    }

    /// Face → top of the box, i.e. how far the ears rise above the face. The
    /// sink-below-the-beat fallback has to clear *those*, not the face.
    static func faceToTop(boxHeight: CGFloat) -> CGFloat {
        boxHeight * faceFracYFromTop
    }

    /// The highest the face may ever ride: the one that puts the **bottom edge of
    /// the photo exactly on the bottom edge of the screen**.
    ///
    /// This is a hard rule, not a preference (Victor, 2026-09-06): the dog's
    /// bottom edge may be *below* the screen's, never above it. The photo is
    /// cropped at the chest, so a gap underneath turns it from a dog leaning into
    /// frame into a sticker floating in mid-air — the one thing the whole
    /// bottom-aligned framing exists to avoid. A beat up near the top of the
    /// screen therefore does not lift the dog; it makes the dog stand under the
    /// beat instead of beside it, which `facePoint` then cashes in for a much
    /// closer horizontal placement.
    static func bottomAnchoredFaceY(boxHeight: CGFloat) -> CGFloat {
        boxHeight * (1 - faceFracYFromTop)
    }

    /// Where the face anchor sits relative to the layer's `position` (its centre),
    /// for the facing the dog will have on that side. The layer is mirrored by a
    /// scale about its own centre, so the x offset simply flips with it.
    static func faceOffset(onRight: Bool, boxSize: CGSize) -> CGVector {
        CGVector(dx: (onRight ? -1 : 1) * (faceFracX - 0.5) * boxSize.width,
                 dy: (0.5 - faceFracYFromTop) * boxSize.height)
    }

    // MARK: - Which side

    /// Breathing room between the silhouette and the edge of the lens. Small on
    /// purpose: "as close as possible without overlapping" was the ask, so this
    /// is the width of "not touching", not a comfortable gap. It is scaled by
    /// `closeness` along with the radius, so it no longer buys any clearance at
    /// all — it survives as the thing that keeps the two numbers in one ratio.
    static let clearMargin: CGFloat = 18

    /// How much of the geometric clearance is actually kept. 1.0 is the strict
    /// answer — the ear exactly on the circle, which is what this file computed
    /// until 2026-09-10; 0.70 pulls the dog **30 % closer to the centre of the
    /// beat** (Victor, 2026-09-10) and therefore lets the ear overlap the lens.
    ///
    /// The overlap is the point, not a regression. The lens is a *distortion*,
    /// not a drawn disc: its outer ring barely moves a pixel, so an ear a few
    /// tens of points inside the radius covers nothing anyone was looking at,
    /// while the strict placement read as a dog standing politely aside from the
    /// beat rather than leaning into it. Applied to `want`, so both the sideways
    /// gap and the sink-below-the-beat fallback shrink by the same factor and the
    /// placement stays one consistent circle.
    static let closeness: CGFloat = 0.70

    /// How much of the box may hang off the outer edge of the screen, as a
    /// fraction of its width — the rump, always, since the dog faces inward.
    /// Clamping the box fully into frame instead would shove the face back inside
    /// the pulsing disc, which is the one thing this placement exists to avoid.
    static let maxBackOverflow: CGFloat = 0.25

    /// Dead band around the midline, as a fraction of the width, inside which the
    /// previous answer stands. It used to be the thing that kept a cursor parked
    /// on the seam from making the dog oscillate; now that the side is asked for
    /// exactly once per run, it is what decides a cursor sitting *on* the seam —
    /// `wasOnRight` is false there, so a dead-centre pointer puts the dog on its
    /// left.
    static let midlineHysteresis: CGFloat = 0.04

    /// Which side of the cursor the dog stands on: **the side with more room**,
    /// which for a cursor in the left half is the right. Inside the dead band the
    /// previous answer stands. Asked once per heartbeat — see the note up top.
    static func shouldBeOnRight(cursorX: CGFloat, wasOnRight: Bool, boundsWidth: CGFloat) -> Bool {
        let mid = boundsWidth / 2
        let band = boundsWidth * midlineHysteresis
        if cursorX < mid - band { return true }    // cursor left  → dog to its right
        if cursorX > mid + band { return false }   // cursor right → dog to its left
        return wasOnRight
    }

    // MARK: - Where the face goes

    /// Lowest the face is allowed to sink when the frame forces the dog under the
    /// beat, as a fraction of the height — but never *above* the cursor, because
    /// a cursor already down at the floor is a beat down at the floor, and the
    /// face belongs beside it.
    static let faceFloorFraction: CGFloat = 0.10

    /// The face anchor's target, in overlay points.
    ///
    /// **Height is decided first**, because it is the constrained one: the face
    /// rides at the cursor's own height, capped by `bottomAnchoredFaceY` so the
    /// photo's bottom edge is never lifted off the floor of the screen. Below
    /// that cap it sinks freely — a beat low on the screen leaves most of the dog
    /// under the frame, which is the intended look.
    ///
    /// **The horizontal then only has to make up the difference.** The constraint
    /// is that the near-top corner of the silhouette — the ear on the beat's side
    /// — stays outside the `closeness`-shrunk lens circle, and being *below* the
    /// beat already buys part of that distance. So a beat high on the screen, which pins the dog to
    /// the floor far beneath it, lets the dog stand almost directly under the
    /// circle instead of off to one side. Only the drop *below the cursor* counts:
    /// while the ears are still above it, the near edge runs straight through the
    /// cursor's own height and the horizontal gap has to carry the whole radius.
    ///
    /// If the frame will not give that gap, two fallbacks, in order: **sink
    /// further** (free — the bottom edge is open, and it stops only at
    /// `faceFloorFraction`, where the face itself would go out of sight), then
    /// **step sideways past `maxBackOverflow`**, with the face staying inside the
    /// frame as the only hard stop. Overlapping the beat is the failure worth
    /// paying to avoid: the dog is a *sibling* of the capture layer, so it never
    /// pulses — it would just cover the one part of the screen the projector is
    /// zoomed into. Since the lens shrank to half the screen height, neither
    /// fallback is reached on the retina.
    static func facePoint(onRight: Bool, cursor: CGPoint, boxSize: CGSize,
                          clearRadius: CGFloat, bounds: CGRect) -> CGPoint {
        let near = faceToNearEdge(boxWidth: boxSize.width)
        let back = faceToBackEdge(boxWidth: boxSize.width)
        let ears = faceToTop(boxHeight: boxSize.height)
        let want = (clearRadius + clearMargin) * closeness
        let dir: CGFloat = onRight ? 1 : -1

        // 1. Height: track the cursor, but never lift the photo off the floor.
        var faceY = min(cursor.y, bottomAnchoredFaceY(boxHeight: boxSize.height))
        // How far the ear tip has dropped below the beat. Clamped at zero: while
        // the ears are above the cursor the near edge spans its height, so none
        // of that separation is real clearance.
        var below = max(0, cursor.y - faceY - ears)

        // The horizontal gap that, with `below` already in hand, puts the corner
        // on the circle.
        func sidestep(_ below: CGFloat) -> CGFloat {
            (max(0, want * want - below * below)).squareRoot()
        }

        // A dog wider than the screen has no placement worth the name.
        let slack = boxSize.width * maxBackOverflow
        let lo = back - slack, hi = bounds.width - back + slack
        guard lo <= hi else { return CGPoint(x: bounds.width / 2, y: faceY) }

        // 2. Horizontal, on its budget.
        var faceX = min(max(cursor.x + dir * (sidestep(below) + near), lo), hi)
        let gap = max(0, abs(faceX - cursor.x) - near)   // cursor → near edge

        // 3. Short? Sink further, then step out past the budget. Worked as a
        //    target height rather than a delta: `below` is clamped at zero while
        //    the ears are above the cursor, so adding a sink to it would lose
        //    exactly one ear's worth of drop.
        // The comparison carries a hair of slack: the placement above aims at
        // exactly `want`, so an exact hit lands on this boundary and rounding
        // alone decides which way it falls. Without the slack a perfectly good
        // placement trips the fallback and sinks the dog a whole ear for nothing.
        if gap * gap + below * below < want * want * (1 - 1e-9) {
            let credit = (want * want - gap * gap).squareRoot()   // drop still needed
            faceY = max(cursor.y - ears - credit, min(faceY, bounds.height * faceFloorFraction))
            below = max(0, cursor.y - faceY - ears)
            if below < credit {
                faceX = min(max(cursor.x + dir * (sidestep(below) + near), 0), bounds.width)
            }
        }

        return CGPoint(x: faceX, y: faceY)
    }

    /// The layer `position` (its centre) that puts the face where `facePoint`
    /// says it goes.
    static func position(onRight: Bool, cursor: CGPoint, boxSize: CGSize,
                         clearRadius: CGFloat, bounds: CGRect) -> CGPoint {
        let face = facePoint(onRight: onRight, cursor: cursor, boxSize: boxSize,
                             clearRadius: clearRadius, bounds: bounds)
        let offset = faceOffset(onRight: onRight, boxSize: boxSize)
        return CGPoint(x: face.x - offset.dx, y: face.y - offset.dy)
    }

    // MARK: - Motion

    /// Moves shorter than this are not worth animating — the dog would twitch on
    /// every poll while the mouse drifts by a pixel.
    ///
    /// This is the only motion left. The leap that carried the dog across the
    /// beat when it changed sides (`apex` / `hopDuration`) went out with the
    /// side changes themselves on 2026-09-09.
    static let minStep: CGFloat = 4
}
