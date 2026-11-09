import CryptoKit
import Foundation

/// 🔺 The ▲ on the tablet's per-tile volume bar, and the "＋N dB" on the ＋
/// beside it: how far THIS clip is from the average clip on the board, said
/// as the one control that can fix it. Only a hint — nothing here ever moves
/// a gain or presses a ＋ (Victor, 2026-11-09).
///
/// For every clip — each soundboard tile, each video snippet of page 2 — the
/// loudest stretch of the file (`Loudness.maxShortTerm`: 3 s, or the whole
/// clip when it is shorter; LUFS), plus the mastering trim the code always
/// applies (`SoundManager.fileGain`); the tile's own bar (`SoundGains`) is left
/// out. A video is measured only over the window that is played: from its
/// `startSeconds`, for the player's 60 s auto-kill. A clip with no audio (two
/// snippets are silent by design) has no hint and is not in the mean.
///
/// - The reference `R` is the plain mean of the maxima of the ORIGINAL files
///   (disk boost 0), sounds and videos alike — a ＋ press cannot drag the
///   target along with the clip.
/// - The clip is judged as it plays NOW: its ＋ render (`DiskBoosts`) when it
///   has one, measured like any other file.
/// - **Louder than `R`** → `recommended`: the bar position (0…80, 80 = "100%")
///   that brings its maximum down to `R`. The bar's gain is (p/80)² in
///   amplitude, so `p = 80 × 10^((R − M) / 40)`: one 4 dB louder sits at ~64
///   ("79%"). Only positions below 80 are served — the ▲ is a turn-it-down hint.
/// - **Quieter than `R`** → `recommendedBoostDb`: the ＋ presses (1.5 dB each)
///   that would lift it to `R`, rounded to whole presses (at most the ＋'s
///   +12 dB); none when that rounds to zero.
///
/// Recomputed when the inputs move — `soundsHash`, `tilesHash`, the
/// `videos.json` in `videosDir`, or a ＋ render landing — off the main thread,
/// with a per-file cache in `~/.victor-effects/loudness-cache.json` so only a
/// new or replaced file is decoded again. It rides `GET /sound/gains` and moves
/// `gainsHash`, so the tablet picks a new clip's hint up on its next ping.
enum RecommendedVolumes {
    /// Bumped when the measurement changes meaning: every cached value is dropped.
    static let algorithmVersion = 2
    /// How long a video snippet is up at most: addons' `VideoPlayer.autoKillAfter`.
    static let videoWindow: Double = 60

    // MARK: - The formula (pinned by RecommendedVolumesTests)

    static func reference(_ maxima: [Double]) -> Double? {
        maxima.isEmpty ? nil : maxima.reduce(0, +) / Double(maxima.count)
    }

    /// The bar position that moves a clip at `m` to `r` (unclamped, ≥ 0).
    static func position(max m: Double, reference r: Double) -> Int {
        let p = Double(SoundGains.defaultPct) * pow(10, (r - m) / 40)
        return max(0, Int(p.rounded()))
    }

    /// Whole ＋ presses that lift a clip at `m` to `r`, in dB; 0 when none.
    static func boostDb(max m: Double, reference r: Double) -> Double {
        guard r > m else { return 0 }
        // Never more than the ＋ can give: past that, the advice is "all of it".
        return min(DiskBoosts.maxDb, (((r - m) / DiskBoosts.stepDb).rounded()) * DiskBoosts.stepDb)
    }

    /// The trim `SoundManager` always applies to `file`, in dB.
    static func fileTrimDb(_ file: String) -> Double {
        guard let g = SoundManager.fileGain[file], g > 0 else { return 0 }
        return 20 * log10(Double(g))
    }

    // MARK: - What a clip is

    struct Clip: Equatable {
        /// The `SoundGains` key: the tile's asset, or `video:<id>`.
        let key: String
        /// The file(s) it may play — a tile alternating between two takes has two.
        let files: [URL]
        var start: Double = 0
        var end: Double? = nil
        /// A render → the original's name, for its `fileGain`.
        var trimNames: [URL: String] = [:]
    }

    /// A clip as it plays now: each original swapped for its ＋ render, if any
    /// (`renders`: original file name → render). A render is the window already.
    /// Nil when none of its files has one.
    static func current(_ clip: Clip, renders: [String: URL]) -> Clip? {
        guard clip.files.contains(where: { renders[$0.lastPathComponent] != nil }) else { return nil }
        let files = clip.files.map { renders[$0.lastPathComponent] ?? $0 }
        var trims: [URL: String] = [:]
        for f in clip.files { if let r = renders[f.lastPathComponent] { trims[r] = f.lastPathComponent } }
        let windowed = clip.end != nil && files.allSatisfy { renders.values.contains($0) }
        return windowed ? Clip(key: clip.key, files: files, trimNames: trims)
            : Clip(key: clip.key, files: files, start: clip.start, end: clip.end, trimNames: trims)
    }

