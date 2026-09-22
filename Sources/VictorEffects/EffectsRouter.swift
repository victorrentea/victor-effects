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
        /// `GET /usage` — the press counts behind the tablet's green dots.
        case usage
        /// `GET /usage/import?counts=<asset>:<n>,…` — a client's historical
        /// totals, max-merged in. One-shot, at the tablet's first sync.
        case usageImport([String: Int])
        case usageReset
        /// `GET /effects/assets` (and its older spelling `GET /sound/effects`)
        /// — which sounds also fire a desktop visual.
        case effectsAssets
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
        case panelShow(PanelPage)
        case panelHide
        case panelPress(Int, PanelPage)
    /// `/test/thumbnail-panel/hover` — what the hover mark actually is right
    /// now, optionally after resolving it at an explicit point.
    case panelHover(NSPoint?)
        /// `/test/thumbnail-panel/cursor` — why the pointer is the shape it is.
        case panelCursor
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
        "/test/coffee/storm": "coffee/storm",
        "/test/iris": "iris",
        "/test/crt-shutdown": "crt-shutdown",
        "/test/snow": "snow",
        "/test/snow/stop": "snow/stop",
        "/test/storm": "storm",
        "/test/storm/stop": "storm/stop",
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
        "/test/universal-minions": "universal-minions",
        "/test/universal-minions/preview": "universal-minions/preview",
        "/test/sketch-arrow": "sketch-arrow",
        "/test/whip": "whip",
        "/test/whip/crack": "whip/crack",
    ]

    /// `?page=videos` selects the panel's second page; anything else — absent,
    /// misspelt, `effects` — is the soundboard. Lenient on purpose: these are
    /// hooks typed into a shell, and a typo answering "no such route" instead of
    /// showing the board is not a better error.
    static func page(_ raw: String?) -> PanelPage {
        PanelPage(rawValue: raw ?? "") ?? .effects
    }

    static func route(forPath path: String) -> Route {
        let (pathOnly, query) = parsePathAndQuery(path)
        func q(_ name: String) -> String? { query.first { $0.name == name }?.value }

        switch pathOnly {
        case "/ping":               return .ping
        case "/sounds/manifest":    return .soundsManifest
        case "/sound/effects":      return .effectsAssets
        case "/effects/assets":     return .effectsAssets
        case "/sound/stop":         return .soundStop
        case "/bt-compensation":    return .btCompensationGet
        case "/alarm/start":        return .alarmStart
        case "/alarm/stop":         return .alarmStop
        case "/tiles":              return .tiles
        case "/usage":              return .usage
        case "/usage/reset":        return .usageReset
        case "/usage/import":
            // "asset:count,asset:count" — a GET because that is the only verb
            // the tablet's link speaks, and the payload is ~100 short pairs.
            var parsed: [String: Int] = [:]
            for pair in (q("counts") ?? "").split(separator: ",") {
                let halves = pair.split(separator: ":")
                if halves.count == 2, let n = Int(halves[1]), n > 0 {
                    parsed[String(halves[0])] = n
                }
            }
            return parsed.isEmpty ? .unknown : .usageImport(parsed)
        case "/state":              return .state
        case "/config/reload":      return .configReload
        case "/test/thumbnail-panel":       return .panelShow(page(q("page")))
        case "/test/thumbnail-panel/hide":  return .panelHide
        case "/test/thumbnail-panel/cursor":  return .panelCursor
        case "/test/thumbnail-panel/hover":
            if let xs = q("x"), let ys = q("y"), let x = Double(xs), let y = Double(ys) {
                return .panelHover(NSPoint(x: x, y: y))
            }
            return .panelHover(nil)
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
            if let n = Int(pathOnly.dropFirst("/test/thumbnail-panel/press/".count)) {
                return .panelPress(n, page(q("page")))
            }
        }
        // The production spelling of the press above. `onPanelPress` is a
        // historical name — the hook has never consulted the panel, and the
        // training daemon's secret FX link presses tiles with no panel in
        // sight. Same case, so there is one handler and nothing to drift.
        if pathOnly.hasPrefix("/press/") {
            if let n = Int(pathOnly.dropFirst("/press/".count)) {
                return .panelPress(n, .effects)
            }
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
    var onPanelShow: ((PanelPage) -> String)?
    var onPanelHide: (() -> Void)?
    var onPanelPress: ((Int, PanelPage) -> String)?
    var onPanelHover: ((NSPoint?) -> String)?
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
            // Counted BEFORE the effect lookup: a tile with no visual is still a
            // tile that was pressed, and the dots measure use, not spectacle.
            // This is also the one place both surfaces meet — the tablet's HTTP
            // press and the panel's in-process dispatch land here alike.
            UsageCounts.record(file)
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
            // The siren is the one tile that reports through /alarm/* instead of
            // /sound/pressed, so without this line it would be the one tile
            // whose dots never move.
            UsageCounts.record(SoundboardPress.sirenAsset)
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
            guard let json = TilesManifest.effectsJSON else {
                return .json("{\"error\":\"no tiles.json in \(EffectsConfig.shared.soundsDir.path)\"}", status: 404)
            }
            return .json(json)

        case .tileImage(let rel):
            guard let img = TilesManifest.image(relativePath: rel) else { return .notFound }
            return .binary(img.data, contentType: img.contentType)

        case .panelShow(let page):
            guard let show = onPanelShow else { return .json("{\"ok\":false,\"reason\":\"no-panel\"}", status: 503) }
            return .json(show(page))

        case .panelHide:
            guard let hide = onPanelHide else { return .json("{\"ok\":false,\"reason\":\"no-panel\"}", status: 503) }
            hide()
            return .ok()

        case .panelPress(let n, let page):
            guard let press = onPanelPress else { return .json("{\"ok\":false,\"reason\":\"no-panel\"}", status: 503) }
            return .json(press(n, page))

        case .panelCursor:
            return .json(PanelCursor.diagnosticJSON())

        case .panelHover(let point):
            guard let hover = onPanelHover else { return .json("{\"ok\":false,\"reason\":\"no-panel\"}", status: 503) }
            return .json(hover(point))

        case .effectsAssets:
            // Sorted so the body is stable: a client caches it and only repaints
            // when the list actually changes. The tablet reads the ⭐ off /tiles
            // now; this route stays as the flat, greppable answer to "which
            // sounds are effect sounds" for a curl and for the drift tests.
            return .json(EffectsCatalog.assetsJSON)

        case .usage:
            return .json(UsageCounts.json)

        case .usageImport(let counts):
            UsageCounts.merge(counts)
            return .json(UsageCounts.json)

        case .usageReset:
            UsageCounts.reset()
            return .json(UsageCounts.json)

        case .state:
            return .json(engine.stateJSON(panelMonitor: panelMonitorActive(),
                                          panelVisible: panelVisible()))

        case .configReload:
            EffectsConfig.shared.reload()
            SoundManager.resetSoundsDirWarning()
            SoundsManifest.invalidate()
            TilesManifest.invalidate()
            // The *pictures* too, which the retired `Reload tiles.json` menu row
            // used to be the only way to drop: the caches are keyed by path, so
            // a thumbnail replaced in place under the same name would otherwise
            // survive every reload for the life of the process.
            TileImageCache.shared.clear()
            VideosManifest.invalidate()
            VideoThumbCache.shared.clear()
            SoundTimingConfig.reload()
            return .json("{\"ok\":true,\"config\":\(EffectsConfig.shared.asJSON)}")

        case .unknown:
            return .notFound
        }
    }
}
