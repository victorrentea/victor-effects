import CryptoKit
import Foundation

/// 🔉 Each tile's own volume, set from the tablet's per-sound bar while (or after)
/// that tile plays. Some clips are mastered louder than they sound in the room;
/// this trims one tile without touching the master wedge.
///
/// **Down only, since 2026-11-09.** Stored as a slider position 0…80, **80 by
/// default** = the clip exactly as stored (×1.0), shown on the tablet as "100%"
/// (display % = position / 80). The position becomes a gain on the same
/// perceptual x² curve as the wedge, (p/80)²: 40 → ×0.25 ("50%"), 0 → silent.
/// Nothing plays above ×1 at runtime any more — the pre-amplified copies
/// (`BoostedClips`, 2026-10-30) that let the bar go to 100 (×1.56) are gone. A
/// clip that is too quiet is made louder ON DISK instead, once, by the ＋ next to
/// the bar (`DiskBoosts`). The scale kept its numbers rather than being rescaled
/// to 0…100, so every row stored before keeps its exact gain; only a row above 80
/// is clamped to 80 when the table is loaded (the log names it).
///
/// Keyed by the **tile's** asset (what `/sound/play` was asked for), not the file
/// that ends up playing — #31 plays the gong and #19 alternates onto #20's take,
/// and the bar the tablet shows is the tile's.
///
/// Lives on the Mac, beside `UsageCounts`, because the Mac plays the routed sound
/// and its thumbnail panel presses the same tiles: one table, both surfaces. The
/// tablet adopts it when `gainsHash` in `/ping` moves, for its local playback.
enum SoundGains {
    /// A video snippet's row (page 2 of the tablet, the panel's 🎬 page). The
    /// clip plays in addons, which gets the level as `?gain=` and follows a live
    /// move as `/sound/gain/video:<id>/<pct>` passes through its proxy.
    static func videoKey(_ id: String) -> String { "video:\(id)" }

    static let defaultPct = 80

    private static var positions: [String: Int] = load()
    private static var cachedHash: String?

    /// A `var` so the tests can point it at a scratch file — the default path is
    /// the real tablet's settings.
    static var storageURL: URL = defaultURL

    static var defaultURL: URL {
        URL(fileURLWithPath: EffectsConfig.expand(EffectsConfig.shared.values.usageFile))
            .deletingLastPathComponent().appendingPathComponent("sound-gains.json")
    }

    // MARK: - Reading

    static func position(of asset: String) -> Int { positions[asset] ?? defaultPct }

    /// Amplitude multiplier for `asset`'s tile: 1.0 at the default position.
    static func gain(for asset: String) -> Float { gain(position: position(of: asset)) }

    static func gain(position: Int) -> Float {
        let p = Float(max(0, min(defaultPct, position))) / Float(defaultPct)
        return p * p
    }

    /// SHA-256 over the sorted `asset:pct` lines, reported in `/ping`.
    static var hash: String {
        if let cachedHash { return cachedHash }
        let joined = positions.keys.sorted().map { "\($0):\(positions[$0]!)" }.joined(separator: "\n")
        let h = SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
        cachedHash = h
        return h
    }

    /// Body of `GET /sound/gains`: only the tiles moved off the default, plus the
    /// default itself and the hash this table was computed from.
    static var json: String { body(hash: hash, extra: "") }

    private static func body(hash: String, extra: String) -> String {
        let body = positions.keys.sorted()
            .map { "\"\($0)\":\(positions[$0]!)" }
            .joined(separator: ",")
        return "{\"gains\":{\(body)},\"defaultPct\":\(defaultPct),\"hash\":\"\(hash)\"\(extra)}"
    }

    /// 🔺 The `gainsHash` `/ping` reports: this table, the ▲/＋ hints
    /// (`RecommendedVolumes`) and the ＋ disk boosts (`DiskBoosts`, busy state
    /// included), so the tablet re-pulls `/sound/gains` when any of them moves.
    static var publicHash: String {
        let rec = RecommendedVolumes.hash
        let boosts = DiskBoosts.shared.stateKey
        return rec.isEmpty && boosts.isEmpty ? hash : RecommendedVolumes.sha256(hash + "\n" + rec + "\n" + boosts)
    }

    /// Body of `GET /sound/gains`: the table, `publicHash`, the hints
    /// (`recommended`, `recommendedBoostDb`, `loudness`) and `boosts`. `json`
    /// (without them) is what is stored.
    static var responseJSON: String {
        body(hash: publicHash, extra: RecommendedVolumes.jsonFields + DiskBoosts.shared.jsonFields)
    }

    // MARK: - Writing

    /// Set `asset`'s tile to slider position `pct` (clamped 0…80 — down only). Back at the
    /// default the row is dropped, so the table only lists what was changed.
    static func set(_ asset: String, _ pct: Int) {
        guard !asset.isEmpty else { return }
        let clamped = max(0, min(defaultPct, pct))
        let next: Int? = clamped == defaultPct ? nil : clamped
        guard positions[asset] != next else { return }
        positions[asset] = next
        cachedHash = nil
        save()
    }

    // MARK: - Persistence

    private static func load() -> [String: Int] {
        guard let data = FileManager.default.contents(atPath: storageURL.path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stored = obj["gains"] as? [String: Int] else { return [:] }
        // Rows from the days the bar went past ×1 (above 80) come back at ×1.0:
        // the row is dropped, and the file rewritten so it says so too.
        let above = stored.filter { $0.value > defaultPct }
        guard !above.isEmpty else { return stored }
        effectsInfo("🔉 clamped to 100% (×1.0, nothing plays louder than its file now): "
            + above.keys.sorted().map { "\($0) was \(above[$0]!)" }.joined(separator: ", "))
        let kept = stored.filter { $0.value < defaultPct }
        let body = kept.keys.sorted().map { "\"\($0)\":\(kept[$0]!)" }.joined(separator: ",")
        try? Data("{\"gains\":{\(body)},\"defaultPct\":\(defaultPct)}".utf8).write(to: storageURL, options: .atomic)
        return kept
    }

    private static func save() {
        let file = storageURL
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(json.utf8).write(to: file, options: .atomic)
        } catch {
            effectsError("cannot write sound gains to \(file.path): \(error)")
        }
    }

    static func useForTesting(_ file: URL) {
        storageURL = file
        positions = load()
        cachedHash = nil
    }
}
