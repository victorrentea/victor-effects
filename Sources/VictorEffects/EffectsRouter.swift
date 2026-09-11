import Foundation

/// What a route answers with. A `Data` body rather than a `String` because one
/// route (`/tiles/<image>`) returns JPEG bytes.
struct EffectsResponse: Equatable {
    var status: Int = 200
    var contentType: String = "text/plain; charset=utf-8"
    var body: Data = Data("ok".utf8)

    var text: String { String(decoding: body, as: UTF8.self) }

    static func ok(_ s: String = "ok") -> EffectsResponse {
        EffectsResponse(status: 200, contentType: "text/plain; charset=utf-8", body: Data(s.utf8))
    }
    static func json(_ s: String, status: Int = 200) -> EffectsResponse {
        EffectsResponse(status: status, contentType: "application/json", body: Data(s.utf8))
    }
    static func binary(_ data: Data, contentType: String) -> EffectsResponse {
        EffectsResponse(status: 200, contentType: contentType, body: data)
    }
    static let notFound = EffectsResponse(status: 404, contentType: "text/plain; charset=utf-8",
                                          body: Data("not found".utf8))
}

/// The whole HTTP surface of the app, as a value.
///
/// Parsing is `static` and pure so a test can assert the table without a socket,
/// and `dispatch` is the single place a route turns into an action — the HTTP
/// listener wraps it in `DispatchQueue.main.sync`, an in-process caller (the
/// thumbnail panel) calls it directly on the main thread. One switch, two
/// callers, no second copy of "what does /sound/play mean" to drift.
final class EffectsRouter {
    enum Route: Equatable {
        case ping
        case soundsManifest
        /// Filename + optional volume percent (0–100) from `?vol=`.
        case soundPlay(String, Int?)
        case soundVolume(Int)
        case soundStop
        /// A client reports a sound started; the Mac owns the sound→effect map.
        case soundPressed(String)
        case soundStopped(String)
        case btCompensationGet
        case btCompensationSet(Int)
        case alarmStart
        case alarmStop
        /// Everything under `/effect/`, nested names included (`pulse/stop`).
        case effect(String)
        /// `/effect/emoji?e=❤️&count=3&glow=💛`
        case emoji(e: String, count: Int, glow: String?)
        /// `/effect/progress-bar/<seconds>?rider=🏁`
        case progressBar(seconds: Int, rider: String?)
        case progressBarStop
        case tiles
        case tileImage(String)
        /// Hook points for the thumbnail panel (WI-4). Parsed here so the route
        /// table is complete and testable before the panel exists.
        case panelShow
        case panelHide
        case panelPress(Int)
        case state
        case configReload
        case unknown
    }

    static func parsePath(_ request: String) -> String {
        let parts = request.split(separator: " ", maxSplits: 2)
        return parts.count > 1 ? String(parts[1]) : "/"
    }

    private static func parsePathAndQuery(_ raw: String) -> (String, [URLQueryItem]) {
        guard let comps = URLComponents(string: "http://x" + raw) else { return (raw, []) }
        return (comps.path, comps.queryItems ?? [])
    }

    /// `/test/<name>` aliases kept from the app this was extracted from, so
    /// every script, doc and muscle-memory curl keeps working — and so the
    /// addons proxy needs no name mapping at all.
    private static let testAliases: [String: String] = [
        "/test/sonar": "sonar",
        "/test/beethoven": "beethoven",
        "/test/phoenix": "phoenix",
        "/test/money": "money",
        "/test/coffee": "coffee",
        "/test/coffee/pop": "coffee/pop",
        "/test/iris": "iris",
        "/test/crt-shutdown": "crt-shutdown",
        "/test/snow": "snow",
        "/test/snow/stop": "snow/stop",
        "/test/elephant": "elephant",
        "/test/elephant/stop": "elephant/stop",
        "/test/claude-peek": "claude-peek",
        "/test/claude-peek/stop": "claude-peek/stop",
        "/test/minion": "minion",
        "/test/counter-strike": "counter-strike",
        "/test/chainsaw": "chainsaw",
        "/test/chainsaw/stop": "chainsaw/stop",
        "/test/fire": "fire",
        "/test/fire/stop": "fire/stop",
        "/test/microwave": "microwave",
        "/test/sketch-arrow": "sketch-arrow",
        "/test/whip": "whip",
        "/test/whip/crack": "whip/crack",
    ]

