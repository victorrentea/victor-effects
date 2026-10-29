import Foundation

/// ♾️ The tiles whose desktop effect has no length of its own: the pointer
/// becomes the effect and stays it until Escape (or a re-press, or the 🛑), and
/// only a backstop far past any real use ends it otherwise. The `durationMs` a
/// `/sound/play` answers for them is a guess at how long the tile should look
/// lit, so a countdown drawn from it lies — the tablet read "3… 2… 1…" over a
/// flame still burning (Victor, 2026-10-30).
///
/// For these `/sound/play` also says `"open":true`, and the tablet draws a ring
/// that spins instead of one that drains, and asks `GET /sound/running/<asset>`
/// once a second until the answer is no.
enum OpenEndedTiles {
    /// Tile asset → the question that says whether its effect is still up.
    /// Keyed by the TILE's asset, the one the client asked `/sound/play` for.
    ///
    /// Two more than the Escape ones, for the same lie: #41 love hands waits up
    /// to 30 s for the click that starts its clip, and #3's bombardment lasts as
    /// long as bombs keep being planted. Every other tile ends with its clip, or
    /// with a fixed length `playSound` already reports (phoenix, the FBI knock).
    static let assets: [String: (EmojiAnimator) -> Bool] = [
        "11_fire.mp3":        { $0.isFireRunning },
        "18_chainsaw.mp3":    { $0.isChainsawRunning },
        "22_minigun.mp3":     { $0.activeEffectNames.contains("bullet-holes") },
        "41_love_hearts.mp3": { $0.activeEffectNames.contains("love-hands") },
        "03_explosion.mp3":   { $0.isBombRunning },
    ]

    static func isOpenEnded(_ asset: String) -> Bool { assets[asset] != nil }

    /// `nil` for a tile that is not open-ended: the route answers 404 rather
    /// than a `false` that would read as "it just ended".
    static func isRunning(_ asset: String, animator: EmojiAnimator) -> Bool? {
        assets[asset].map { $0(animator) }
    }
}
