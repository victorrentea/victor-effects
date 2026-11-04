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
enum CricketMoon {
    static let sound = "12_cricket.mp3"
    static let videoName = "cricket-moon.mov"
    /// Key in `activeEffects`, and the name `fireEffect` answers to.
    static let effectName = "cricket-moon"
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
