import AVFoundation
import Foundation

/// 🔉 A tile turned up past the tablet's white tick (green bar above 80) must
/// actually get louder — and an `AVAudioPlayer` cannot: its `volume` stops at
/// 1.0, so with the blue master near the top `min(1, master × tile)` threw the
/// whole boost away (Victor, 2026-10-30: "green up and the Mac is no louder").
///
/// So a boosted tile plays a **pre-amplified copy** of its file: rendered once,
/// off the main thread, at the largest gain the bar can ask for
/// (`headroom`, ×1.56 at position 100) through a peak limiter so the extra
/// loudness does not come out as clipping, and kept in the caches folder. The
/// player then runs at `master × tile / headroom`, which is ≤ 1 for every bar
/// position — the multiplication the tablet's two bars promise, with nothing cut.
///
/// The copy only stands in while the tile is above ×1; at or below the tick the
/// untouched original plays. A press that finds no copy yet plays the original
/// (capped, as before) and starts the render for the next one.
enum BoostedClips {
    /// The loudest a tile can be asked to play — the top of the green bar.
    static let headroom: Float = SoundGains.gain(position: 100)

    /// Where the limiter holds the peaks of the amplified copy (≈ −0.5 dBFS).
    static let ceiling: Float = 0.94

    private static let queue = DispatchQueue(label: "boosted-clips", qos: .utility)
    private static let lock = NSLock()
    private static var rendering: Set<String> = []

    static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VictorEffects/boosted", isDirectory: true)
    }

    /// The file to play for `source` at amplitude `gain`, and the factor already
    /// baked into it (divide the player's volume by it). The original and 1
    /// unless the tile is boosted and its copy is ready.
    static func source(for source: URL, gain: Float) -> (url: URL, boost: Float) {
        guard gain > 1.001, let copy = copyURL(for: source) else { return (source, 1) }
        if FileManager.default.fileExists(atPath: copy.path) { return (copy, headroom) }
        prepare(source)
        return (source, 1)
    }

    /// Render `source`'s amplified copy in the background, if it is not on disk yet.
    static func prepare(_ source: URL) {
        guard let copy = copyURL(for: source),
              !FileManager.default.fileExists(atPath: copy.path) else { return }
        lock.lock()
        let fresh = rendering.insert(copy.path).inserted
        lock.unlock()
        guard fresh else { return }
        queue.async {
            defer { lock.lock(); rendering.remove(copy.path); lock.unlock() }
            let started = Date()
            do {
                try render(source, to: copy)
                effectsInfo("🔉 boosted copy of \(source.lastPathComponent) ready in "
                    + String(format: "%.2f", Date().timeIntervalSince(started)) + " s")
            } catch {
                try? FileManager.default.removeItem(at: copy)
                overlayError("🔉 boosted copy of \(source.lastPathComponent) failed: \(error)")
            }
        }
    }

    /// Named after the source's name, size and modification time, so an mp3
    /// replaced in `soundsDir` gets a fresh copy instead of last week's.
    private static func copyURL(for source: URL) -> URL? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: source.path),
              let size = a[.size] as? Int,
              let mtime = (a[.modificationDate] as? Date)?.timeIntervalSince1970 else { return nil }
        let stem = source.deletingPathExtension().lastPathComponent
        return cacheDir.appendingPathComponent("\(stem)-\(size)-\(Int(mtime))-x\(Int(headroom * 100)).caf")
    }

    private static func render(_ source: URL, to copy: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let frames = AVAudioFrameCount(input.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData else { return }
        try input.read(into: buffer)
        let channels = (0..<Int(format.channelCount)).map { data[$0] }
        let n = Int(buffer.frameLength)
        let gains = limiterGains(frames: n, sampleRate: format.sampleRate) { i in
            channels.reduce(0) { max($0, abs($1[i])) }
        }
        for ch in channels {
            for i in 0..<n { ch[i] *= headroom * gains[i] }
        }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let tmp = copy.appendingPathExtension("part")
        do {
            let out = try AVAudioFile(forWriting: tmp, settings: format.settings,
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
            try out.write(from: buffer)
        }
        try FileManager.default.moveItem(at: tmp, to: copy)
    }

    /// Per-frame gain (0…1) that keeps `peak(i) × headroom` under `ceiling`.
    /// Offline, so it can look ahead: the gain ramps down over `attack` BEFORE a
    /// peak (no overshoot, no click) and recovers over `release` after it.
    static func limiterGains(frames n: Int, sampleRate: Double,
                             attack: Double = 0.005, release: Double = 0.12,
                             peak: (Int) -> Float) -> [Float] {
        guard n > 0 else { return [] }
        var g = [Float](repeating: 1, count: n)
        for i in 0..<n {
            let p = peak(i) * headroom
            if p > ceiling { g[i] = ceiling / p }
        }
        let down = Float(1 / max(1, attack * sampleRate))
        if n > 1 { for i in stride(from: n - 2, through: 0, by: -1) { g[i] = min(g[i], g[i + 1] + down) } }
        let up = Float(1 / max(1, release * sampleRate))
        for i in 1..<n { g[i] = min(g[i], g[i - 1] + up) }
        return g
    }
}
