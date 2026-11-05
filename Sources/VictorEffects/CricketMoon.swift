import AVFoundation
import CoreGraphics

/// 🦗 Tile 12 (`12_cricket.mp3`): the silence after a joke that died gets a witness.
/// An animated cricket under a crescent moon and stars stands in the bottom-left
/// corner for the length of the clip, blinking at the room (2026-11-04, Victor's
/// Gemini clip, *"only the cricket and the moon plus stars, on a transparent
/// background, in the bottom-left corner"*).
///
/// The picture is `assetsDir/cricket-moon.mov`, HEVC with alpha played by an
/// `AVPlayerLayer` the way the phoenix is: 227 frames as images would be most of a
/// gigabyte, the video streams at under 2 MB. `tools/make-cricket-moon.py` builds
/// it. It has no audio track: the clip plays down the ordinary routed path, this
/// is the press-path visual only. Everything here is the arithmetic of that one
/// run, so it can be tested without a screen.
///
/// Behind them, when `assetsDir/cricket-brush.png` is there, a black brush stroke
/// (2026-11-05, Victor picked the picture and marked where the moon and the cricket
/// go; fully opaque, transparent around it): the film's own night, on any desktop.
/// `tools/make-cricket-brush.py` builds it and prints `videoInBackdrop`. Without it
/// he stands on the bare desktop, as he always did.
enum CricketMoon {
    static let sound = "12_cricket.mp3"
    static let videoName = "cricket-moon.mov"
    /// Key in `activeEffects`, and the name `fireEffect` answers to.
    static let effectName = "cricket-moon"
    static let backdropName = "cricket-brush.png"
    /// The video's height on the screen. The crop ends under the feet, so the
    /// cricket stands on the bottom edge and the moon stays clear of the middle.
    static let heightShare: CGFloat = 0.45
    /// …unless the display is so narrow that it would stop being a corner.
    static let widthCap: CGFloat = 0.6
    static let fadeIn: Double = 0.25
    /// The clip's chirps end on its last few hundred milliseconds, and so does he.
    static let fadeOut: Double = 0.35

    /// Flush in the bottom-left corner of `bounds` (AppKit y-up), aspect kept.
    static func frame(in bounds: CGRect, video: CGSize) -> CGRect {
        guard video.width > 0, video.height > 0 else { return .zero }
        let scale = min(bounds.height * heightShare / video.height,
                        bounds.width * widthCap / video.width)
        return CGRect(x: bounds.minX, y: bounds.minY,
                      width: video.width * scale, height: video.height * scale)
    }

    /// Where the film stands on the stroke, as shares of it, y up: nearest the spots
    /// Victor marked for the moon and the cricket, with every lit pixel on solid
    /// paint. Printed by `tools/make-cricket-brush.py`.
    static let videoInBackdrop = CGRect(x: 366.0 / 1929, y: 239.0 / 1080,
                                        width: 964.0 / 1929, height: 704.0 / 1080)
    static let backdropAspect: CGFloat = 1929.0 / 1080
    /// With the stroke, the stroke is what is sized, and he stands inside it.
    static let backdropHeightShare: CGFloat = 0.55
    static let backdropWidthCap: CGFloat = 0.7

    /// The stroke in the corner and the film on it.
    static func onBackdrop(in bounds: CGRect) -> (backdrop: CGRect, video: CGRect) {
        let height = min(bounds.height * backdropHeightShare,
                         bounds.width * backdropWidthCap / backdropAspect)
        let size = CGSize(width: height * backdropAspect, height: height)
        let origin = CGPoint(x: bounds.minX, y: bounds.minY)
        let fit = videoInBackdrop
        return (CGRect(origin: origin, size: size),
                CGRect(x: origin.x + fit.minX * size.width, y: origin.y + fit.minY * size.height,
                       width: fit.width * size.width, height: fit.height * size.height))
    }

    /// How long the run stays up: the clip, since that is what the room hears; the
    /// video's own length only when the clip cannot be read. Either way a number
    /// the effect ends itself on, never a wait for `/sound/stopped`.
    static func life(clip: Double?, video: Double) -> Double {
        if let clip, clip > 0 { return clip }
        return video
    }

    /// `keyTimes` for the opacity's `[0, 1, 1, 0]`, kept in order however short the run.
    static func fadeKeyTimes(life: Double) -> [Double] {
        guard life > 0 else { return [0, 0, 1, 1] }
        let rise = min(fadeIn / life, 0.5)
        return [0, rise, max(rise, 1 - fadeOut / life), 1]
    }

    /// The clip's real length, read off the file in `soundsDir`.
    static func clipLength() -> Double? {
        guard let url = SoundManager.shared.soundURL(for: sound) else { return nil }
        let d = AVURLAsset(url: url).duration
        return d.isNumeric ? CMTimeGetSeconds(d) : nil
    }
}
