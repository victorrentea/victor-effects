import AppKit

/// 🐕 Pure decisions for tile #44 (`44_small_dog.mp3`): which of the three
/// barking dogs comes up this press, and where it stands.
///
/// The three GIFs are **re-timed to this clip** — each one opens its mouth on
/// every one of the clip's ten barks (onsets measured from the clip's RMS on a
/// 20 ms grid), and each lasts the clip's 5.05 s. So they must never be looped
/// or stretched: frame time is the sync.
///
/// They live in `assetsDir`, not in this repo: one was drawn by an image model
/// from a stock reference, two are Dribbble shots (Hugo Puente's "Barking
/// dog", Maresch&Sturm's "Basti is barking") with the backdrop keyed out.
enum SmallDogBark {

    /// Whose turn it is. Presses rotate 1 → 2 → 3 → 1 across the app's life.
    private(set) static var nextIndex = 0

    /// Picks the next dog among the files that are actually present, so a Mac
    /// with only one of them dropped in still barks — with that one every time.
    static func next<T>(of available: [T]) -> T? {
        guard !available.isEmpty else { return nil }
        defer { nextIndex += 1 }
        return available[nextIndex % available.count]
    }

    /// Height of the dog as a share of the screen's — the box Victor marked on
    /// screen (1072 of 2234 px), the same 48 % the 🐺 wolf stands in.
    static let heightFraction: CGFloat = 0.48

    /// Gap between the dog and the right edge, as a share of the width.
    static let rightInsetFraction: CGFloat = 0.04

    /// The dog's frame in overlay coordinates (bottom-origin, y up): feet on
    /// the bottom edge, right side 4 % in from the right edge, the GIF's own
    /// aspect (the three are cropped flush around the dog, so they differ).
    static func frame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        let h = bounds.height * heightFraction
        let w = imageSize.height > 0 ? h * imageSize.width / imageSize.height : h
        return CGRect(x: bounds.maxX - bounds.width * rightInsetFraction - w,
                      y: bounds.minY, width: w, height: h)
    }
}
