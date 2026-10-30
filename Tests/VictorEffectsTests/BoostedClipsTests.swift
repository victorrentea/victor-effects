import XCTest
@testable import VictorEffects

/// The limiter behind a tile turned up past the tablet's tick: the amplified
/// copy must never go over the ceiling, and must leave quiet passages at the
/// full boost (otherwise "louder" would only be louder where it was loud).
final class BoostedClipsTests: XCTestCase {
    private let rate = 1000.0   // 1 frame = 1 ms, so the ramps are easy to read

    func testAQuietSignalGetsTheWholeBoost() {
        let g = BoostedClips.limiterGains(frames: 500, sampleRate: rate) { _ in 0.3 }
        XCTAssertEqual(g.min(), 1)
    }

    func testAPeakNeverGoesOverTheCeiling() {
        let peaks: [Float] = (0..<1000).map { $0 == 400 ? 1.0 : ($0 % 7 == 0 ? 0.8 : 0.2) }
        let g = BoostedClips.limiterGains(frames: peaks.count, sampleRate: rate) { peaks[$0] }
        for i in peaks.indices {
            XCTAssertLessThanOrEqual(peaks[i] * BoostedClips.headroom * g[i], BoostedClips.ceiling + 1e-5, "frame \(i)")
        }
    }

    func testTheGainRampsDownBeforeAPeakAndRecoversAfter() {
        let peaks: [Float] = (0..<1000).map { $0 == 500 ? 1.0 : 0.1 }
        let g = BoostedClips.limiterGains(frames: peaks.count, sampleRate: rate) { peaks[$0] }
        XCTAssertLessThan(g[499], 1, "already ducking ahead of the peak")
        XCTAssertEqual(g[400], 1)
        XCTAssertLessThan(g[520], 1, "still recovering just after")
        XCTAssertEqual(g[999], 1, "back to the full boost")
    }

    func testTheTopOfTheBarIsTheHeadroom() {
        XCTAssertEqual(BoostedClips.headroom, SoundGains.gain(position: 100))
        XCTAssertGreaterThan(BoostedClips.headroom, 1)
    }
}