    static func route(forPath path: String) -> Route {
        let (pathOnly, query) = parsePathAndQuery(path)
        func q(_ name: String) -> String? { query.first { $0.name == name }?.value }

        switch pathOnly {
        case "/ping":               return .ping
        case "/sounds/manifest":    return .soundsManifest
        case "/sound/stop":         return .soundStop
        case "/bt-compensation":    return .btCompensationGet
        case "/alarm/start":        return .alarmStart
        case "/alarm/stop":         return .alarmStop
        case "/tiles":              return .tiles
        case "/state":              return .state
        case "/config/reload":      return .configReload
        case "/test/thumbnail-panel":       return .panelShow
        case "/test/thumbnail-panel/hide":  return .panelHide
        case "/effect/progress-bar/stop":   return .progressBarStop
        case "/effect/emoji":
            let count = Int(q("count") ?? "1") ?? 1
            return .emoji(e: q("e") ?? "❤️", count: max(1, min(count, 50)), glow: q("glow"))
        default:
            break
        }

        if let name = testAliases[pathOnly] { return .effect(name) }

        if pathOnly.hasPrefix("/effect/progress-bar/") {
            let arg = String(pathOnly.dropFirst("/effect/progress-bar/".count))
            if let secs = Int(arg), secs > 0 { return .progressBar(seconds: secs, rider: q("rider")) }
            return .unknown
        }
        if pathOnly.hasPrefix("/effect/") {
            let name = String(pathOnly.dropFirst("/effect/".count))
            return name.isEmpty ? .unknown : .effect(name)
        }
        if pathOnly.hasPrefix("/sound/play/") {
            let name = String(pathOnly.dropFirst("/sound/play/".count))
            let vol = q("vol").flatMap { Int($0) }
            if !name.isEmpty { return .soundPlay(name, vol) }
        }
        if pathOnly.hasPrefix("/sound/pressed/") {
            let name = String(pathOnly.dropFirst("/sound/pressed/".count))
            if !name.isEmpty { return .soundPressed(name) }
        }
        if pathOnly.hasPrefix("/sound/stopped/") {
            let name = String(pathOnly.dropFirst("/sound/stopped/".count))
            if !name.isEmpty { return .soundStopped(name) }
        }
        if pathOnly.hasPrefix("/sound/volume/") {
            if let pct = Int(pathOnly.dropFirst("/sound/volume/".count)) { return .soundVolume(pct) }
        }
        if pathOnly.hasPrefix("/bt-compensation/") {
            if let ms = Int(pathOnly.dropFirst("/bt-compensation/".count)) { return .btCompensationSet(ms) }
        }
        if pathOnly.hasPrefix("/test/thumbnail-panel/press/") {
            if let n = Int(pathOnly.dropFirst("/test/thumbnail-panel/press/".count)) { return .panelPress(n) }
        }
        if pathOnly.hasPrefix("/tiles/") {
            let rel = String(pathOnly.dropFirst("/tiles/".count))
            if !rel.isEmpty { return .tileImage(rel) }
        }
        return .unknown
    }

    // MARK: - Dispatch

    private let engine: EffectsEngine

    /// Filled in by the thumbnail panel (WI-4). Left as optional closures so the
    /// four panel routes already answer — with 503 — instead of not existing.
    var onPanelShow: (() -> String)?
    var onPanelHide: (() -> Void)?
    var onPanelPress: ((Int) -> String)?
    var panelMonitorActive: () -> Bool = { false }
    var panelVisible: () -> Bool = { false }

    init(engine: EffectsEngine) {
        self.engine = engine
    }

