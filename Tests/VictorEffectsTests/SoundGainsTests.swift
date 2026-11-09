import XCTest
@testable import VictorEffects

/// 🔉 The per-tile volume bar on the tablet. Its promise: a tile nobody touched
/// sounds exactly as before (80 = ×1.0), and a moved one is remembered.
final class SoundGainsTests: XCTestCase {
    private var scratch: URL!

    override func setUp() {
        super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("gains-\(UUID().uuidString).json")
        SoundGains.useForTesting(scratch)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        SoundGains.useForTesting(SoundGains.defaultURL)
        super.tearDown()
    }

    func testAnUntouchedTilePlaysAtTheOldLevel() {
        XCTAssertEqual(SoundGains.position(of: "01_baby.mp3"), 80)
        XCTAssertEqual(SoundGains.gain(for: "01_baby.mp3"), 1.0, accuracy: 0.0001)
    }

    func testTheCurveIsTheWedgesSquaredOnePinnedAt80() {
        XCTAssertEqual(SoundGains.gain(position: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(SoundGains.gain(position: 40), 0.25, accuracy: 0.0001)
        // Down only: nothing above the clip as stored (2026-11-09).
        XCTAssertEqual(SoundGains.gain(position: 100), 1, accuracy: 0.0001)
        XCTAssertEqual(SoundGains.gain(position: 140), 1, accuracy: 0.0001)
    }

    func testAMovedTileIsPersistedAndMovesTheHash() {
        let before = SoundGains.hash
        SoundGains.set("03_explosion.mp3", 55)
        XCTAssertNotEqual(SoundGains.hash, before)
        SoundGains.useForTesting(scratch)          // what a relaunch does
        XCTAssertEqual(SoundGains.position(of: "03_explosion.mp3"), 55)
        XCTAssertTrue(SoundGains.json.contains("\"03_explosion.mp3\":55"))
    }

    func testBackAtTheDefaultTheRowIsDropped() {
        SoundGains.set("03_explosion.mp3", 55)
        SoundGains.set("03_explosion.mp3", 80)
        XCTAssertFalse(SoundGains.json.contains("03_explosion"))
    }

    func testAStoredRowAboveTheTickIsClampedToTheFileAsStored() throws {
        try Data("{\"gains\":{\"04_wolf.mp3\":85,\"18_chainsaw.mp3\":25},\"defaultPct\":80}".utf8).write(to: scratch)
        SoundGains.useForTesting(scratch)
        XCTAssertEqual(SoundGains.position(of: "04_wolf.mp3"), 80)
        XCTAssertEqual(SoundGains.gain(for: "04_wolf.mp3"), 1, accuracy: 0.0001)
        XCTAssertEqual(SoundGains.position(of: "18_chainsaw.mp3"), 25, "an attenuated row keeps its exact gain")
        XCTAssertFalse(String(decoding: try Data(contentsOf: scratch), as: UTF8.self).contains("wolf"))
    }

    func testTheBarCannotBeSetAboveTheTick() {
        SoundGains.set("03_explosion.mp3", 95)
        XCTAssertEqual(SoundGains.position(of: "03_explosion.mp3"), 80)
        XCTAssertFalse(SoundGains.json.contains("03_explosion"))
    }

    func testTheRoutesParse() {
        XCTAssertEqual(EffectsRouter.route(forPath: "/sound/gains"), .soundGains)
        XCTAssertEqual(EffectsRouter.route(forPath: "/sound/gain/03_explosion.mp3/65"), .soundGainSet("03_explosion.mp3", 65))
        XCTAssertEqual(EffectsRouter.route(forPath: "/sound/gain/03_explosion.mp3"), .unknown)
    }
}
