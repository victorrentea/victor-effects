import AVFoundation
import Foundation

/// ＋ A clip made louder ON DISK, 1.5 dB per press of the ＋ beside the tablet's
/// per-tile bar (Victor, 2026-11-09). The bar itself only turns a clip down
/// (`SoundGains`); this is how a quiet one comes up, without anything playing
/// above ×1 at runtime.
///
/// - **Per FILE, pressed per tile.** A press on a tile raises every file that
///   tile is heard as (`TileAudio.files`: #31 → the gong, #19 → both takes,
///   #9 → the long hymn), so what the ＋ changes is what the room hears. A file
///   two tiles share (the gong: #31 and #50; the "ching": #53 and #57) is ONE
///   boost — a ＋ on either is heard on both. A video's "file" is `video:<id>`:
///   only the AUDIO of its played window (from `startSeconds`, the player's
///   60 s), which addons lays over the untouched mp4 in an `AVMutableComposition`.
///   The mp4 is never touched — the YouTube-publish guard fingerprints it.
/// - **Always rendered from the ORIGINAL**, at the file's total boost — never
///   from the previous render, so ten presses are one gain stage, not ten (and
///   no codec generation loss: the render is 16-bit WAV). The original is never
///   overwritten or deleted; reset (long-press ＋) simply plays it again.
/// - **Through a look-ahead peak limiter at −1 dBFS** (`ceiling`). How hard it
///   had to work is kept as `limitedDb` (the deepest gain reduction); above
///   `limitedHintDb` the tablet says "limitat" — more presses now buy less.
/// - **Heard everywhere the file plays**: `SoundManager.soundURL(for:)` answers
///   with the render (`renderURL(forFile:)`), and every path — the routed play
///   and the special ones in `EmojiAnimator` — resolves its file there.
/// - **Rendered on the press, off the main thread**; while it runs the clip is
///   `busy` and every play uses the previous render (or the original). Renders
///   live in `~/.victor-effects/boosted/`, named after the original's size and
///   mtime, so a replaced original is not played stale and is rendered again
///   (`resume()`). The table is `~/.victor-effects/disk-boosts.json`.
final class DiskBoosts {
    static let shared = DiskBoosts()

    static let stepDb = 1.5
    /// Eight presses. Past this the limiter is doing the work, not the gain.
    static let maxDb = 12.0
    /// −1 dBFS: where the limiter holds the render's peaks.
    static let ceiling: Float = 0.891
    /// "limitat" on the tablet when the limiter took more than this off a peak.
    static let limitedHintDb = 1.0

    struct Source: Equatable {
        /// The boost's key: the sound file's name, or `video:<id>`.
        let key: String
        /// The original's file name — the render is named after it.
        let name: String
        let url: URL
        var start: Double = 0
        var end: Double? = nil
    }

    struct Ready: Equatable {
        var db: Double
        var limitedDb: Double
        /// The render's file name (in `dir`).
        var render: String
    }

    private(set) var target: [String: Double] = [:]
    private(set) var ready: [String: Ready] = [:]
    private var pending: [String: Int] = [:]
    private let queue = DispatchQueue(label: "disk-boosts", qos: .userInitiated)

    /// What `renderURL(forFile:)` reads — from any thread (the players resolve
    /// their files on background queues too).
    private let lock = NSLock()
    private var playable: [String: (render: URL, source: Source)] = [:]

    var storageURL: URL
    var dir: URL
    /// Seams for the tests: a clip's file keys, and a file key's original.
    var filesOf: (String) -> [String] = DiskBoosts.liveFiles
    var sourceOf: (String) -> Source? = DiskBoosts.liveSource { didSet { publish() } }

    init(storage: URL? = nil, dir: URL? = nil) {
        let base = URL(fileURLWithPath: EffectsConfig.configDir)
        storageURL = storage ?? base.appendingPathComponent("disk-boosts.json")
        self.dir = dir ?? base.appendingPathComponent("boosted", isDirectory: true)
        load()
        publish()
    }

    // MARK: - Playing (any thread)

    /// The render to play for `file` (a sound file's name, or `video:<id>`),
    /// when its boost is on and the render was made from the original as it is
    /// on disk now; nil = play the original.
    func renderURL(forFile file: String) -> URL? {
        lock.lock()
        let p = playable[file]
        lock.unlock()
        guard let p else { return nil }
        let expected = Self.renderName(p.source, db: 0)
        // Same original (size + mtime) as the render was made from?
        guard p.render.lastPathComponent.hasPrefix(String(expected.prefix { $0 != "+" })),
              FileManager.default.fileExists(atPath: p.render.path) else {
            DispatchQueue.main.async { [weak self] in self?.resume() }
            return nil
        }
        return p.render
    }

