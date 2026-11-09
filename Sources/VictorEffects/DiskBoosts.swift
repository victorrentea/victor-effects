import AVFoundation
import Foundation

/// ＋ A clip made louder ON DISK, 1.5 dB per press of the ＋ beside the tablet's
/// per-tile bar (Victor, 2026-11-09). The bar itself only turns a clip down
/// (`SoundGains`); this is how a quiet one comes up, without anything playing
/// above ×1 at runtime.
///
/// - **Always rendered from the ORIGINAL**, at the clip's total boost — never
///   from the previous render, so ten presses are one gain stage, not ten (and
///   no codec generation loss: the render is 16-bit WAV). The original is never
///   overwritten or deleted; reset (long-press ＋) simply plays it again.
/// - **Through a look-ahead peak limiter at −1 dBFS** (`ceiling`). How hard it
///   had to work is kept as `limitedDb` (the deepest gain reduction); above
///   `limitedHintDb` the tablet says "limitat" — more presses now buy less.
/// - **Per clip key**, like `SoundGains`: the tile's asset (every file that tile
///   may play is rendered — #31's gong, #19's two takes — plus the tile's own
///   file, which is the one the tablet downloads for its local plays), or
///   `video:<id>`: only the AUDIO of the played window (from `startSeconds`, the
///   player's 60 s), which addons lays over the untouched mp4 in an
///   `AVMutableComposition`. The mp4 is never touched — the YouTube-publish
///   guard fingerprints it.
/// - **Rendered on the press, off the main thread**; while it runs the key is
///   `busy` and every play uses the previous render (or the original). Renders
///   live in `~/.victor-effects/boosted/`, named after the original's size and
///   mtime, so a replaced original is rendered again (`resume()`, and lazily by
///   `playURL`). The table is `~/.victor-effects/disk-boosts.json`.
final class DiskBoosts {
    static let shared = DiskBoosts()

    static let stepDb = 1.5
    /// Eight presses. Past this the limiter is doing the work, not the gain.
    static let maxDb = 12.0
    /// −1 dBFS: where the limiter holds the render's peaks.
    static let ceiling: Float = 0.891
    /// "limitat" on the tablet when the limiter took more than this off a peak.
    static let limitedHintDb = 1.0
    /// How long a video snippet is up at most: addons' `VideoPlayer.autoKillAfter`.
    static let videoWindow: Double = RecommendedVolumes.videoWindow

    struct Source: Equatable {
        /// The original's file name (`fileGain` and the render map are keyed on it).
        let name: String
        let url: URL
        var start: Double = 0
        var end: Double? = nil
    }

    struct Ready: Equatable {
        var db: Double
        var limitedDb: Double
        /// Original file name → render file name (in `dir`).
        var renders: [String: String]
    }

    private(set) var target: [String: Double] = [:]
    private(set) var ready: [String: Ready] = [:]
    private var pending: [String: Int] = [:]
    private let queue = DispatchQueue(label: "disk-boosts", qos: .userInitiated)

    var storageURL: URL
    var dir: URL
    /// Where a key's sources come from — a seam for the tests.
    var sourcesProvider: (String) -> [Source] = DiskBoosts.liveSources

    init(storage: URL? = nil, dir: URL? = nil) {
        let base = URL(fileURLWithPath: EffectsConfig.configDir)
        storageURL = storage ?? base.appendingPathComponent("disk-boosts.json")
        self.dir = dir ?? base.appendingPathComponent("boosted", isDirectory: true)
        load()
    }

    // MARK: - Reading (main thread)

    func boostDb(_ key: String) -> Double { target[key] ?? 0 }
    func readyDb(_ key: String) -> Double { ready[key]?.db ?? 0 }
    func isBusy(_ key: String) -> Bool { (pending[key] ?? 0) > 0 }

    /// The file to play for `tile` when it plays `file`: its render when one is
    /// ready for the original as it is on disk now, else the original itself.
    func playURL(tile: String, file: URL) -> URL {
        guard let r = ready[tile], r.db > 0, let name = r.renders[file.lastPathComponent] else { return file }
        let render = dir.appendingPathComponent(name)
        let source = Source(name: file.lastPathComponent, url: file)
        guard name == Self.renderName(source, db: r.db), FileManager.default.fileExists(atPath: render.path) else {
            resume()   // the original was replaced since: render it again
            return file
        }
        return render
    }

