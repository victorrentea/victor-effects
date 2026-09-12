import Foundation

/// The one place this app dials **out**, to the addons app on
/// `EffectsConfig.addonsBaseURL` (normally 55123).
///
/// Everything else in the split goes the other way — addons proxies the sound
/// and effect routes *here* — but `/videos` and `/video/*` are addons-local and
/// deliberately not proxied back: the video library, IINA, the display
/// arrangement and the auto-kill all live over there, and duplicating a proxy
/// hop for them would only add a way for the two halves to disagree about what
/// is playing.
///
/// **Synchronous, with a hard 1.5 s cap.** The caller is a hold gesture on the
/// main thread and the answer is needed before the panel can be sized, so this
/// blocks — but over loopback it costs milliseconds, and the one case where it
/// costs the full timeout (addons down) is the case that then draws the "no
/// videos" tile. A background fetch would mean a panel that appears empty and
/// resizes itself a moment later, under a key somebody is still holding.
enum AddonsClient {
    /// Long enough for a loopback answer carrying eighteen inline JPEGs, short
    /// enough that a dead addons app is a stutter and not a hang.
    static let timeout: TimeInterval = 1.5

    static var baseURL: String { EffectsConfig.shared.addonsBaseURL }

    /// `GET <addonsBaseURL><path>` → the body, or nil for any failure at all
    /// (no base URL configured, refused connection, timeout, non-200). Every
    /// caller degrades the same way, so there is nothing to tell apart.
    static func get(_ path: String) -> Data? {
        let base = baseURL
        guard !base.isEmpty, let url = URL(string: base + path) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        var result: Data?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { result = data }
            done.signal()
        }.resume()
        // `+0.5` so the semaphore is never the thing that gives up first: the
        // request's own timeout has to be what fails, or a cancelled-looking
        // wait would leave the task running and the next press queueing behind it.
        _ = done.wait(timeout: .now() + timeout + 0.5)
        return result
    }

    /// Same, as text — for the little JSON bodies the play routes answer with.
    static func getText(_ path: String) -> String? {
        get(path).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// One tile on the panel's video page — the tablet's page 2, on the Mac.
struct VideoTile: Equatable {
    /// The `#NN` badge: the tile's **1-based place in the order the Mac serves**,
    /// nothing else, so it renumbers itself when a video is added. Same rule as
    /// the tablet (`buildSnippetTile`, `index + 1`), and the same rule
    /// `/test/thumbnail-panel/press/<n>?page=videos` addresses it by.
    let n: Int
    let id: String
    let title: String
    let startSeconds: Int
    /// The tile picture, decoded from the base64 JPEG `GET /videos` carries
    /// inline. Inline and not a URL because that is how the tablet gets it too —
    /// one call, one truth, and nothing to fetch per tile.
    let thumb: Data?
}

/// The video list, fetched from addons.
///
/// **Refreshed on every show, cached for the session.** Refreshed because a
/// video added with the `add-training-video` skill has to appear without
/// restarting this app — the same promise the tablet makes. Cached because the
/// refresh is allowed to fail: a Mac whose addons app is restarting must still
/// draw the board it drew a minute ago, rather than replace eighteen tiles with
/// an error.
enum VideosManifest {
    private(set) static var cached: [VideoTile] = []

    /// Parse `{"videos":[{id,title,startSeconds,thumb}]}`. Pure, so the tests
    /// feed it a literal instead of depending on another app being up.
    ///
    /// Lenient in the same way `TilesManifest` is: an entry missing its title or
    /// its thumbnail still becomes a tile, because the list is written by a repo
    /// this one does not own.
    static func parse(_ data: Data) -> [VideoTile] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = obj["videos"] as? [[String: Any]] else { return [] }
        // Numbered AFTER the drop, not before it: `#NN` is the tile's place on
        // the board the eye is reading, so a row this app refused has to close
        // up behind it rather than leave a hole in the badges.
        return rows.compactMap { row -> (String, [String: Any])? in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            return (id, row)
        }.enumerated().map { index, entry in
            let (id, row) = entry
            return VideoTile(n: index + 1,
                             id: id,
                             title: (row["title"] as? String) ?? id,
                             startSeconds: (row["startSeconds"] as? Int) ?? 0,
                             thumb: (row["thumb"] as? String).flatMap { Data(base64Encoded: $0) })
        }
    }

    /// Ask addons now; keep the last good answer if it does not come.
    @discardableResult
    static func refresh() -> [VideoTile] {
        if let data = AddonsClient.get("/videos") {
            let tiles = parse(data)
            if !tiles.isEmpty {
                cached = tiles
                return tiles
            }
            // A 200 carrying an empty list is a real answer — an addons app with
            // no `videos/` folder — and it replaces the cache rather than hiding
            // behind it.
            cached = []
            return []
        }
        return cached
    }

    static func tile(number: Int) -> VideoTile? { cached.first { $0.n == number } }

    static func invalidate() { cached = [] }
}

/// What pressing a video tile means — a port of the tablet's `onSnippetTouch`
/// tap half: **tap plays the clip, tapping the one that is playing stops it**.
///
/// The tablet's other gesture on that tile (hold three seconds → the soundtrack
/// alone, `GET /video/sound/<id>`) is deliberately not here: it is a gesture for
/// a finger, and the panel is already being held open with the other hand.
///
/// Unlike `SoundboardPress` this does not go through `EffectsRouter` — the
/// player lives in the other process, so the press IS an HTTP call, and it is
/// the only thing on this side that is.
final class VideoPress {
    /// The clip that is running, for the pulsing red border.
    private(set) var playing: VideoTile?
    var onPlayingChanged: ((VideoTile?) -> Void)?

    /// Swapped in the tests, exactly like `SoundboardPress.schedule`.
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The transport, so a test can press a tile without an addons app.
    var get: (String) -> String? = { AddonsClient.getText($0) }

    /// Completion timers are outvoted, not cancelled — the same guard
    /// `SoundboardPress` carries, for the same reason.
    private var generation = 0

    @discardableResult
    func press(_ tile: VideoTile) -> String {
        if playing?.id == tile.id {
            generation += 1
            _ = get("/video/stop")
            setPlaying(nil)
            return "{\"ok\":true,\"n\":\(tile.n),\"id\":\"\(tile.id)\",\"action\":\"stop\"}"
        }
        guard let body = get("/video/play/\(tile.id)") else {
            return "{\"ok\":false,\"n\":\(tile.n),\"id\":\"\(tile.id)\",\"reason\":\"addons-down\"}"
        }
        // `durationMs` is the shorter of what is left of the clip and the
        // auto-kill window — the same contract the tablet pins its page open
        // for, and here it is how long the border pulses.
        let durationMs = SoundboardPress.durationMs(from: body)
        setPlaying(tile)
        generation += 1
        let gen = generation
        if durationMs > 0 {
            schedule(Double(durationMs + 100) / 1000) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.setPlaying(nil)
            }
        }
        return "{\"ok\":true,\"n\":\(tile.n),\"id\":\"\(tile.id)\","
            + "\"action\":\"play\",\"durationMs\":\(durationMs)}"
    }

    /// The clip can also end in ways this side cannot see (it runs out, IINA is
    /// closed by hand, the auto-kill fires). Nothing polls for that here — the
    /// border is cleared by the `durationMs` the play answered with, which is
    /// exactly the deadline addons armed.
    func stop() {
        guard playing != nil else { return }
        generation += 1
        _ = get("/video/stop")
        setPlaying(nil)
    }

    private func setPlaying(_ tile: VideoTile?) {
        guard playing != tile else { return }
        playing = tile
        onPlayingChanged?(tile)
    }
}
