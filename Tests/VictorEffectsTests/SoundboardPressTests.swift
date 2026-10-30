import XCTest
@testable import VictorEffects

/// A router that records instead of acting. What matters about a press is the
/// sequence of routes it produces — the tablet in the room produces the same
/// one, and the two boards must not disagree about what a tile does.
private final class RecordingRouter: SoundboardDispatcher {
    var paths: [String] = []
    var playStatus = 200
    var durationMs = 1000

    @discardableResult
    func dispatch(_ pathAndQuery: String) -> EffectsResponse {
        paths.append(pathAndQuery)
        if pathAndQuery.hasPrefix("/sound/play/") {
            guard playStatus == 200 else {
                return .json("{\"ok\":false,\"reason\":\"unknown-sound\"}", status: playStatus)
            }
            return .json("{\"ok\":true,\"durationMs\":\(durationMs)}")
        }
        return .ok()
    }
}

final class SoundboardPressTests: XCTestCase {
    private var router: RecordingRouter!
    private var press: SoundboardPress!
    /// The completion the press scheduled, held rather than run: "what happens
    /// when the sound ends" is then an assertion, not a wait.
    private var pending: (delay: TimeInterval, work: () -> Void)?

    private let joker = Tile(n: 40, asset: "40_joker.mp3", image: "tiles/sfx_40_joker.jpg")
    private let money = Tile(n: 53, asset: "53_rain.mp3", image: "tiles/sfx_53_money.png", restartable: true)
    private let siren = Tile(n: 2, asset: "02_siren.mp3", image: "tiles/sfx_02_siren.jpg")

    override func setUp() {
        super.setUp()
        router = RecordingRouter()
        press = SoundboardPress(router: router)
        press.volumePct = { 70 }
        press.schedule = { [weak self] delay, work in self?.pending = (delay, work) }
    }

    private func fireCompletion() {
        let work = pending?.work
        pending = nil
        work?()
    }

    func testAPressPlaysThenFiresThePairedEffectWithoutStoppingAnything() {
        press.press(joker)

        XCTAssertEqual(router.paths, [
            "/sound/play/40_joker.mp3?vol=70",
            "/sound/pressed/40_joker.mp3",
        ])
        XCTAssertEqual(press.playing, joker)
    }

    /// 2026-10-29: two tiles run at once — another press leaves the first alone.
    func testAnotherTileRunsAlongsideTheFirst() {
        press.press(joker)
        router.paths.removeAll()

        press.press(siren)

        XCTAssertFalse(router.paths.contains("/effect/stop-all"), "\(router.paths)")
        XCTAssertFalse(router.paths.contains { $0.hasPrefix("/sound/stop/") }, "\(router.paths)")
        XCTAssertEqual(press.playingTiles, [joker, siren])
    }

    func testRePressingANonRestartableTileStopsOnlyIt() {
        press.press(joker)
        press.press(siren)
        router.paths.removeAll()

        press.press(joker)

        XCTAssertEqual(router.paths, ["/sound/stop/40_joker.mp3"])
        XCTAssertEqual(press.playingTiles, [siren])
    }

    /// 2026-10-30: a cell's two layers never sound together — pressing the
    /// cell on the other layer stops the one running there, starts nothing.
    func testTheTileUnderARunningOneStopsItInsteadOfStarting() {
        let starWars = Tile(n: 55, asset: "55_star_wars.mp3", image: "tiles/sfx_55.jpg")
        let tsunami = Tile(n: 55, asset: "55b_tsunami.mp3", image: "tiles/sfx_55b.jpg")
        press.press(joker)
        press.press(starWars)
        router.paths.removeAll()

        press.press(tsunami)

        XCTAssertEqual(router.paths, ["/sound/stop/55_star_wars.mp3"])
        XCTAssertEqual(press.playingTiles, [joker])
    }

