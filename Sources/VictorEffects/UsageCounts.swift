import CryptoKit
import Foundation

/// How many times each tile has been pressed — **on this Mac, for every
/// surface**: the tablet reports each press over HTTP (`/sound/pressed/<file>`,
/// `/alarm/start` for the siren) and the thumbnail panel presses through the
/// same router in-process, so one counter sees both.
///
/// It lives here rather than on the tablet because the tablet is a *client*: it
/// used to keep the only copy, which meant the panel's presses were invisible to
/// the green dots, and a reinstall took the history with it. The dots are still
/// drawn on the tablet — from these numbers, adopted on connect.
///
/// Storage is a small JSON file next to the config (`usageFile`), rewritten on
/// every press: ~91 short entries, far cheaper than the sound it is counting,
/// and a crash mid-workshop must not lose the session's history.
enum UsageCounts {
    private static var counts: [String: Int] = load()
    /// Set once the first time a press is recorded, so `/ping` does not stat the
    /// file to answer "did anything change".
    private static var cachedHash: String?

    /// Where the counts are stored. A `var` purely so the tests can point it at
    /// a scratch file: they exercise `record`/`merge`/`reset`, and those write —
    /// against the default path a single `swift test` would overwrite the real
    /// history of a real tablet, which is not a thing a test may do.
    static var storageURL: URL = defaultURL

    static var defaultURL: URL {
        URL(fileURLWithPath: EffectsConfig.expand(EffectsConfig.shared.values.usageFile))
    }

    // MARK: - Reading

    static var all: [String: Int] { counts }

    /// SHA-256 over the sorted `asset:count` lines. Reported in `/ping` so a
    /// client can tell in one 5-second ping whether the numbers it is drawing
    /// are still this Mac's, without pulling the whole table on a timer.
    static var hash: String {
        if let cachedHash { return cachedHash }
        let joined = counts.keys.sorted().map { "\($0):\(counts[$0]!)" }.joined(separator: "\n")
        let h = SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
        cachedHash = h
        return h
    }

    /// Body of `GET /usage`. Carries the hash it was computed from, so a client
    /// that adopts the table can record "I am now at this hash" without a second
    /// round trip — and without trusting a `/ping` that may have crossed it.
    static var json: String {
        let body = counts.keys.sorted()
            .map { "\"\($0)\":\(counts[$0]!)" }
            .joined(separator: ",")
        return "{\"counts\":{\(body)},\"hash\":\"\(hash)\"}"
    }

    // MARK: - Writing

    /// One press of `asset`. Every press, from every surface — the filtering
    /// (the restartable money tile is kept out of the *ruler* the dots are
    /// measured against) is a rendering decision and stays with the renderer.
    static func record(_ asset: String) {
        guard !asset.isEmpty else { return }
        counts[asset, default: 0] += 1
        cachedHash = nil
        save()
    }

    /// Merge a client's historical totals in, keeping the LARGER of the two per
    /// asset. Max-merge rather than add so the tablet can seed its years of
    /// history once and a repeated (or retried) seed cannot inflate anything —
    /// the operation is idempotent, which matters for something a flaky link may
    /// deliver twice.
    static func merge(_ incoming: [String: Int]) {
        var changed = false
        for (asset, count) in incoming where count > (counts[asset] ?? 0) {
            counts[asset] = count
            changed = true
        }
        guard changed else { return }
        cachedHash = nil
        save()
    }

    static func reset() {
        counts = [:]
        cachedHash = nil
        save()
    }

    // MARK: - Persistence

    private static func load() -> [String: Int] {
        guard let data = FileManager.default.contents(atPath: storageURL.path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let stored = obj["counts"] as? [String: Int] else { return [:] }
        return stored
    }

    private static func save() {
        let file = storageURL
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(json.utf8).write(to: file, options: .atomic)
        } catch {
            effectsError("cannot write usage counts to \(file.path): \(error)")
        }
    }

    /// Testing seam: re-point the counter at `file` and reload from it, which is
    /// exactly what happens at launch. Tests pass a scratch path — against the
    /// default one a single `swift test` would overwrite the real history of a
    /// real tablet.
    static func useForTesting(_ file: URL) {
        storageURL = file
        counts = load()
        cachedHash = nil
    }
}
