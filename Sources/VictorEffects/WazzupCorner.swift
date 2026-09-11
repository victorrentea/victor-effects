import AppKit
import QuartzCore

/// 👅 Pure geometry for the Ghostface mask that leans into the **bottom-left
/// corner** while tile 69 ("wazzup") plays.
///
/// Same bargain as `HeartbeatCatCorner`: every decision is a function of the
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

    /// **A fifth of the screen's area.** Area, not side: a box of 20 % *per side*
    /// would be a stamp nobody reads from the back of a room, and 20 % per side
    /// of the area is what Victor asked for. √0.2 ≈ 0.4472 of the width by the
    /// same fraction of the height therefore gives 0.2 of the area — and the
    /// aspect-fit inside it means the mask actually covers rather less, because
    /// it fills one dimension and falls short on the other.
    static let boxSideFraction: CGFloat = 0.4472135954999579  // √0.2

    /// The mask's frame in overlay coordinates (bottom-origin, y up): aspect-fit
    /// into the fifth-area box and pinned **flush to the bottom-left corner**.
    /// The letterboxing is spent *away* from that corner — the corner is the
    /// placement, the slack is not.
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
}