    /// The files a tile's press is heard as — `TileAudio`, the one table the
    /// players read too. A tile with no file (sound made in code) has no clip.
    static func soundClips(tiles: [Tile], resolve: (String) -> URL? = { SoundManager.shared.originalURL(for: $0) }) -> [Clip] {
        var seen = Set<String>()
        var out: [Clip] = []
        for tile in tiles.flatMap({ [$0] + ($0.under.map { [$0] } ?? []) }) where seen.insert(tile.asset).inserted {
            let names = TileAudio.files(forTile: tile.asset, exists: { resolve($0) != nil })
            guard !names.isEmpty else { continue }
            let files = names.map { resolve($0) ?? URL(fileURLWithPath: "/missing").appendingPathComponent($0) }
            out.append(Clip(key: tile.asset, files: files))
        }
        return out
    }

    struct VideoEntry: Decodable { let id: String; let file: String; let startSeconds: Int? }

    static func videoClips(manifest data: Data, videosDir: URL) -> [Clip] {
        struct Doc: Decodable { let videos: [VideoEntry] }
        guard let doc = try? JSONDecoder().decode(Doc.self, from: data) else { return [] }
        return doc.videos.map { v in
            let start = Double(max(0, v.startSeconds ?? 0))
            return Clip(key: SoundGains.videoKey(v.id), files: [videosDir.appendingPathComponent(v.file)],
                        start: start, end: start + videoWindow)
        }
    }

    // MARK: - Measuring

    enum Result: Equatable {
        case loudness(Double)
        /// No audio track, or digital silence: no ▲, and not in the mean.
        case silent
        case failed(String)
    }

    /// Each clip's maximum (trim included). Files already in `cacheFile` with the
    /// same size, mtime and window are not decoded again.
    static func measure(_ clips: [Clip], cacheFile: URL?) -> [String: Result] {
        var cache = LoudnessCache(file: cacheFile)
        let out = measure(clips, cache: &cache)
        cache.save()
        return out
    }

    static func measure(_ clips: [Clip], cache: inout LoudnessCache) -> [String: Result] {
        var out: [String: Result] = [:]
        for clip in clips {
            var best: Double?
            var failure: String?
            for url in clip.files {
                switch cache.value(for: url, start: clip.start, end: clip.end) {
                case .failure(let e): failure = "\(url.lastPathComponent): \(e)"
                case .success(let v):
                    // The trim belongs to the ORIGINAL's name (`trimNames`), which a render lacks.
                    let original = clip.trimNames[url] ?? url.lastPathComponent
                    if let v { best = max(best ?? -.infinity, v + fileTrimDb(original)) }
                }
            }
            if let failure { out[clip.key] = .failed(failure) }
            else if let best { out[clip.key] = .loudness(best) }
            else { out[clip.key] = .silent }
        }
        return out
    }

    struct Table: Equatable {
        /// Each clip's maximum, original file (disk boost 0).
        var maxima: [String: Double] = [:]
        /// …and as it plays now, for the clips with a ＋ render.
        var current: [String: Double] = [:]
        var reference: Double?
        /// ▲: louder than R → the bar position (< 80) that brings it to R.
        var positions: [String: Int] = [:]
        /// ＋N dB: quieter than R → whole presses that lift it to R.
        var boosts: [String: Double] = [:]
    }

    static func table(_ results: [String: Result], current now: [String: Result] = [:]) -> Table {
        var t = Table()
        for (k, r) in results { if case .loudness(let m) = r { t.maxima[k] = m } }
        for (k, r) in now { if case .loudness(let m) = r, t.maxima[k] != nil { t.current[k] = m } }
        t.reference = reference(t.maxima.keys.sorted().map { t.maxima[$0]! })
        guard let r = t.reference else { return t }
        for (k, raw) in t.maxima {
            let m = t.current[k] ?? raw
            if m > r {
                let p = position(max: m, reference: r)
                if p < SoundGains.defaultPct { t.positions[k] = p }
            } else {
                let b = boostDb(max: m, reference: r)
                if b > 0 { t.boosts[k] = b }
            }
        }
        return t
    }

    // MARK: - The live table (main thread)

    private static var live = Table()
    private static var currentKey: String?
    private static var computing = false
    private static var cachedHash = ""

    static var cacheFile: URL {
        URL(fileURLWithPath: EffectsConfig.configDir).appendingPathComponent("loudness-cache.json")
    }

    static var videosManifestURL: URL? {
        EffectsConfig.shared.videosDir?.appendingPathComponent("videos.json")
    }