    private func publish() {
        var next: [String: (render: URL, source: Source)] = [:]
        for (key, r) in ready where r.db > 0 {
            guard let s = sourceOf(key) else { continue }
            next[key] = (dir.appendingPathComponent(r.render), s)
        }
        lock.lock()
        playable = next
        lock.unlock()
    }

    // MARK: - Reading, per clip (main thread)

    func boostDb(_ clip: String) -> Double { filesOf(clip).map { target[$0] ?? 0 }.max() ?? 0 }
    func readyDb(_ clip: String) -> Double { filesOf(clip).map { ready[$0]?.db ?? 0 }.max() ?? 0 }
    func isBusy(_ clip: String) -> Bool { filesOf(clip).contains { (pending[$0] ?? 0) > 0 } }
    func limitedDb(_ clip: String) -> Double { filesOf(clip).map { ready[$0]?.limitedDb ?? 0 }.max() ?? 0 }

    /// The render of the tile's OWN file — what the tablet downloads for its
    /// local plays (it plays the tile's own mp3). Nil when the tile is heard as
    /// another file, or has no render.
    func tabletFile(_ clip: String) -> URL? {
        guard !clip.hasPrefix("video:"), filesOf(clip).contains(clip) else { return nil }
        return renderURL(forFile: clip)
    }

    /// Every ready render of `clip`, by the original's file name — for the
    /// loudness pass, which judges a clip as it plays now.
    func renders(_ clip: String) -> [String: URL] {
        var out: [String: URL] = [:]
        for f in filesOf(clip) {
            guard let r = ready[f], r.db > 0, let s = sourceOf(f) else { continue }
            out[s.name] = dir.appendingPathComponent(r.render)
        }
        return out
    }

    /// Every ready render, by the ORIGINAL's file name (the mp4's for a video).
    var allRenders: [String: URL] {
        var out: [String: URL] = [:]
        for (k, r) in ready where r.db > 0 {
            if let s = sourceOf(k) { out[s.name] = dir.appendingPathComponent(r.render) }
        }
        return out
    }

    // MARK: - Writing, per clip (main thread)

    /// One ＋ press: every file the clip is heard as goes 1.5 dB up. False for a
    /// clip with nothing to render (unknown, or a sound made in code).
    @discardableResult
    func press(_ clip: String) -> Bool {
        let sources = filesOf(clip).compactMap(sourceOf)
        guard !sources.isEmpty else { return false }
        var changed = false
        for s in sources {
            let db = min(Self.maxDb, (target[s.key] ?? 0) + Self.stepDb)
            guard db != target[s.key] else { continue }
            target[s.key] = db
            render(s, db: db)
            changed = true
        }
        if changed { save() }
        return true
    }

    /// Long-press ＋: the clip's files back to their originals. The renders go;
    /// the originals were never touched.
    func reset(_ clip: String) {
        for f in filesOf(clip) {
            target[f] = nil
            if let old = ready.removeValue(forKey: f) { delete(old.render) }
        }
        save()
        publish()
    }

    /// Render whatever a stored boost is missing — at launch, or when an
    /// original turned out to have been replaced.
    func resume() {
        for (key, db) in target where db > 0 && (pending[key] ?? 0) == 0 {
            guard let s = sourceOf(key) else { continue }
            let name = Self.renderName(s, db: db)
            let complete = ready[key]?.db == db && ready[key]?.render == name
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
            if !complete { render(s, db: db) }
        }
    }

