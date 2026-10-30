import CryptoKit
import Foundation

/// 🔉 Each tile's own volume, set from the tablet's per-sound bar while (or after)
/// that tile plays. Some clips are mastered louder than they sound in the room;
/// this trims — or lifts — one tile without touching the master wedge.
///
/// Stored as a **slider position** 0…100, **80 by default**: 80 is the level every
/// clip played at before this existed, so a tile nobody touched sounds exactly as
/// it always did, and the 20 above it is headroom to make a quiet clip louder.
/// The position becomes a gain on the same perceptual x² curve as the wedge,
/// pinned so that 80 → ×1.0 (100 → ×1.56, 40 → ×0.25, 0 → silent).
///
/// Keyed by the **tile's** asset (what `/sound/play` was asked for), not the file
/// that ends up playing — #31 plays the gong and #19 alternates onto #20's take,
/// and the bar the tablet shows is the tile's.
///
/// Lives on the Mac, beside `UsageCounts`, because the Mac plays the routed sound
/// and its thumbnail panel presses the same tiles: one table, both surfaces. The
/// tablet adopts it when `gainsHash` in `/ping` moves, for its local playback.
enum SoundGains {
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

    /// The tiles set above the default — the ones that play a boosted copy.
    static var boostedAssets: [String] { positions.filter { $0.value > defaultPct }.keys.sorted() }

    /// Amplitude multiplier for `asset`'s tile: 1.0 at the default position.
    static func gain(for asset: String) -> Float { gain(position: position(of: asset)) }

    static func gain(position: Int) -> Float {
        let p = Float(max(0, min(100, position))) / Float(defaultPct)
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
    static var json: String {
        let body = positions.keys.sorted()
            .map { "\"\($0)\":\(positions[$0]!)" }
            .joined(separator: ",")
        return "{\"gains\":{\(body)},\"defaultPct\":\(defaultPct),\"hash\":\"\(hash)\"}"
    }

    // MARK: - Writing

    /// Set `asset`'s tile to slider position `pct` (clamped 0…100). Back at the
    /// default the row is dropped, so the table only lists what was changed.
    static func set(_ asset: String, _ pct: Int) {
        guard !asset.isEmpty else { return }
        let clamped = max(0, min(100, pct))
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
        return stored
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
