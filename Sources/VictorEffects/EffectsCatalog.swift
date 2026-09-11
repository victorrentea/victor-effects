import CryptoKit
import Foundation

/// **The** answer to "does pressing this tile also do something on the desktop,
/// and what?" — one function, so no client ever has to assemble it from two
/// half-lists.
///
/// There are two places a sound can acquire a visual, and they cannot be merged
/// away:
///
///  - `SoundEffectMap.onPress` — the press path. The tablet reports the press,
///    the Mac fires the effect. Most tiles.
///  - `SoundEffectMap.playPathVisuals` — the effects whose cue sits at a fixed
///    offset INSIDE the clip (the microwave's BING at 2.695 s, the FBI's first
///    bang at 22 ms). They are started from `EffectsEngine.playSound`, which
///    owns the audio, and are deliberately absent from `onPress` because a
///    second trigger would double-fire them.
///
/// Plus the siren, whose visual is a *toggled* overlay (`/alarm/start|stop`)
/// rather than a self-terminating effect, and so lives in neither table.
///
/// Before this type existed the tablet drew its ⭐ from a union it assembled
/// itself out of `GET /sound/effects`; now it reads the `effect` field the Mac
/// stamps onto every tile in `GET /tiles`, and the union exists in exactly one
/// place — here. `EffectsCatalogTests` pins the resulting set by name, so an
/// edit to EITHER table has to touch the test and say what it meant.
enum EffectsCatalog {

    /// The siren's visual is the alarm overlay, not a `fireEffect` case: it is
    /// the one tile the tablet starts and stops through `/alarm/*`. Named here
    /// so `/tiles` can still say *what* the star promises.
    static let sirenEffectName = "alarm"

    /// The effect a tile's asset drives on the desktop, or nil if pressing it
    /// only makes a noise.
    static func effectName(forAsset asset: String) -> String? {
        if let pressed = SoundEffectMap.onPress[asset] { return pressed }
        if let inClip = SoundEffectMap.playPathVisuals[asset] { return inClip }
        if asset == SoundboardPress.sirenAsset { return sirenEffectName }
        return nil
    }

    /// Every asset with a visual, sorted — a stable body for `/effects/assets`
    /// and a stable input for [effectsHash].
    static var assets: [String] {
        var all = Set(SoundEffectMap.onPress.keys)
        all.formUnion(SoundEffectMap.playPathVisuals.keys)
        all.insert(SoundboardPress.sirenAsset)
        return all.sorted()
    }

    /// SHA-256 over the sorted asset list, newline-joined.
    ///
    /// Reported in `/ping` (and `/tiles`) so the tablet can tell in one 5-second
    /// ping whether the star set it is painting is still the Mac's, without
    /// re-pulling the whole tile manifest on a timer. Deliberately hashes the
    /// ASSETS and not the effect names: renaming "blood-drip" to "blood" changes
    /// nothing the tablet draws, and a hash that churns on it would cost a
    /// refetch for no visible difference.
    static var effectsHash: String {
        let joined = assets.joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Body of `GET /effects/assets` (and of the older `GET /sound/effects`).
    static var assetsJSON: String {
        let list = assets.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"assets\":[\(list)]}"
    }
}
