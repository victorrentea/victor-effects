import Foundation

/// 🔊 What a press of a tile is HEARD as — the one answer the ▲/＋ hints
/// (`RecommendedVolumes`), the ＋ renders (`DiskBoosts`) and the per-tile bar's
/// gain on the special paths (`SoundManager.tileGain(forFile:)`) all read, and
/// the constants `EffectsEngine.playSound` and the animator play from
/// (Victor, 2026-11-09: "the ▲ and the ＋ must reflect and change what is
/// actually heard when that tile is pressed").
///
/// Most tiles are heard as their own mp3. The exceptions:
/// - a tile that plays ANOTHER file (#31's iris rings the gong, #53's money
///   the "ching", #14 the minions' cut, #9 the long hymn, #34 the phoenix's cry);
/// - a tile that alternates between two takes (`AlternatingSounds`) — both
///   files, the ▲ follows the louder;
/// - a tile whose sound is made in code (none today: the sonar plays
///   `23_radar.mp3`) — `synthesized`, no file, no hint.
///
/// A file shared by two tiles (the gong: #31 and #50; the "ching": #53 and #57)
/// is boosted per FILE, so a ＋ on either is heard on both.
/// `TileAudioDriftTests` parses `EffectsEngine.playSound` and fails on a tile
/// that plays a literal file this table does not know about.
enum TileAudio {
    static let irisSound = "50_gong.mp3"            // #31
    static let moneySound = "57_checkmark.mp3"      // #53
    static let universalSound = "universal-minions.mp3"  // #14

    /// Tiles whose sound is generated in code: no file to measure or boost.
    static let synthesized: Set<String> = []

    /// The fixed remaps (the two that pick a file at play time are below).
    static let remaps: [String: [String]] = [
        "31_tarzan.mp3": [irisSound],
        "53_rain.mp3": [moneySound],
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