    /// One `stat`, no read: cheap enough for every `/ping`.
    private static func stamp(_ url: URL?) -> String {
        guard let url, let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "-" }
        let size = (a[.size] as? Int) ?? 0
        let mtime = ((a[.modificationDate] as? Date)?.timeIntervalSince1970) ?? 0
        return "\(size)-\(Int(mtime))"
    }

    /// Called on every `/ping` and at launch: starts a background pass when the
    /// sounds, the tiles or the video list moved since the table on hand.
    static func refreshIfStale() {
        let soundsHash = SoundsManifest.cachedCombinedHash
        guard !soundsHash.isEmpty, !computing else { return }
        let renders = DiskBoosts.shared.allRenders
        let key = "\(algorithmVersion)|\(soundsHash)|\(TilesManifest.tilesHash)|\(stamp(videosManifestURL))|"
            + renders.values.map(\.lastPathComponent).sorted().joined(separator: ",")
        guard key != currentKey else { return }
        guard let tiles = TilesManifest.load()?.doc.tiles else { return }
        let videosDir = EffectsConfig.shared.videosDir
        let cache = cacheFile
        computing = true
        DispatchQueue.global(qos: .utility).async {
            let started = Date()
            var clips = soundClips(tiles: tiles)
            if let videosDir, let data = FileManager.default.contents(atPath: videosDir.appendingPathComponent("videos.json").path) {
                clips += videoClips(manifest: data, videosDir: videosDir)
            }
            var c = LoudnessCache(file: cache)
            let results = measure(clips, cache: &c)
            let now = measure(clips.compactMap { current($0, renders: renders) }, cache: &c)
            c.save()
            let t = table(results, current: now)
            DispatchQueue.main.async {
                computing = false
                currentKey = key
                live = t
                cachedHash = hashOf(t)
                for (k, r) in results { if case .failed(let why) = r { effectsError("🔺 no loudness for \(k): \(why)") } }
                let silent = results.filter { $0.value == .silent }.keys.sorted()
                effectsInfo("🔺 hints: ▲ on \(t.positions.count), ＋ on \(t.boosts.count) of \(t.maxima.count) clips, R = "
                    + (t.reference.map { String(format: "%.2f LUFS", $0) } ?? "-")
                    + (silent.isEmpty ? "" : ", silent: \(silent.joined(separator: " "))")
                    + (videosDir == nil ? ", no videosDir — sounds only" : "")
                    + String(format: " (%.1f s)", Date().timeIntervalSince(started)))
            }
        }
    }

    /// `/config/reload`: the next ping measures again (cached files are not re-decoded).
    static func invalidate() { currentKey = nil }

    /// Over the hints served; "" while there is no table yet.
    static var hash: String { cachedHash }

    private static func hashOf(_ t: Table) -> String {
        guard t.reference != nil else { return "" }
        return sha256(t.positions.keys.sorted().map { "\($0):\(t.positions[$0]!)" }.joined(separator: "\n")
            + "|" + t.boosts.keys.sorted().map { "\($0):\(t.boosts[$0]!)" }.joined(separator: "\n"))
    }

    /// The extra fields of `GET /sound/gains`, each with a leading comma.
    static var jsonFields: String {
        let t = live
        func map<V>(_ m: [String: V], _ f: (V) -> String) -> String {
            m.keys.sorted().map { "\(jsonString($0)):\(f(m[$0]!))" }.joined(separator: ",")
        }
        let ref = t.reference.map { String(format: "%.2f", $0) } ?? "null"
        return ",\"recommended\":{\(map(t.positions) { "\($0)" })}"
            + ",\"recommendedBoostDb\":{\(map(t.boosts) { "\($0)" })}"
            + ",\"loudness\":{\"referenceLufs\":\(ref)"
            + ",\"maxShortTermLufs\":{\(map(t.maxima) { String(format: "%.2f", $0) })}"
            + ",\"currentLufs\":{\(map(t.current) { String(format: "%.2f", $0) })}}"
    }

    static func useForTesting(_ t: Table) {
        live = t
        cachedHash = hashOf(t)
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        return String((String(data: data, encoding: .utf8) ?? "[\"\"]").dropFirst().dropLast())
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Per-file loudness cache: `<path>|<size>|<mtime>|<start>|<end>` → LUFS (or
/// null for silent). Entries not asked for in a pass are dropped on save.
struct LoudnessCache {
    let file: URL?
    private var stored: [String: Any] = [:]
    private var used: [String: Any] = [:]

    init(file: URL?) {
        self.file = file
        if let file, let data = FileManager.default.contents(atPath: file.path),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           (obj["version"] as? Int) == RecommendedVolumes.algorithmVersion,
           let items = obj["items"] as? [String: Any] {
            stored = items
        }
    }

    mutating func value(for url: URL, start: Double, end: Double?) -> Swift.Result<Double?, Error> {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return .failure(Loudness.Failure.unreadable("no such file"))
        }
        let size = (a[.size] as? Int) ?? 0
        let mtime = Int(((a[.modificationDate] as? Date)?.timeIntervalSince1970) ?? 0)
        let key = "\(url.path)|\(size)|\(mtime)|\(start)|\(end.map { "\($0)" } ?? "-")"
        if let hit = stored[key] {
            used[key] = hit
            return .success((hit as? NSNumber)?.doubleValue)
        }
        do {
            let v = try Loudness.maxShortTerm(of: url, start: start, end: end)
            used[key] = v.map { NSNumber(value: $0) } ?? NSNull()
            return .success(v)
        } catch {
            return .failure(error)
        }
    }

    func save() {
        guard let file else { return }
        let obj: [String: Any] = ["version": RecommendedVolumes.algorithmVersion, "items": used]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
