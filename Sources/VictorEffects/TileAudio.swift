import Foundation

/// 🔊 What a press of a tile is HEARD as — the one answer the ▲/＋ hints
/// (`RecommendedVolumes`), the ＋ renders (`DiskBoosts`) and the per-tile bar's
/// gain on the special paths (`SoundManager.tileGain(forFile:)`) all read, and
/// the constants `EffectsEngine.playSound` and the animator play from
/// (Victor, 2026-11-09: "the ▲ and the ＋ must reflect and change what is
/// actually heard when that tile is pressed").
///
/// Most tiles are heard as their own mp3. The exceptions:
/// - a tile that plays ANOTHER file (#31's iris rings a gong, #53's money a
///   "ching", #14 the minions' cut, #9 the long hymn, #34 the phoenix's cry);
/// - a tile that alternates between two takes (`AlternatingSounds`) — both
///   files, the ▲ follows the louder;
/// - a tile whose sound is made in code (none today: the sonar plays
///   `23_radar.mp3`) — `synthesized`, no file, no hint.
///
/// **No two tiles share a file** (Victor, 2026-11-09): #31 and #53 used to
/// borrow #50's gong and #57's ching, so a ＋ (boosted per FILE) on one was heard
/// on the other too. Each now has its own copy in the sounds folder —
/// `iris_gong.mp3` (= `50_gong.mp3`) and `money_ching.mp3` (= `57_checkmark.mp3`),
/// byte for byte the same audio — and borrows the other tile's file only on a
/// machine whose sounds folder lacks the copy (the public starter pack), where
/// the ＋ is then shared again rather than the tile going silent.
/// `TileAudioDriftTests` parses `EffectsEngine.playSound` and fails on a tile
/// that plays a literal file this table does not know about.
enum TileAudio {
    /// #31's and #53's own files, and the tiles' files they fall back to.
    static let irisOwnSound = "iris_gong.mp3"
    static let irisSharedSound = "50_gong.mp3"
    static let moneyOwnSound = "money_ching.mp3"
    static let moneySharedSound = "57_checkmark.mp3"
    static let universalSound = "universal-minions.mp3"  // #14

    private static let onDisk: (String) -> Bool = { SoundManager.shared.originalURL(for: $0) != nil }

    /// The file #31 plays: its own copy, else #50's gong.
    static func irisSound(exists: (String) -> Bool = onDisk) -> String {
        exists(irisOwnSound) ? irisOwnSound : irisSharedSound
    }
    /// The file #53 plays: its own copy, else #57's ching.
    static func moneySound(exists: (String) -> Bool = onDisk) -> String {
        exists(moneyOwnSound) ? moneyOwnSound : moneySharedSound
    }
    static var irisSound: String { irisSound() }
    static var moneySound: String { moneySound() }

    /// Tiles whose sound is generated in code: no file to measure or boost.
    static let synthesized: Set<String> = []

    /// The fixed remaps (the ones that pick a file at play time are below).
    static let remaps: [String: [String]] = [
        "14_universal.mp3": [universalSound],
    ]

    /// The file names a press of `tile` is heard as; [] for a synthesized one.
    /// `exists` answers whether an ORIGINAL is on this machine (the hymn and
    /// the phoenix pick the first that is, as their players do).
    static func files(forTile tile: String, exists: (String) -> Bool = { SoundManager.shared.originalURL(for: $0) != nil }) -> [String] {
        if synthesized.contains(tile) { return [] }
        if let cycle = AlternatingSounds.defaultTable[tile] { return cycle }
        if let r = remaps[tile] { return r }
        switch tile {
        case "31_tarzan.mp3":
            return [irisSound(exists: exists)]
        case "53_rain.mp3":
            return [moneySound(exists: exists)]
        case PrayController.tile:
            // `PrayController.startHymn`: the tablet take, else the long, else the short.
            return [PrayController.tabletHymn, PrayController.hymn, PrayController.shortHymn]
                .first(where: exists).map { [$0] } ?? [tile]
        case "34_phoenix.mp3":
            // `EmojiAnimator.showPhoenix`: the video's sound when the video is
            // there, else the legacy cry. The tile's own mp3 is a silent placeholder.
            return EffectsConfig.shared.assetURL(EmojiAnimator.phoenixVideoName) != nil
                ? [EmojiAnimator.phoenixVideoSound] : ["phoenix.mp3"]
        default:
            return [tile]
        }
    }

    /// The tile a file is heard for, when no press says so (a sound started
    /// after the press, from a timer): the tile that IS that file, else the
    /// first tile whose press plays it.
    static func owningTile(ofFile file: String, tiles: [String]) -> String? {
        if tiles.contains(file) { return file }
        return tiles.first { files(forTile: $0, exists: { _ in true }).contains(file) }
    }
}