    /// Block until every queued render is done — the tests' and proof's handle.
    func waitForRenders() {
        queue.sync {}
        if Thread.isMainThread { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    private func render(_ s: Source, db: Double) {
        pending[s.key, default: 0] += 1
        let dir = self.dir
        queue.async { [weak self] in
            let started = Date()
            let name = Self.renderName(s, db: db)
            var limited = 0.0
            var failure: String?
            do {
                limited = try Self.renderBoost(s, db: db, to: dir.appendingPathComponent(name))
            } catch {
                failure = "\(error)"
            }
            let finish = {
                guard let self else { return }
                self.pending[s.key, default: 1] -= 1
                if self.pending[s.key] == 0 { self.pending[s.key] = nil }
                if let failure {
                    effectsError("＋ render of \(s.key) at +\(db) dB failed: \(failure)")
                    if self.ready[s.key]?.render != name { self.delete(name) }
                } else if self.target[s.key] == db {
                    if let old = self.ready[s.key], old.render != name { self.delete(old.render) }
                    self.ready[s.key] = Ready(db: db, limitedDb: limited, render: name)
                    self.save()
                    self.publish()
                    effectsInfo("＋ \(s.key) +\(db) dB ready in " + String(format: "%.2f s", Date().timeIntervalSince(started))
                        + String(format: ", limiter %.1f dB", limited))
                } else if self.ready[s.key]?.render != name {
                    self.delete(name)   // superseded by a later press or a reset
                }
            }
            if Thread.isMainThread { finish() } else { DispatchQueue.main.async(execute: finish) }
        }
    }

    private func delete(_ render: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(render))
    }

    // MARK: - The served state

    /// Moves `gainsHash` whenever a boost, its readiness or its busy state moves.
    var stateKey: String {
        Set(target.keys).union(ready.keys).union(pending.keys).sorted().map { k in
            "\(k):\(target[k] ?? 0):\(ready[k]?.db ?? 0):\((pending[k] ?? 0) > 0):"
                + (ready[k].map { String(format: "%.1f", $0.limitedDb) } ?? "-")
        }.joined(separator: "\n")
    }

    /// `,"boosts":{…}` for `GET /sound/gains`, one row per CLIP whose files carry
    /// any state — every tile that plays a boosted file, so #31 and #50 both
    /// show the gong's boost.
    func jsonFields(tiles: [String]) -> String {
        let state = Set(target.keys).union(ready.keys).union(pending.keys)
        let clips = Set(tiles).union(state).filter { !Set(filesOf($0)).isDisjoint(with: state) }
        let rows = clips.sorted().map { k -> String in
            let rev = tabletFile(k).map { ",\"rev\":\"\($0.lastPathComponent)\"" } ?? ""
            let lim = limitedDb(k)
            return "\"\(k)\":{\"db\":\(boostDb(k)),\"readyDb\":\(readyDb(k)),\"busy\":\(isBusy(k)),"
                + "\"limitedDb\":" + String(format: "%.2f", lim)
                + ",\"limited\":\(lim > Self.limitedHintDb)\(rev)}"
        }
        return ",\"boosts\":{\(rows.joined(separator: ","))}"
    }

    var jsonFields: String {
        jsonFields(tiles: TilesManifest.load()?.doc.tiles.flatMap { [$0.asset] + ($0.under.map { [$0.asset] } ?? []) } ?? [])
    }

    /// `GET /sound/boost/<key>` — what addons asks at a video's play.
    func infoJSON(_ clip: String) -> String {
        var audio = "null"
        if clip.hasPrefix("video:"), let url = renderURL(forFile: clip), let s = sourceOf(clip) {
            audio = "{\"path\":\(Self.jsonString(url.path)),\"start\":\(s.start)}"
        }
        return "{\"key\":\(Self.jsonString(clip)),\"db\":\(boostDb(clip)),\"readyDb\":\(readyDb(clip)),"
            + "\"busy\":\(isBusy(clip)),\"audio\":\(audio)}"
    }

    // MARK: - Sources

    static func liveFiles(_ clip: String) -> [String] {
        clip.hasPrefix("video:") ? [clip] : TileAudio.files(forTile: clip)
    }

    static func liveSource(_ key: String) -> Source? {
        if key.hasPrefix("video:") {
            guard let vdir = EffectsConfig.shared.videosDir,
                  let data = FileManager.default.contents(atPath: vdir.appendingPathComponent("videos.json").path),
                  let clip = RecommendedVolumes.videoClips(manifest: data, videosDir: vdir).first(where: { $0.key == key }),
                  let url = clip.files.first, FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Source(key: key, name: url.lastPathComponent, url: url, start: clip.start, end: clip.end)
        }
        guard let url = SoundManager.shared.originalURL(for: key) else { return nil }
        return Source(key: key, name: key, url: url)
    }

    /// `<stem>.<size>-<mtime>[.s<start>-<len>].+<db>dB.wav`: a replaced original
    /// or a different boost is a different name, so a stale render is never played.
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
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (obj["version"] as? Int) == 2 else { return }
        if let b = obj["boosts"] as? [String: NSNumber] { target = b.mapValues { $0.doubleValue } }
        if let r = obj["ready"] as? [String: [String: Any]] {
            for (k, v) in r {
                guard let db = (v["db"] as? NSNumber)?.doubleValue, let render = v["render"] as? String else { continue }
                ready[k] = Ready(db: db, limitedDb: (v["limitedDb"] as? NSNumber)?.doubleValue ?? 0, render: render)
            }
        }
    }

    private func save() {
        let readyObj = ready.mapValues { ["db": $0.db, "limitedDb": $0.limitedDb, "render": $0.render] as [String: Any] }
        let obj: [String: Any] = ["version": 2, "boosts": target, "ready": readyObj]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted]) else { return }
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: .atomic)
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        return String((String(data: data, encoding: .utf8) ?? "[\"\"]").dropFirst().dropLast())
    }
}