    func testRePressingARestartableTileReplaysIt() {
        press.press(money)
        router.paths.removeAll()

        press.press(money)

        XCTAssertEqual(router.paths, [
            "/sound/play/53_rain.mp3?vol=70",
            "/sound/pressed/53_rain.mp3",
        ])
        XCTAssertEqual(press.playingTiles, [money])
    }

    func testTheSirenDrivesTheAlarmOverlayInsteadOfAPairedEffect() {
        press.press(siren)

        XCTAssertEqual(router.paths, [
            "/sound/play/02_siren.mp3?vol=70",
            "/alarm/start",
        ])
    }

    func testStoppingASirenTakesTheAlarmOverlayDownFirst() {
        // Its own stop leaves the alarm up: it is a toggled overlay, not a
        // self-terminating effect. Hence the extra call, and hence its order.
        press.press(siren)
        router.paths.removeAll()

        press.press(siren)

        XCTAssertEqual(router.paths, ["/alarm/stop", "/sound/stop/02_siren.mp3"])
    }

    func testCompletionReportsTheStopByFilename() {
        press.press(joker)
        router.paths.removeAll()
        XCTAssertEqual(pending?.delay ?? 0, 1.1, accuracy: 0.0001)

        fireCompletion()

        XCTAssertEqual(router.paths, ["/sound/stopped/40_joker.mp3"])
        XCTAssertNil(press.playing)
    }

    func testTheSirensCompletionStopsTheAlarm() {
        press.press(siren)
        router.paths.removeAll()

        fireCompletion()

        XCTAssertEqual(router.paths, ["/alarm/stop"])
    }

    func testAStaleCompletionDoesNothing() {
        press.press(money)
        let stale = pending
        press.press(money)      // a restart outvotes the pending completion
        router.paths.removeAll()

        stale?.work()

        XCTAssertEqual(router.paths, [])
        XCTAssertEqual(press.playing, money, "the running tile must survive an old timer")
    }

    func testOneTilesCompletionLeavesTheOtherPlaying() {
        press.press(joker)
        let jokerDone = pending
        press.press(siren)
        router.paths.removeAll()

        jokerDone?.work()

        XCTAssertEqual(router.paths, ["/sound/stopped/40_joker.mp3"])
        XCTAssertEqual(press.playingTiles, [siren])
    }

    func testAMissingSoundLeavesNothingPlaying() {
        router.playStatus = 404

        let json = press.press(joker)

        XCTAssertEqual(router.paths, ["/sound/play/40_joker.mp3?vol=70"])
        XCTAssertNil(press.playing)
        XCTAssertTrue(json.contains("missing-sound"), json)
        XCTAssertNil(pending, "no completion may be scheduled for a sound that never started")
    }

    func testTheVolumeFollowsTheCurrentTabletVolume() {
        press.volumePct = { 35 }
        press.press(joker)
        XCTAssertTrue(router.paths.contains("/sound/play/40_joker.mp3?vol=35"))
    }

    func testDurationIsReadBackFromThePlayResponse() {
        router.durationMs = 8600
        let json = press.press(joker)
        XCTAssertTrue(json.contains("\"durationMs\":8600"), json)
        XCTAssertEqual(pending?.delay ?? 0, 8.7, accuracy: 0.0001)
    }

    func testDurationParsingSurvivesAnUnexpectedBody() {
        XCTAssertEqual(SoundboardPress.durationMs(from: "{\"ok\":true,\"durationMs\":5459}"), 5459)
        XCTAssertEqual(SoundboardPress.durationMs(from: "{\"ok\":true}"), 0)
        XCTAssertEqual(SoundboardPress.durationMs(from: ""), 0)
    }

    func testThePlayingTileIsPublishedForTheBorder() {
        var seen: [[String]] = []
        press.onPlayingChanged = { seen.append($0.map(\.asset)) }

        press.press(joker)
        fireCompletion()

        XCTAssertEqual(seen, [["40_joker.mp3"], []])
    }
}
