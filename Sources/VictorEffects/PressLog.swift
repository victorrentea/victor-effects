import Foundation

/// Who pressed: the tablet (HTTP), the Mac's own thumbnail panel (in-process),
/// or anything else (e.g. a `/press/<n>` link fired by a script or the daemon).
enum PressSource: String, Equatable {
    case tablet, panel, other
}

/// Append-only record of every press `UsageCounts` counts, one JSON object per
/// line in `pressLogFile` (default `~/.victor-effects/presses.jsonl`):
///
///     {"ts":"2026-10-22T17:32:01.123+03:00","file":"53b_7_rings.mp3","n":53,"layer":"b","source":"tablet"}
///
/// `UsageCounts` says *how many*; this says *when*. `n`/`layer` come from the
/// loaded `tiles.json` (layer `"b"` for an `under` tile, which shares its
/// host's `n`); a file that is not on the grid logs `"n":null,"layer":null`.
///
/// Best-effort by construction: the write happens on a utility queue, and a
/// failure is logged — never thrown into the press.
enum PressLog {
    private static let queue = DispatchQueue(label: "victor-effects-presslog", qos: .utility)

    /// Test seam, like `UsageCounts.storageURL`: nil = use the configured file.
    static var overrideURL: URL?

    static var fileURL: URL {
        overrideURL ?? URL(fileURLWithPath: EffectsConfig.expand(EffectsConfig.shared.values.pressLogFile))
    }

    /// Call on the main thread (it reads the cached tiles manifest); the I/O
    /// itself is hopped off it.
    static func append(file: String, source: PressSource, now: Date = Date()) {
        guard !file.isEmpty else { return }
        let resolved = resolve(file, in: TilesManifest.load()?.doc)
        let line = format(ts: now, file: file, n: resolved.n, layer: resolved.layer, source: source)
        let url = fileURL
        queue.async { write(line + "\n", to: url) }
    }

    /// Block until queued writes landed. Tests only.
    static func flush() { queue.sync {} }

    /// Which tile `file` is on the grid: layer "a" if it is a top tile's asset,
    /// "b" if it is the `under` of one (same `n`).
    static func resolve(_ file: String, in doc: TilesDocument?) -> (n: Int?, layer: String?) {
        guard let doc else { return (nil, nil) }
        for t in doc.tiles {
            if t.asset == file { return (t.n, "a") }
            if let u = t.under, u.asset == file { return (t.n, "b") }
        }
        return (nil, nil)
    }

    static func format(ts: Date, file: String, n: Int?, layer: String?, source: PressSource) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nPart = n.map(String.init) ?? "null"
        let layerPart = layer.map { "\"\($0)\"" } ?? "null"
        return "{\"ts\":\"\(f.string(from: ts))\",\"file\":\"\(escape(file))\",\"n\":\(nPart),"
            + "\"layer\":\(layerPart),\"source\":\"\(source.rawValue)\"}"
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out
    }

    private static func write(_ text: String, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Data(text.utf8))
        } catch {
            effectsError("cannot append to press log \(url.path): \(error)")
        }
    }
}
