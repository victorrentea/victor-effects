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

    /// The tiles whose sounds are running, oldest first, for the pulsing red
    /// border. Several at once since 2026-10-29: pressing another tile no
    /// longer stops the one running — only pressing THAT tile again does.
    private(set) var playingTiles: [Tile] = []
    /// The most recent of them.
    var playing: Tile? { playingTiles.last }
    var onPlayingChanged: (([Tile]) -> Void)?

    /// Completion timers are not cancelled, they are *outvoted*: each start of
    /// a tile records a fresh number under its asset, and a late completion
    /// that finds another number (a restart, a stop) does nothing.
    private var generations: [String: Int] = [:]
    private var counter = 0

    init(router: SoundboardDispatcher) {
        self.router = router
    }

    /// Press one tile. Returns the JSON body the `/test/…/press/<n>` hook
    /// answers with, which doubles as a description of what happened.
    @discardableResult
    func press(_ tile: Tile) -> String {
        // Re-pressing a tile that is playing stops IT (and only it) — unless the
        // tile is restartable (#53 money), which falls through to the start path
        // and so replays from the top, stacking a fresh round of the effect.
        if playingTiles.contains(where: { $0.asset == tile.asset }), !tile.restartable {
            stop(tile)
            return "{\"ok\":true,\"n\":\(tile.n),\"asset\":\"\(tile.asset)\",\"action\":\"stop\"}"
        }

        // No stop-all: whatever else is running keeps running.
        let response = router.dispatch("/sound/play/\(tile.asset)?vol=\(volumePct())")
        guard response.status == 200 else {
            return "{\"ok\":false,\"n\":\(tile.n),\"asset\":\"\(tile.asset)\",\"reason\":\"missing-sound\"}"
        }
        let durationMs = Self.durationMs(from: response.text)

        // The Mac owns the sound→effect map: every press is reported by bare
        // filename and the Mac decides whether a visual is paired with it.
        router.dispatch(startPath(for: tile.asset))
        setPlaying(playingTiles.filter { $0.asset != tile.asset } + [tile])

        counter += 1
        let gen = counter
        let asset = tile.asset
        generations[asset] = gen
        schedule(Double(durationMs + 100) / 1000) { [weak self] in
            guard let self, self.generations[asset] == gen else { return }
            self.generations[asset] = nil
            self.setPlaying(self.playingTiles.filter { $0.asset != asset })
            self.router.dispatch(self.stopPath(for: asset))
        }

        return "{\"ok\":true,\"n\":\(tile.n),\"asset\":\"\(tile.asset)\","
            + "\"action\":\"play\",\"durationMs\":\(durationMs)}"
    }

    /// Stop one running tile: its clip and its desktop effect
    /// (`/sound/stop/<asset>`); the siren's toggled overlay goes down first.
    func stop(_ tile: Tile) {
        generations[tile.asset] = nil
        if tile.asset == Self.sirenAsset { router.dispatch("/alarm/stop") }
        router.dispatch("/sound/stop/\(tile.asset)")
        setPlaying(playingTiles.filter { $0.asset != tile.asset })
    }

    /// Silence everything, exactly as the tablet's `stopAllLocalAndMac` does:
    /// the siren's overlay first (it is toggled, so `stop-all` alone leaves it
    /// up), then the blanket stop.
    func stopAll() {
        generations.removeAll()
        if playingTiles.contains(where: { $0.asset == Self.sirenAsset }) {
            router.dispatch("/alarm/stop")
        }
        router.dispatch("/effect/stop-all")
        setPlaying([])
    }

    private func startPath(for asset: String) -> String {
        asset == Self.sirenAsset ? "/alarm/start" : "/sound/pressed/\(asset)"
    }

    private func stopPath(for asset: String) -> String {
        asset == Self.sirenAsset ? "/alarm/stop" : "/sound/stopped/\(asset)"
    }

    private func setPlaying(_ tiles: [Tile]) {
        guard playingTiles != tiles else { return }
        playingTiles = tiles
        onPlayingChanged?(tiles)
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
