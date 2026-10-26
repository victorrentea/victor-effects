import AppKit

/// 🐕 Where tile #44's barking dog (`44_small_dog.mp3`) stands.
///
/// The dog is Maresch&Sturm's "Basti is barking" (Dribbble), cut out with a
/// BiRefNet matte per frame and **re-timed to this clip**: his mouth opens on
/// every one of its ten barks and he jumps a little on each, higher on the
/// louder ones (onsets measured from the clip's RMS on a 20 ms grid). The GIF
/// lasts the clip's 5.05 s, so it must never be looped or stretched: frame time
/// is the sync. It lives in `assetsDir`, not in this repo.
enum SmallDogBark {

    /// Height of the dog at rest as a share of the screen's — the box Victor
    /// marked on screen (1072 of 2234 px), the same 48 % the 🐺 wolf stands in.
    static let heightFraction: CGFloat = 0.48

    /// Empty room above the dog in the GIF for the jump, as a share of the
    /// dog's own height. The canvas is drawn that much taller, so the dog
    /// itself keeps `heightFraction`.
    static let jumpHeadroom: CGFloat = 0.12

    /// Gap between the dog and the left edge, as a share of the width — the
    /// wolf's 4 %. Bottom-LEFT (Victor, 2026-10-26, after a first try on the
    /// right): the dog faces right, so from this corner he barks into the
    /// desktop instead of at the screen's edge.
    static let leftInsetFraction: CGFloat = 0.04

    /// The GIF's frame in overlay coordinates (bottom-origin, y up): feet on
    /// the bottom edge, left side 4 % in from the left edge, the GIF's aspect.
    static func frame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let h = bounds.height * heightFraction * (1 + jumpHeadroom)
        let w = imageSize.height > 0 ? h * imageSize.width / imageSize.height : h
        return CGRect(x: bounds.minX + bounds.width * leftInsetFraction,
                      y: bounds.minY, width: w, height: h)
    }
}