    /// Run one request. **Main thread only** — every handler touches AppKit.
    @discardableResult
    func dispatch(_ pathAndQuery: String) -> EffectsResponse {
        assert(Thread.isMainThread, "EffectsRouter.dispatch must run on the main thread")
        return run(Self.route(forPath: pathAndQuery))
    }

    private func run(_ route: Route) -> EffectsResponse {
        switch route {
        case .ping:
            return .json(engine.pingJSON(panelMonitor: panelMonitorActive()))

        case .soundsManifest:
            guard SoundManager.sharedSoundsDir() != nil else {
                return .json("{\"error\":\"soundsDir unreadable\"}", status: 503)
            }
            return .json(SoundsManifest.manifestJSON)

        case .soundPlay(let name, let volumePct):
            guard let json = engine.playSound(name, volumePct: volumePct) else {
                return .json("{\"ok\":false,\"reason\":\"unknown-sound\"}", status: 404)
            }
            return .json(json)

        case .soundVolume(let pct):
            SoundManager.shared.setTabletVolume(Float(pct) / 100)
            return .ok()

        case .soundStop:
            SoundManager.shared.stopTabletSound()
            return .ok()

        case .soundPressed(let file):
            guard let effect = SoundEffectMap.pressEffect(for: file) else { return .ok("no-effect") }
            engine.runEffect(effect)
            return .ok()

        case .soundStopped(let file):
            guard let effect = SoundEffectMap.stopEffect(for: file) else { return .ok("no-effect") }
            engine.runEffect(effect)
            return .ok()

        case .btCompensationGet:
            let ms = Int((SoundTimingConfig.shared.effectiveBluetoothCompensationSeconds * 1000).rounded())
            let maxMs = Int((SoundTimingConfig.maxCompensationSeconds * 1000).rounded())
            return .json("{\"ms\":\(ms),\"maxMs\":\(maxMs)}")

        case .btCompensationSet(let ms):
            SoundTimingConfig.shared.setBluetoothCompensation(seconds: Double(ms) / 1000.0)
            let applied = Int((SoundTimingConfig.shared.effectiveBluetoothCompensationSeconds * 1000).rounded())
            return .json("{\"ok\":true,\"ms\":\(applied)}")

        case .alarmStart:
            engine.startAlarm()
            return .ok()

        case .alarmStop:
            engine.stopAlarm()
            return .ok()

        case .effect(let name):
            engine.runEffect(name)
            return .ok()

        case .emoji(let e, let count, let glow):
            engine.spawnEmoji(e, count: count, glow: glow)
            return .ok()

        case .progressBar(let seconds, let rider):
            engine.startProgressBar(seconds: seconds, rider: rider)
            return .ok()

        case .progressBarStop:
            engine.cancelProgressBar()
            return .ok()

        case .tiles:
            guard let json = TilesManifest.json else {
                return .json("{\"error\":\"no tiles.json in \(EffectsConfig.shared.soundsDir.path)\"}", status: 404)
            }
            return .json(json)

        case .tileImage(let rel):
            guard let img = TilesManifest.image(relativePath: rel) else { return .notFound }
            return .binary(img.data, contentType: img.contentType)

        case .panelShow:
            guard let show = onPanelShow else { return .json("{\"ok\":false,\"reason\":\"no-panel\"}", status: 503) }
            return .json(show())

        case .panelHide:
            guard let hide = onPanelHide else { return .json("{\"ok\":false,\"reason\":\"no-panel\"}", status: 503) }
            hide()
            return .ok()

        case .panelPress(let n):
            guard let press = onPanelPress else { return .json("{\"ok\":false,\"reason\":\"no-panel\"}", status: 503) }
            return .json(press(n))

        case .state:
            return .json(engine.stateJSON(panelMonitor: panelMonitorActive(),
                                          panelVisible: panelVisible()))

        case .configReload:
            EffectsConfig.shared.reload()
            SoundManager.resetSoundsDirWarning()
            SoundsManifest.invalidate()
            TilesManifest.invalidate()
            SoundTimingConfig.reload()
            return .json("{\"ok\":true,\"config\":\(EffectsConfig.shared.asJSON)}")

        case .unknown:
            return .notFound
        }
    }
}
