import Foundation

/// Body of `GET /sounds/captions`: for every asset on the grid (A and `under` B)
/// the real clip length and the cue list the Mac itself would show — built from
/// `SoundCaptions.schedule(for:clipSeconds:)`, so an exported subtitle track
/// cannot differ from what the room saw. A cue's `end` is when the caption is
/// taken down (`at + seconds`). A silent asset has `"cues":[]`.
enum CaptionsExport {
    static func assets(in doc: TilesDocument) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for t in doc.tiles {
            for a in [t.asset, t.under?.asset].compactMap({ $0 }) where !a.isEmpty && seen.insert(a).inserted {
                out.append(a)
            }
        }
        return out
    }

    /// Pure: `duration` is injected so tests need no audio files.
    static func build(assets: [String], duration: (String) -> TimeInterval?) -> [String: Any] {
        var result: [String: Any] = [:]
        for asset in assets {
            let secs = duration(asset)
            let cues: [[String: Any]] = SoundCaptions.schedule(for: asset, clipSeconds: secs).map {
                ["start": round3($0.at), "end": round3($0.at + $0.seconds), "text": $0.text]
            }
            result[asset] = ["durationSeconds": round3(secs ?? 0), "cues": cues] as [String: Any]
        }
        return result
    }

    static func json(_ obj: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    private static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

    // Durations mean opening ~90 audio files; recompute only when the audio or
    // the grid changed.
    private static var cache: (key: String, body: String)?

    static func cachedJSON() -> String {
        let key = SoundsManifest.cachedCombinedHash + "|" + TilesManifest.tilesHash
        if let cache, cache.key == key, !key.hasPrefix("|") { return cache.body }
        guard let doc = TilesManifest.load()?.doc else { return "{}" }
        let body = json(build(assets: assets(in: doc)) { SoundManager.shared.soundDuration($0) })
        cache = (key, body)
        return body
    }
}
