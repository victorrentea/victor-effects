import XCTest
@testable import VictorEffects

/// The green dots on the tablet are drawn from these numbers, and the tablet no
/// longer keeps a table of its own — so "the Mac counted it" is the only reason
/// a dot ever moves. What that buys, and what these tests pin, is that the
/// panel's presses and the tablet's presses land in the SAME counter.
final class UsageCountsTests: XCTestCase {
    private var scratch: URL!

    override func setUp() {
        super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString).json")
        UsageCounts.useForTesting(scratch)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        UsageCounts.useForTesting(UsageCounts.defaultURL)
        super.tearDown()
    }

    func testRecordCountsAndPersists() {
        UsageCounts.record("03_explosion.mp3")
        UsageCounts.record("03_explosion.mp3")
        UsageCounts.record("01_baby.mp3")
        XCTAssertEqual(UsageCounts.all["03_explosion.mp3"], 2)
        XCTAssertEqual(UsageCounts.all["01_baby.mp3"], 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.path))
    }

    /// The hash is what a 5-second `/ping` carries, and it is the only thing
    /// telling the tablet to re-pull the table. A press that does not move it is
    /// a dot that never lights.
    func testHashMovesOnEveryPressAndIsStable() {
        let empty = UsageCounts.hash
        UsageCounts.record("50_gong.mp3")
        let afterOne = UsageCounts.hash
        XCTAssertNotEqual(empty, afterOne)
        XCTAssertEqual(afterOne, UsageCounts.hash, "same counts must hash the same")
        UsageCounts.record("50_gong.mp3")
        XCTAssertNotEqual(afterOne, UsageCounts.hash)
    }

    /// The tablet's history is seeded in once, over a link that may deliver it
    /// twice. Max-merge makes the second delivery a no-op instead of a doubling.
    func testMergeKeepsTheLargerAndIsIdempotent() {
        UsageCounts.record("40_joker.mp3")           // Mac: 1
        UsageCounts.merge(["40_joker.mp3": 57, "26_drum.mp3": 4])
        XCTAssertEqual(UsageCounts.all["40_joker.mp3"], 57)
        XCTAssertEqual(UsageCounts.all["26_drum.mp3"], 4)

        let hash = UsageCounts.hash
        UsageCounts.merge(["40_joker.mp3": 57, "26_drum.mp3": 4])
        XCTAssertEqual(UsageCounts.hash, hash, "a repeated seed must change nothing")

        UsageCounts.merge(["40_joker.mp3": 3])
        XCTAssertEqual(UsageCounts.all["40_joker.mp3"], 57, "a smaller number must never win")
    }

    func testJSONCarriesTheHashItWasComputedFrom() throws {
        UsageCounts.record("22_minigun.mp3")
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(UsageCounts.json.utf8)) as? [String: Any])
        XCTAssertEqual((obj["counts"] as? [String: Int])?["22_minigun.mp3"], 1)
        XCTAssertEqual(obj["hash"] as? String, UsageCounts.hash)
    }

    func testSurvivesAReload() {
        UsageCounts.record("11_fire.mp3")
        UsageCounts.record("11_fire.mp3")
        // Re-point at the same file: the static table is rebuilt from disk the
        // way it is at app launch.
        UsageCounts.useForTesting(scratch)
        XCTAssertEqual(UsageCounts.all["11_fire.mp3"], 2, "counts must outlive a restart")
    }

    func testResetClearsEverything() {
        UsageCounts.record("11_fire.mp3")
        UsageCounts.reset()
        XCTAssertTrue(UsageCounts.all.isEmpty)
    }
}
