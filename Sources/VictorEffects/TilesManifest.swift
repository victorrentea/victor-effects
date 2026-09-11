import CryptoKit
import Foundation

/// One soundboard tile, as described by `soundsDir/tiles.json`.
///
/// The tablet used to be the only place this list existed, as a hardcoded
/// Kotlin array beside 91 drawables. Moving it into the folder the Mac already
/// shares with the tablet means adding a tile is one JSON entry plus one image
/// — no Kotlin edit, no Swift edit, and both ends necessarily agree.
struct Tile: Codable, Equatable {
    /// The number printed in the tile's corner. Also how `/test/…/press/<n>`
    /// addresses it.
    let n: Int
    /// Filename inside `soundsDir`, e.g. `01_baby.mp3`.
    let asset: String
    /// Image path relative to `soundsDir`, e.g. `tiles/sfx_01_baby.jpg`.
    let image: String
    /// Optional word drawn across the tile.
    let label: String?
    /// Pressing it again restarts instead of stopping.
    let restartable: Bool
    /// Third-party audio the tablet can hide in its "©" mode. Carried here only
    /// so the manifest stays the single description of a tile.
    let copyright: Bool

    enum CodingKeys: String, CodingKey { case n, asset, image, label, restartable, copyright }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? c.decode(Int.self, forKey: .n)) ?? 0
        asset = (try? c.decode(String.self, forKey: .asset)) ?? ""
        image = (try? c.decode(String.self, forKey: .image)) ?? ""
        label = try? c.decode(String.self, forKey: .label)
        restartable = (try? c.decode(Bool.self, forKey: .restartable)) ?? false
        copyright = (try? c.decode(Bool.self, forKey: .copyright)) ?? false
    }

    init(n: Int, asset: String, image: String, label: String? = nil,
         restartable: Bool = false, copyright: Bool = false) {
        self.n = n; self.asset = asset; self.image = image
        self.label = label; self.restartable = restartable; self.copyright = copyright
    }
}

struct TilesDocument: Codable, Equatable {
    let columns: Int
    let tiles: [Tile]

    init(columns: Int, tiles: [Tile]) {
        self.columns = columns
        self.tiles = tiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Lenient on purpose: a manifest written by hand (or by a tablet build
        // that predates a key) must not take the whole panel down.
        let cols = (try? c.decode(Int.self, forKey: .columns)) ?? 0
        columns = cols > 0 ? cols : 13
        tiles = (try? c.decode([Tile].self, forKey: .tiles)) ?? []
    }

    enum CodingKeys: String, CodingKey { case columns, tiles }
}

enum TilesManifest {
    private static var cached: (doc: TilesDocument, hash: String)?

    static var url: URL { EffectsConfig.shared.soundsDir.appendingPathComponent("tiles.json") }

    /// Parse bytes. Pure, so the tests can feed it a literal instead of
    /// depending on a file that lives in another repo.
    static func parse(_ data: Data) -> TilesDocument? {
        try? JSONDecoder().decode(TilesDocument.self, from: data)
    }

    static func load() -> (doc: TilesDocument, hash: String)? {
        if let cached { return cached }
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        guard let doc = parse(data) else {
            effectsError("tiles.json at \(url.path) is not valid JSON")
            return nil
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        cached = (doc, hash)
        return cached
    }

    static func invalidate() { cached = nil }

    /// Reported in `/ping` so a client can tell whether its tile list matches
    /// this Mac's, the same way `soundsHash` does for the audio.
    static var tilesHash: String { load()?.hash ?? "" }

    /// The raw bytes of the manifest, or nil when there is no manifest. Hashed
    /// into `tilesHash` and enriched into [effectsJSON]; no route serves it.
    static var json: String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Body of `GET /tiles`: the manifest as written, plus **`"effect"` on every
    /// tile whose asset also animates the desktop** and a top-level
    /// **`"effectsHash"`**.
    ///
    /// This is what makes the ⭐ badge unable to drift. The tablet used to hold
    /// its own idea of which tiles were effect tiles; now the only list is
    /// `EffectsCatalog`, and it arrives stamped onto the very rows the badge is
    /// drawn from — one fetch, one truth, nothing to keep in step.
    ///
    /// Enriched by re-serialising rather than by string-splicing, and through
    /// `JSONSerialization` rather than `TilesDocument`, so that **keys this app
    /// has never heard of survive**: the manifest is written by the tablet's
    /// repo, and a key added there must not be filtered out by a Mac build that
    /// predates it. `effect` itself is REPLACED, never merged: a stale copy left
    /// in the file by an older tool loses to the live catalogue.
    ///
    /// `tilesHash` is unchanged by any of this — it stays the hash of the file's
    /// own bytes, so "is my tile list the Mac's tile list" keeps its meaning
    /// while "is my star set the Mac's star set" gets its own answer.
    static var effectsJSON: String? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return enrich(data) ?? String(data: data, encoding: .utf8)
    }

    /// Pure half of [effectsJSON], so a test can feed it a literal manifest
    /// instead of a machine that happens to have the tablet assets mounted.
    /// Returns nil when the bytes are not a JSON object — the caller then serves
    /// them verbatim, because this repo's job is to pass the grid on, not to
    /// have opinions about a file it does not own.
    static func enrich(_ data: Data) -> String? {
        guard var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let tiles = obj["tiles"] as? [[String: Any]] {
            obj["tiles"] = tiles.map { tile -> [String: Any] in
                var tile = tile
                if let asset = tile["asset"] as? String,
                   let effect = EffectsCatalog.effectName(forAsset: asset) {
                    tile["effect"] = effect
                } else {
                    tile.removeValue(forKey: "effect")
                }
                return tile
            }
        }
        obj["effectsHash"] = EffectsCatalog.effectsHash
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    static func tile(number: Int) -> Tile? {
        load()?.doc.tiles.first { $0.n == number }
    }

    /// Bytes of one tile image, addressed by its manifest-relative path.
    ///
    /// The path is resolved under `soundsDir` and then checked to still be
    /// inside it: the images are named by a JSON file this app does not own, so
    /// `../../../.ssh/id_rsa` has to bounce off something.
    static func image(relativePath: String) -> (data: Data, contentType: String)? {
        let base = EffectsConfig.shared.soundsDir.standardizedFileURL
        let candidate = base.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") else { return nil }
        guard let data = FileManager.default.contents(atPath: candidate.path) else { return nil }
        let type: String
        switch candidate.pathExtension.lowercased() {
        case "png": type = "image/png"
        case "webp": type = "image/webp"
        case "gif": type = "image/gif"
        default: type = "image/jpeg"
        }
        return (data, type)
    }
}
