import CryptoKit
import Foundation

/// SHA-256 manifest of the soundboard folder (`soundsDir/*.mp3`). A client that
/// holds its own copy of the same sounds — the tablet does — computes the same
/// manifest and compares the combined hash it gets from `/ping`: a mismatch
/// means this Mac's copy differs, and the client plays those files itself
/// instead of routing them here.
///
/// Computed over the live folder, not over a bundle: since the sounds stopped
/// being an app resource there is no such thing as a "stale bundle" to detect
/// — replacing an mp3 changes the hash on the next launch, with no rebuild.
///
/// Canonical form (must match the Android side exactly):
///   - all *.mp3 files in the folder, sorted by filename
///   - one line per file: "<filename>:<sha256-hex-lowercase>\n"
///   - combined hash = SHA-256 hex of the concatenated lines
enum SoundsManifest {
    /// filename → SHA-256 hex, computed on first access (~15MB, <100ms) and
    /// cached — but ONLY a non-empty result is cached. An empty one means the
    /// folder wasn't resolvable at that instant (a `swift build` had just put
    /// the unresolvable symlink back, see `SoundManager.sharedSoundsDir`), and
    /// caching that would have this app advertise a bogus hash to the tablet
    /// for the rest of its life — telling it every sound differs, i.e. "play
    /// them yourself" — long after the folder came back.
    static var files: [String: String] {
        if let cached = cachedFiles { return cached }
        let computed = computeFiles()
        if !computed.isEmpty { cachedFiles = computed }
        return computed
    }

    private static var cachedFiles: [String: String]?

    /// Drop the cache — `GET /config/reload` may have pointed `soundsDir`
    /// somewhere else entirely.
    static func invalidate() { cachedFiles = nil }

    /// Hash a folder without touching the cached one. Used by the tests, which
    /// must not depend on whatever this machine has configured.
    static func combinedHash(ofDirectory dir: URL) -> String {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var files: [String: String] = [:]
        for url in urls where url.pathExtension.lowercased() == "mp3" {
            guard let data = try? Data(contentsOf: url) else { continue }
            files[url.lastPathComponent] = SHA256.hash(data: data).hexString
        }
        let joined = files.keys.sorted().map { "\($0):\(files[$0]!)\n" }.joined()
        return SHA256.hash(data: Data(joined.utf8)).hexString
    }

    /// The single value the tablet compares on every /ping.
    static var combinedHash: String {
        let f = files
        let joined = f.keys.sorted().map { "\($0):\(f[$0]!)\n" }.joined()
        return SHA256.hash(data: Data(joined.utf8)).hexString
    }

    /// JSON for GET /sounds/manifest — fetched by the tablet only on a
    /// combined-hash mismatch, to compute the per-file fallback set.
    static var manifestJSON: String {
        let entries = files.keys.sorted()
            .map { "\"\($0)\":\"\(files[$0]!)\"" }
            .joined(separator: ",")
        return "{\"hash\":\"\(combinedHash)\",\"files\":{\(entries)}}"
    }

    private static func computeFiles() -> [String: String] {
        // Same resolution as playback, so the manifest can never advertise a
        // folder the /sound/play path can't read (or vice versa).
        guard let dir = SoundManager.sharedSoundsDir(),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            overlayError("SoundsManifest: no readable soundsDir")
            return [:]
        }
        var result: [String: String] = [:]
        for url in urls where url.pathExtension.lowercased() == "mp3" {
            guard let data = try? Data(contentsOf: url) else { continue }
            result[url.lastPathComponent] = SHA256.hash(data: data).hexString
        }
        return result
    }
}

private extension SHA256Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
