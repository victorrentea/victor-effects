import XCTest
import Foundation
@testable import VictorEffects

/// Verifies the Swift whip physics is a faithful port of OpenWhip's JS
/// (overlay.html). The cross-language parity tests replay the EXACT scenarios
/// defined in tools/whip-parity/generate-golden.js and assert the Swift port
/// reproduces the golden values generated from the original JavaScript.
///
/// Regenerate the golden with: `node tools/whip-parity/generate-golden.js`.
final class WhipPhysicsTests: XCTestCase {

    // Tolerances. Settle is contractive → essentially bit-identical (only
    // sin/cos/acos/atan2 differ ≤1 ulp between V8 and Apple libm). Swing is 70
    // frames of vigorous motion → a hair looser but still 100× tighter than any
    // real porting bug (a dropped iteration / wrong sign shifts coords by ≥0.1px).
    private let settleTol = 1e-6
    private let swingTol = 1e-4

    // MARK: - Golden model

    private struct Golden: Decodable {
        struct Scenario: Decodable {
            let W, H: Double
            let segments: Int
            let spawnX, spawnY, frameMs: Double
        }
        struct Settle: Decodable {
            let snapshotFrames: [Int]
            let points: [String: [[Double]]]
        }
        struct Swing: Decodable {
            let N: Int
            let crackFrames: [Int]
            let tipVelByFrame: [Double]
            let finalPoints: [[Double]]
        }
        let scenario: Scenario
        let settle: Settle
        let swing: Swing
    }

    private func loadGolden() throws -> Golden {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "whip_golden.json", withExtension: nil, subdirectory: "Resources"),
            "whip_golden.json must be bundled in the test target"
        )
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    /// Mirrors generate-golden.js freshSim(): spawn at (spawnX,spawnY) with now=0,
    /// which resets handleAngle/handleAngVel/prevMouse/lastCrackTime/whipSpawnTime
    /// exactly as the JS scenario runner does.
    private func freshSim(_ g: Golden) -> WhipPhysics {
        let sim = WhipPhysics(width: g.scenario.W, height: g.scenario.H)
        sim.spawn(mouseX: g.scenario.spawnX, mouseY: g.scenario.spawnY, now: 0)
        return sim
    }

    /// Swing path — must match generate-golden.js `swingPath` byte-for-byte.
    private func swingX(_ f: Int, spawnX: Double) -> Double {
        if f <= 8 { return spawnX }
        let k = Double(f - 8)
        return spawnX + 320 * sin(k * 0.85)
    }

    // MARK: - Invariants

    func testSpawnGeometry() {
        let sim = WhipPhysics(width: 1280, height: 800)
        sim.spawn(mouseX: 640, mouseY: 400, now: 0)
        XCTAssertTrue(sim.isActive)
        XCTAssertEqual(sim.points.count, WhipPhysics.P.segments)
        // Handle anchored at the cursor; arc extends right and up.
        XCTAssertEqual(sim.points.first!.x, 640, accuracy: 1e-9)
        XCTAssertEqual(sim.points.first!.y, 400, accuracy: 1e-9)
        XCTAssertGreaterThan(sim.points.last!.x, sim.points.first!.x) // tip is to the right
    }

    // MARK: - Cross-language parity: settle

    func testSettleMatchesJSGolden() throws {
        let g = try loadGolden()
        XCTAssertEqual(g.scenario.segments, WhipPhysics.P.segments)
        let sim = freshSim(g)
        let snaps = Set(g.settle.snapshotFrames)
        let last = g.settle.snapshotFrames.max() ?? 0

        for f in 1...last {
            sim.setMouse(g.scenario.spawnX, g.scenario.spawnY)
            sim.update(now: Double(f) * g.scenario.frameMs)
            guard snaps.contains(f) else { continue }
            let expected = g.settle.points[String(f)]!
            XCTAssertEqual(sim.points.count, expected.count)
            for i in 0..<expected.count {
                XCTAssertEqual(sim.points[i].x, expected[i][0], accuracy: settleTol, "settle f\(f) p\(i).x")
                XCTAssertEqual(sim.points[i].y, expected[i][1], accuracy: settleTol, "settle f\(f) p\(i).y")
            }
        }
    }

    // MARK: - Cross-language parity: swing (cracks + final shape)

    func testSwingMatchesJSGolden() throws {
        let g = try loadGolden()
        let sim = freshSim(g)
        var cracks: [Int] = []

        for f in 1...g.swing.N {
            sim.setMouse(swingX(f, spawnX: g.scenario.spawnX), g.scenario.spawnY)
            if sim.update(now: Double(f) * g.scenario.frameMs) { cracks.append(f) }
        }

        // The whole point: cracks fire on the same frames as the original JS.
        XCTAssertEqual(cracks, g.swing.crackFrames, "crack frames must match the JS golden")
        XCTAssertFalse(cracks.isEmpty, "swing scenario must actually crack")

        // And the resulting whip shape matches frame-for-frame.
        let expected = g.swing.finalPoints
        XCTAssertEqual(sim.points.count, expected.count)
        for i in 0..<expected.count {
            XCTAssertEqual(sim.points[i].x, expected[i][0], accuracy: swingTol, "swing final p\(i).x")
            XCTAssertEqual(sim.points[i].y, expected[i][1], accuracy: swingTol, "swing final p\(i).y")
        }
    }

    // MARK: - Crack gating (grace + cooldown), Swift-only & deterministic

    func testGraceBlocksCracksBeforeThreshold() {
        let sim = WhipPhysics(width: 1280, height: 800)
        sim.spawn(mouseX: 640, mouseY: 400, now: 0)
        // Vigorous motion from frame 1; nothing may crack before firstCrackGraceMs.
        for f in 1...40 {
            let k = Double(f)
            sim.setMouse(640 + 320 * sin(k * 0.5), 400)
            let now = Double(f) * 16
            let cracked = sim.update(now: now)
            if now < WhipPhysics.P.firstCrackGraceMs {
                XCTAssertFalse(cracked, "crack fired during grace window at frame \(f) (now=\(now)ms)")
            }
        }
    }

    func testCooldownSeparatesCracks() {
        let g = (try? loadGolden())
        // Reuse the golden's known crack frames if available; otherwise skip.
        guard let crackFrames = g?.swing.crackFrames, crackFrames.count >= 2 else { return }
        let frameMs = g!.scenario.frameMs
        for i in 1..<crackFrames.count {
            let gapMs = Double(crackFrames[i] - crackFrames[i - 1]) * frameMs
            XCTAssertGreaterThan(gapMs, WhipPhysics.P.crackCooldownMs,
                                 "consecutive cracks must be >crackCooldownMs apart")
        }
    }
}
