import Foundation

/// Whatever can run a route. `EffectsRouter` in the app, a recorder in the
/// tests — the press semantics are a sequence of routes in a particular order,
/// and the order is the thing worth asserting.
protocol SoundboardDispatcher: AnyObject {
    @discardableResult
    func dispatch(_ pathAndQuery: String) -> EffectsResponse
}

extension EffectsRouter: SoundboardDispatcher {}

/// What pressing a tile means — a port of the tablet's `SfxAdapter.toggle` /
/// `startOnMac` / `completionStopUrl` (MainActivity.kt).
///
/// It is a port and not an invention: the same grid is on a tablet in the room,
/// and a tile that stops the sound there but restarts it here would be a bug in
/// Victor's hands mid-session. The one difference is the transport — the tablet
/// sends HTTP to this Mac, the panel calls `EffectsRouter.dispatch` directly on
/// the main thread, which is the same switch without the socket.
///
/// The order of the calls carries a scar: the tablet learned the hard way that
/// firing `stop-all` and the paired effect from two threads lets the stop land
/// *after* the effect and wipe it. Everything here is sequential for that
/// reason.
final class SoundboardPress {
    /// The siren is the one tile whose visual is a toggled overlay rather than
    /// a self-terminating effect, so it starts and stops through `/alarm/*`
    /// instead of `/sound/pressed|stopped/`.
    static let sirenAsset = "02_siren.mp3"

    private let router: SoundboardDispatcher

    /// Volume the sound is played at, as a percentage. A closure because
    /// `SoundManager` is a main-thread singleton and the tests have no audio.
    var volumePct: () -> Int = { Int((SoundManager.shared.currentTabletVolume * 100).rounded()) }

    /// Runs `work` after `delay`. Swapped in the tests for one that hands the
    /// closure back so "what happens when the sound ends" is a synchronous
    /// assertion instead of a two-second wait.
    var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The tile whose sound is running, for the pulsing red border.
    private(set) var playing: Tile?
    var onPlayingChanged: ((Tile?) -> Void)?

    /// Completion timers are not cancelled, they are *outvoted*: every press
    /// bumps this and a late completion that finds a newer generation does
    /// nothing. Same effect as the tablet's `if (playingPosition == position)`
    /// guard, minus a cancellable handle to keep in sync.
    private var generation = 0

    init(router: SoundboardDispatcher) {
        self.router = router
    }

    /// Press one tile. Returns the JSON body the `/test/…/press/<n>` hook
    /// answers with, which doubles as a description of what happened.
    @discardableResult
    func press(_ tile: Tile) -> String {
        // Re-pressing the tile that is playing stops it — unless the tile is
        // restartable (#53 money), which falls through to the start path and so
        // replays from the top, stacking a fresh round of the effect.
        if let current = playing, current.asset == tile.asset, !tile.restartable {
            stopAll()
            return "{\"ok\":true,\"n\":\(tile.n),\"asset\":\"\(tile.asset)\",\"action\":\"stop\"}"
        }

        stopAll()

        let response = router.dispatch("/sound/play/\(tile.asset)?vol=\(volumePct())")
        guard response.status == 200 else {
            return "{\"ok\":false,\"n\":\(tile.n),\"asset\":\"\(tile.asset)\",\"reason\":\"missing-sound\"}"
        }
        let durationMs = Self.durationMs(from: response.text)

        // The Mac owns the sound→effect map: every press is reported by bare
        // filename and the Mac decides whether a visual is paired with it.
        router.dispatch(startPath(for: tile.asset))
        setPlaying(tile)

        generation += 1
        let gen = generation
        let asset = tile.asset
        schedule(Double(durationMs + 100) / 1000) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.setPlaying(nil)
            self.router.dispatch(self.stopPath(for: asset))
        }

        return "{\"ok\":true,\"n\":\(tile.n),\"asset\":\"\(tile.asset)\","
            + "\"action\":\"play\",\"durationMs\":\(durationMs)}"
    }

    /// Silence everything, exactly as the tablet's `stopAllLocalAndMac` does:
    /// the siren's overlay first (it is toggled, so `stop-all` alone leaves it
    /// up), then the blanket stop.
    func stopAll() {
        generation += 1
        if playing?.asset == Self.sirenAsset {
            router.dispatch("/alarm/stop")
        }
        router.dispatch("/effect/stop-all")
        setPlaying(nil)
    }

    private func startPath(for asset: String) -> String {
        asset == Self.sirenAsset ? "/alarm/start" : "/sound/pressed/\(asset)"
    }

    private func stopPath(for asset: String) -> String {
        asset == Self.sirenAsset ? "/alarm/stop" : "/sound/stopped/\(asset)"
    }

    private func setPlaying(_ tile: Tile?) {
        guard playing != tile else { return }
        playing = tile
        onPlayingChanged?(tile)
    }

    /// `{"ok":true,"durationMs":8600}` → 8600. Hand-rolled rather than
    /// `JSONSerialization` because the body is this app's own one-line JSON and
    /// a missing duration must degrade to "stop it soon", not to a thrown error
    /// in the middle of a press.
    static func durationMs(from json: String) -> Int {
        guard let range = json.range(of: "\"durationMs\":") else { return 0 }
        let digits = json[range.upperBound...].prefix { $0.isNumber || $0 == "-" }
        return Int(digits) ?? 0
    }
}
