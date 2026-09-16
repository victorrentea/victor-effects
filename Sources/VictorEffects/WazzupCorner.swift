import AppKit
import QuartzCore

/// 👅 Pure geometry for the Ghostface mask that leans into the **bottom-left
/// corner** while tile 69 ("wazzup") plays.
///
/// Same bargain as `HeartbeatCatFollow`: every decision is a function of the
/// overlay bounds and the image's own aspect, so it can be tested without a
/// screen. Unlike the cat, the corner is **fixed** — the mask is cut out facing
/// right-ish (it was mirrored on the way into `assetsDir`, see `assetName`), so
/// standing in the left corner it already looks *into* the desktop rather than
/// off the edge, and there is nothing to decide at run time.
enum WazzupCorner {

    /// The cut-out mask, expected in `EffectsConfig.assetsDir` — a frame lifted
    /// from a stock mask sheet, background flood-filled to alpha and **mirrored
    /// horizontally**, so it is deliberately **not in this repo** (same rule as
    /// `brother_full.gif` and `scared_cat.gif`). Missing ⇒ one log line and no
    /// overlay; the clip still plays.
    static let assetName = "wazzup.png"

    /// The clip the overlay is glued to. Its real length decides how long the
    /// mask stays up (`fallbackDuration` only when the file cannot be measured).
    static let soundName = "69_scream_ghost.mp3"

    /// Measured 5.56 s. Only used when `soundsDir` has no copy to ask.
    static let fallbackDuration: Double = 5.6

    /// **20 % bigger on screen than the box used to be, side to side.** Victor's
    /// ask ("fă-o mai mare cu 20%") reads most naturally as 20 % bigger to the
    /// eye — each side scaled by 1.2 — not 20 % more area, which would only look
    /// ~9.5 % bigger per side and quietly undershoot what he asked for. The box
    /// used to be sized so its AREA was a fifth of the screen (√0.2 per side,
    /// ≈ 0.4472); this is that same side fraction scaled by 1.2. The aspect-fit
    /// inside it still means the mask covers rather less than the box, because
    /// it fills one dimension and falls short on the other.
    static let boxSideFraction: CGFloat = 0.5366563145999494  // √0.2 × 1.2

    /// The mask's resting frame in overlay coordinates (bottom-origin, y up):
    /// aspect-fit into the box and pinned **flush to the bottom-left corner**.
    /// The letterboxing is spent *away* from that corner — the corner is the
    /// placement, the slack is not. This is where the slide-in
    /// (`slideInStartFrame`) ends up.
    static func frame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let box = CGSize(width: bounds.width * boxSideFraction,
                         height: bounds.height * boxSideFraction)
        guard imageSize.width > 0, imageSize.height > 0,
              box.width > 0, box.height > 0 else {
            return CGRect(origin: .zero, size: box)
        }
        let aspect = imageSize.width / imageSize.height
        var w = box.width
        var h = w / aspect
        if h > box.height {
            h = box.height
            w = h * aspect
        }
        return CGRect(x: 0, y: 0, width: w, height: h)
    }

    /// Where the mask starts before it slides in: the resting `frame`, shifted
    /// left by its own width so its right edge lands exactly on the left screen
    /// edge (`maxX == 0`) — fully off-screen, not a corner still touching it.
    /// Same y as the resting frame: Victor asked for the ghost to slide in from
    /// the left, not to arrive diagonally, so there is nothing to decide
    /// vertically.
    static func slideInStartFrame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let rest = frame(imageSize: imageSize, in: bounds)
        return rest.offsetBy(dx: -rest.width, dy: 0)
    }
}
