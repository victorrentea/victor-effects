import Foundation

/// Body of `GET /sounds/captions`: for every asset on the grid (A and `under` B)
/// the real clip length and the cue list the Mac itself would show — built from
/// `SoundCaptions.live(for:clipSeconds:)`, so an exported subtitle track cannot
/// differ from what the room saw. A cue's `end` is when the caption is taken
/// down (`at + seconds`); `words`, on a timed line only, when each word starts,
/// in seconds into the clip, and `lastWordEnd` when a held last word is full. A silent asset has `"cues":[]`.
///
/// `GET /sounds/captions/base` is the same without the karaoke tuner's edits
/// (`CaptionEdits`): what the app ships with, which the tuner can go back to.
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
    static func build(assets: [String], track: (String, TimeInterval?) -> [CaptionLine] = SoundCaptions.schedule,
                      duration: (String) -> TimeInterval?) -> [String: Any] {
        var result: [String: Any] = [:]
        for asset in assets {
            let secs = duration(asset)
            let cues: [[String: Any]] = track(asset, secs).map { line in
                var cue: [String: Any] = ["start": round3(line.at), "end": round3(line.at + line.seconds), "text": line.text]
                if !line.words.isEmpty { cue["words"] = line.words.map { round3(line.at + $0) } }
                if let end = line.lastWordEnd { cue["lastWordEnd"] = round3(line.at + end) }
                return cue
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
    private static var cache: [Bool: (key: String, body: String)] = [:]

    static func cachedJSON(base: Bool = false) -> String {
        let key = SoundsManifest.cachedCombinedHash + "|" + TilesManifest.tilesHash + (base ? "" : "|" + CaptionEdits.stamp)
        if let hit = cache[base], hit.key == key, !key.hasPrefix("|") { return hit.body }
        guard let doc = TilesManifest.load()?.doc else { return "{}" }
        let body = json(build(assets: assets(in: doc), track: base ? SoundCaptions.schedule : SoundCaptions.live) {
            SoundManager.shared.soundDuration($0)
        })
        cache[base] = (key, body)
        return body
    }
}
