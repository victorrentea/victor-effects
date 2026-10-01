import XCTest
@testable import VictorEffects

/// The retina overlay the heartbeat tests use: 1512 × 982 points, bottom-origin.
private let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)

final class PulseBrainTests: XCTestCase {

    // The keyframe animation needs key times in [0,1], strictly increasing, from
    // 0 to 1 — otherwise CoreAnimation silently drops it and the brain sits still.
    func testKeyTimesSpanTheRevealAndOnlyMoveForward() {
        let times = PulseBrain.keyframes(in: bounds).keyTimes
        XCTAssertEqual(times.first, 0)
        XCTAssertEqual(times.last, 1)
        for (a, b) in zip(times, times.dropFirst()) { XCTAssertLessThan(a, b) }
    }

    // The brain is at the mask's edge: the reveal is linear, so at key time t
    // it stands at x = t · width.
    func testTheBrainRidesTheMasksEdge() {
        let (positions, times) = PulseBrain.keyframes(in: bounds)
        for (p, t) in zip(positions, times) {
            XCTAssertEqual(p.x, CGFloat(t) * bounds.width, accuracy: 0.001)
        }
    }

    // Bottom-origin layer, top-origin PNG: the R spike (the PNG's highest point)
    // must come out ABOVE the baseline, the S dip below it.
    func testTheSpikeGoesUpOnScreen() {
        let ys = PulseBrain.keyframes(in: bounds).positions.map(\.y)
        let baseline = ys[0]
        XCTAssertGreaterThan(ys.max()! - baseline, bounds.height * 0.25)
        XCTAssertGreaterThan(baseline - ys.min()!, bounds.height * 0.20)
    }

    // Flatline after the second beat: the brain ends on the baseline, at the right edge.
    func testItEndsOnTheFlatline() {
        let positions = PulseBrain.keyframes(in: bounds).positions
        XCTAssertEqual(positions.last!.x, bounds.maxX, accuracy: 0.001)
        XCTAssertEqual(positions.last!.y, positions[0].y, accuracy: bounds.height * 0.01)
    }

    // ☠️ comes 0.3 s after the line goes flat: after the second beat's last
    // bump (~3.03 s into the 5.392 s reveal), well before the reveal ends.
    func testTheSkullComesThreeTenthsAfterTheFlatline() {
        let flat = Double(PulseBrain.flatlineStartX) * 5.392
        XCTAssertEqual(flat, 3.03, accuracy: 0.01)
        XCTAssertEqual(PulseBrain.skullAppearsAt(totalDuration: 5.392), flat + 0.3, accuracy: 0.0001)
    }

    // The flatline really is flat: from flatlineStartX on, the brain stays on the baseline.
    func testFromTheFlatlineStartTheLineIsFlat() {
        let tail = PulseBrain.penPath.filter { $0.x >= PulseBrain.flatlineStartX }
        XCTAssertEqual(tail.count, 2)
        XCTAssertEqual(tail[0].y, tail[1].y, accuracy: 0.005)
    }
}
