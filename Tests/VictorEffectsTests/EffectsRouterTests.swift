import XCTest
@testable import VictorEffects

/// The route table is the app's whole public contract — another app proxies to
/// it by path, so a renamed route is a silent outage over there. Every case
/// below is a promise to a caller that does not live in this repo.
final class EffectsRouterTests: XCTestCase {
    private func route(_ path: String) -> EffectsRouter.Route {
        EffectsRouter.route(forPath: path)
    }

    func testParsePathExtractsPathFromHttpRequestLine() {
        let request = "GET /effect/snow HTTP/1.1\r\nHost: localhost\r\n\r\n"
        XCTAssertEqual(EffectsRouter.parsePath(request), "/effect/snow")
    }

    func testRouteMapsEffectEndpointWithNestedName() {
        XCTAssertEqual(route("/effect/pulse/stop"), .effect("pulse/stop"))
    }

    func testRoutePhoenixTestAndEffectEndpoints() {
        // Both the headless test hook and the generic /effect/ path dispatch the
        // phoenix overlay through the same effect name.
        XCTAssertEqual(route("/test/phoenix"), .effect("phoenix"))
        XCTAssertEqual(route("/effect/phoenix"), .effect("phoenix"))
    }

    func testRouteIrisTestAndEffectEndpoints() {
        XCTAssertEqual(route("/test/iris"), .effect("iris"))
        XCTAssertEqual(route("/effect/iris"), .effect("iris"))
    }

    func testRouteCrtShutdownTestAndEffectEndpoints() {
        // 📺 The tail of game-over, addressable alone so it can be rehearsed
        // without the picture and the 1.6 s clip in front of it.
        XCTAssertEqual(route("/test/crt-shutdown"), .effect("crt-shutdown"))
        XCTAssertEqual(route("/effect/crt-shutdown"), .effect("crt-shutdown"))
    }

    func testRouteSketchArrowTestAndEffectEndpoints() {
        // 🔁 Tile #71's replay arrow. One-shot, so no /stop twin: it ends itself
        // at the clip's length.
        XCTAssertEqual(route("/test/sketch-arrow"), .effect("sketch-arrow"))
        XCTAssertEqual(route("/effect/sketch-arrow"), .effect("sketch-arrow"))
    }

    func testRouteElephantTestAndEffectEndpoints() {
        // 🐘 is a toggle, so the alias has a /stop twin.
        XCTAssertEqual(route("/test/elephant"), .effect("elephant"))
        XCTAssertEqual(route("/test/elephant/stop"), .effect("elephant/stop"))
        XCTAssertEqual(route("/effect/elephant"), .effect("elephant"))
    }

    func testWhipRoutesKeepTheirHistoricTestNames() {
        // /test/whip and /test/whip/crack predate this app; the other app
        // proxies those exact paths through, so they must not be renamed to
        // something tidier.
        XCTAssertEqual(route("/test/whip"), .effect("whip"))
        XCTAssertEqual(route("/test/whip/crack"), .effect("whip/crack"))
        XCTAssertEqual(route("/effect/whip"), .effect("whip"))
        XCTAssertEqual(route("/effect/whip/crack"), .effect("whip/crack"))
    }

    func testRouteMapsSoundPressedAndStopped() {
        XCTAssertEqual(route("/sound/pressed/40_joker.mp3"), .soundPressed("40_joker.mp3"))
        XCTAssertEqual(route("/sound/stopped/37_rainbow.mp3"), .soundStopped("37_rainbow.mp3"))
    }

    func testSoundStopExactStillDistinctFromStopped() {
        // "/sound/stop" preempts playback; it must NOT be parsed as a
        // "/sound/stopped/<file>" report with an empty filename.
        XCTAssertEqual(route("/sound/stop"), .soundStop)
    }

    func testSoundPlayCarriesTheVolumeQuery() {
        XCTAssertEqual(route("/sound/play/50_gong.mp3"), .soundPlay("50_gong.mp3", nil))
        XCTAssertEqual(route("/sound/play/50_gong.mp3?vol=60"), .soundPlay("50_gong.mp3", 60))
    }