    /// The render of `key`'s own file — what the tablet downloads for a tile.
    func tabletFile(_ key: String) -> URL? {
        guard !key.hasPrefix("video:"), let r = ready[key], r.db > 0, let name = r.renders[key] else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Every ready render of `key` by original name, for the loudness pass.
    func renders(_ key: String) -> [String: URL] {
        guard let r = ready[key], r.db > 0 else { return [:] }
        return r.renders.mapValues { dir.appendingPathComponent($0) }
    }

    // MARK: - Writing (main thread)

    /// One ＋ press. False for a key with nothing to render (unknown tile/video).
    @discardableResult
    func press(_ key: String) -> Bool {
        let sources = sourcesProvider(key)
        guard !sources.isEmpty else { return false }
        let db = min(Self.maxDb, boostDb(key) + Self.stepDb)
        guard db != boostDb(key) else { return true }
        target[key] = db
        save()
        render(key, db: db, sources: sources)
        return true
    }

    /// Long-press ＋: back to the original. The renders go; the original was never touched.
    func reset(_ key: String) {
        target[key] = nil
        if let old = ready.removeValue(forKey: key) { deleteRenders(old) }
        save()
    }

    /// Render whatever a stored boost is missing — at launch, or when an
    /// original turned out to have been replaced.
    func resume() {
        for (key, db) in target where db > 0 && !isBusy(key) {
            let sources = sourcesProvider(key)
            guard !sources.isEmpty else { continue }
            let names = Dictionary(uniqueKeysWithValues: sources.map { ($0.name, Self.renderName($0, db: db)) })
            let have = ready[key]
            let complete = have?.db == db && have?.renders == names
                && names.values.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
            if !complete { render(key, db: db, sources: sources) }
        }
    }

    /// Block until every queued render is done — the tests' and proof's handle.
    func waitForRenders() {
        queue.sync {}
        if Thread.isMainThread { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    private func render(_ key: String, db: Double, sources: [Source]) {
        pending[key, default: 0] += 1
        let dir = self.dir
        queue.async { [weak self] in
            let started = Date()
            var renders: [String: String] = [:]
            var limited = 0.0
            var failure: String?
            for s in sources {
                do {
                    let name = Self.renderName(s, db: db)
                    let out = dir.appendingPathComponent(name)
                    let l = try Self.renderBoost(s, db: db, to: out)
                    renders[s.name] = name
                    limited = max(limited, l)
                } catch {
                    failure = "\(s.name): \(error)"
                }
            }
            let finish = {
                guard let self else { return }
                self.pending[key, default: 1] -= 1
                if self.pending[key] == 0 { self.pending[key] = nil }
                let fresh = Ready(db: db, limitedDb: limited, renders: renders)
                if let failure {
                    effectsError("＋ render of \(key) at +\(db) dB failed: \(failure)")
                    self.deleteRenders(fresh, keeping: self.ready[key])
                } else if self.target[key] == db {
                    if let old = self.ready[key] { self.deleteRenders(old, keeping: fresh) }
                    self.ready[key] = fresh
                    self.save()
                    effectsInfo("＋ \(key) +\(db) dB ready in " + String(format: "%.2f s", Date().timeIntervalSince(started))
                        + String(format: ", limiter %.1f dB", limited))
                } else {
                    self.deleteRenders(fresh, keeping: self.ready[key])   // superseded by a later press or a reset
                }
            }
            if Thread.isMainThread { finish() } else { DispatchQueue.main.async(execute: finish) }
        }
    }

    private func deleteRenders(_ r: Ready, keeping: Ready? = nil) {
        let keep = Set(keeping?.renders.values.map { $0 } ?? [])
        for name in r.renders.values where !keep.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - The served state

    /// Moves `gainsHash` whenever a boost, its readiness or its busy state moves.
    var stateKey: String {
        Set(target.keys).union(ready.keys).union(pending.keys).sorted().map { k in
            "\(k):\(boostDb(k)):\(readyDb(k)):\(isBusy(k)):\(ready[k].map { String(format: "%.1f", $0.limitedDb) } ?? "-")"
        }.joined(separator: "\n")
    }

    /// `,"boosts":{…}` for `GET /sound/gains`.
    var jsonFields: String {
        let rows = Set(target.keys).union(ready.keys).union(pending.keys).sorted().map { k -> String in
            let rev = tabletFile(k).map { ",\"rev\":\"\($0.lastPathComponent)\"" } ?? ""
            return "\"\(k)\":{\"db\":\(boostDb(k)),\"readyDb\":\(readyDb(k)),\"busy\":\(isBusy(k)),"
                + "\"limitedDb\":" + String(format: "%.2f", ready[k]?.limitedDb ?? 0)
                + ",\"limited\":\((ready[k]?.limitedDb ?? 0) > Self.limitedHintDb)\(rev)}"
        }
        return ",\"boosts\":{\(rows.joined(separator: ","))}"
    }

    /// `GET /sound/boost/<key>` — what addons asks at a video's play.
    func infoJSON(_ key: String) -> String {
        var audio = "null"
        if key.hasPrefix("video:"), let r = ready[key], r.db > 0, let name = r.renders.values.first {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path), let s = sourcesProvider(key).first {
                audio = "{\"path\":\(Self.jsonString(url.path)),\"start\":\(s.start)}"
            }
        }
        return "{\"key\":\(Self.jsonString(key)),\"db\":\(boostDb(key)),\"readyDb\":\(readyDb(key)),"
            + "\"busy\":\(isBusy(key)),\"audio\":\(audio)}"
    }

    // MARK: - Sources

    static func liveSources(_ key: String) -> [Source] {
        if key.hasPrefix("video:") {
            let id = String(key.dropFirst("video:".count))
            guard let vdir = EffectsConfig.shared.videosDir,
                  let data = FileManager.default.contents(atPath: vdir.appendingPathComponent("videos.json").path),
                  let clip = RecommendedVolumes.videoClips(manifest: data, videosDir: vdir).first(where: { $0.key == key }),
                  let url = clip.files.first, FileManager.default.fileExists(atPath: url.path) else { return [] }
            _ = id
            return [Source(name: url.lastPathComponent, url: url, start: clip.start, end: clip.end)]
        }
        guard let soundsDir = SoundManager.sharedSoundsDir() else { return [] }
        var names = RecommendedVolumes.playedFiles(forTile: key)
        if !names.contains(key) { names.append(key) }
        return names.map { Source(name: $0, url: soundsDir.appendingPathComponent($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    /// `<stem>.<size>-<mtime>[.s<start>].+<db>dB.wav`: a replaced original or a
    /// different boost is a different name, so a stale render is never played.
    static func renderName(_ s: Source, db: Double) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: s.url.path)
        let size = (a?[.size] as? Int) ?? 0
        let mtime = Int(((a?[.modificationDate] as? Date)?.timeIntervalSince1970) ?? 0)
        let stem = (s.name as NSString).deletingPathExtension
        let window = s.start > 0 || s.end != nil ? ".s\(Int(s.start))-\(Int((s.end ?? 0) - s.start))" : ""
        return "\(stem).\(size)-\(mtime)\(window).+" + String(format: "%.1f", db) + "dB.wav"
    }

    // MARK: - The render

    /// Decode `s` (its window), multiply by `db`, limit at `ceiling`, write a
    /// 16-bit WAV to `out`. Returns the deepest gain reduction in dB.
    @discardableResult
    static func renderBoost(_ s: Source, db: Double, to out: URL) throws -> Double {
        guard let pcm = try Loudness.decode(s.url, start: s.start, end: s.end),
              let frames = pcm.channels.first?.count, frames > 0 else {
            throw Loudness.Failure.unreadable("no audio to render")
        }
        let gain = Float(pow(10, db / 20))
        let g = limiterGains(frames: frames, sampleRate: pcm.sampleRate, gain: gain) { i in
            pcm.channels.reduce(0) { max($0, abs($1[i])) }
        }
        let minGain = g.min() ?? 1
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: pcm.sampleRate,
                                   channels: AVAudioChannelCount(pcm.channels.count), interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for (c, ch) in pcm.channels.enumerated() {
            let dst = buffer.floatChannelData![c]
            for i in 0..<frames { dst[i] = ch[i] * gain * g[i] }
        }
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = out.deletingPathExtension().appendingPathExtension("part.wav")
        try? FileManager.default.removeItem(at: tmp)
        do {
            let file = try AVAudioFile(forWriting: tmp, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: pcm.sampleRate,
                AVNumberOfChannelsKey: pcm.channels.count,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: tmp, to: out)
        return minGain < 1 ? -20 * log10(Double(minGain)) : 0
    }

    /// Per-frame gain (0…1) that keeps `peak(i) × gain` under `ceiling`.
    /// Offline, so it looks ahead: the gain ramps down over `attack` BEFORE a
    /// peak (no overshoot, no click) and recovers over `release` after it.
    static func limiterGains(frames n: Int, sampleRate: Double, gain: Float,
                             attack: Double = 0.005, release: Double = 0.12,
                             peak: (Int) -> Float) -> [Float] {
        guard n > 0 else { return [] }
        var g = [Float](repeating: 1, count: n)
        for i in 0..<n {
            let p = peak(i) * gain
            if p > ceiling { g[i] = ceiling / p }
        }
        let down = Float(1 / max(1, attack * sampleRate))
        if n > 1 { for i in stride(from: n - 2, through: 0, by: -1) { g[i] = min(g[i], g[i + 1] + down) } }
        let up = Float(1 / max(1, release * sampleRate))
        for i in 1..<n { g[i] = min(g[i], g[i - 1] + up) }
        return g
    }

    // MARK: - Persistence

    private func load() {
        guard let data = FileManager.default.contents(atPath: storageURL.path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let b = obj["boosts"] as? [String: NSNumber] { target = b.mapValues { $0.doubleValue } }
        if let r = obj["ready"] as? [String: [String: Any]] {
            for (k, v) in r {
                guard let db = (v["db"] as? NSNumber)?.doubleValue, let renders = v["renders"] as? [String: String] else { continue }
                ready[k] = Ready(db: db, limitedDb: (v["limitedDb"] as? NSNumber)?.doubleValue ?? 0, renders: renders)
            }
        }
    }

    private func save() {
        let readyObj = ready.mapValues { ["db": $0.db, "limitedDb": $0.limitedDb, "renders": $0.renders] as [String: Any] }
        let obj: [String: Any] = ["boosts": target, "ready": readyObj]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted]) else { return }
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: .atomic)
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        return String((String(data: data, encoding: .utf8) ?? "[\"\"]").dropFirst().dropLast())
    }
}