    func testSoundEffectMapDrivesBloodAndKeepsSirenSpecial() {
        XCTAssertEqual(SoundEffectMap.pressEffect(for: "40_joker.mp3"), "blood-drip")
        XCTAssertEqual(SoundEffectMap.pressEffect(for: "03_explosion.mp3"), "explosion")
        XCTAssertEqual(SoundEffectMap.stopEffect(for: "37_rainbow.mp3"), "rainbow/stop")
        // The siren is the alarm overlay's, driven by /alarm/start — not mapped.
        XCTAssertNil(SoundEffectMap.pressEffect(for: "02_siren.mp3"))
        XCTAssertNil(SoundEffectMap.pressEffect(for: "99_nonexistent.mp3"))
    }

    func testProgressBarParsesSecondsAndRider() {
        XCTAssertEqual(route("/effect/progress-bar/5"), .progressBar(seconds: 5, rider: nil))
        XCTAssertEqual(route("/effect/progress-bar/300?rider=%F0%9F%8F%81"),
                       .progressBar(seconds: 300, rider: "🏁"))
        XCTAssertEqual(route("/effect/progress-bar/stop"), .progressBarStop)
        // A non-numeric duration is a typo, not an effect called "abc".
        XCTAssertEqual(route("/effect/progress-bar/abc"), .unknown)
        XCTAssertEqual(route("/effect/progress-bar/0"), .unknown)
    }

    func testEmojiRouteDefaultsAndClamps() {
        XCTAssertEqual(route("/effect/emoji"), .emoji(e: "❤️", count: 1, glow: nil))
        XCTAssertEqual(route("/effect/emoji?e=%E2%98%95&count=3&glow=%F0%9F%92%9B"),
                       .emoji(e: "☕", count: 3, glow: "💛"))
        // The count comes from a remote caller; 10 000 hearts is a hang, not a
        // request, so it is clamped rather than trusted.
        XCTAssertEqual(route("/effect/emoji?count=10000"), .emoji(e: "❤️", count: 50, glow: nil))
        XCTAssertEqual(route("/effect/emoji?count=-4"), .emoji(e: "❤️", count: 1, glow: nil))
    }

    func testTrainingEndAndFocusPlaylistAreNotOursButStillParse() {
        // They belong to the other app, which keeps them local and never proxies
        // them here. Reaching this app they are just unknown effect names, which
        // the engine logs — no route-level special case to keep in sync.
        XCTAssertEqual(route("/effect/training-end"), .effect("training-end"))
    }

    func testTilesRoutes() {
        XCTAssertEqual(route("/tiles"), .tiles)
        XCTAssertEqual(route("/tiles/tiles/sfx_01_baby.jpg"), .tileImage("tiles/sfx_01_baby.jpg"))
        XCTAssertEqual(route("/tiles/"), .unknown)
    }

    func testDiagnosticRoutes() {
        XCTAssertEqual(route("/state"), .state)
        XCTAssertEqual(route("/config/reload"), .configReload)
        XCTAssertEqual(route("/ping"), .ping)
        XCTAssertEqual(route("/sounds/manifest"), .soundsManifest)
        XCTAssertEqual(route("/bt-compensation"), .btCompensationGet)
        XCTAssertEqual(route("/bt-compensation/800"), .btCompensationSet(800))
        XCTAssertEqual(route("/alarm/start"), .alarmStart)
        XCTAssertEqual(route("/alarm/stop"), .alarmStop)
        XCTAssertEqual(route("/sound/volume/60"), .soundVolume(60))
    }

    func testPanelHooks() {
        XCTAssertEqual(route("/test/thumbnail-panel"), .panelShow)
        XCTAssertEqual(route("/test/thumbnail-panel/hide"), .panelHide)
        XCTAssertEqual(route("/test/thumbnail-panel/press/23"), .panelPress(23))
    }

    func testPercentEncodingIsDecodedOnceHere() {
        // The proxy in front of this app forwards the path and query verbatim,
        // already encoded, and re-encodes nothing. Decoding is this side's job,
        // and doing it twice would turn a literal "%25" in a filename into "%".
        XCTAssertEqual(route("/sound/play/50%5Fgong.mp3"), .soundPlay("50_gong.mp3", nil))
        XCTAssertEqual(route("/effect/emoji?e=%E2%98%95"), .emoji(e: "☕", count: 1, glow: nil))
        XCTAssertEqual(route("/effect/progress-bar/300?rider=%F0%9F%8F%81"),
                       .progressBar(seconds: 300, rider: "🏁"))
    }

    func testUnknownPathsAreUnknown() {
        XCTAssertEqual(route("/test/unknown"), .unknown)
        XCTAssertEqual(route("/videos"), .unknown)       // stayed with the other app
        XCTAssertEqual(route("/"), .unknown)
    }
}
