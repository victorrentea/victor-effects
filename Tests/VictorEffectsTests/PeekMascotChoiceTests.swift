import XCTest
@testable import VictorEffects

/// The ⌘⌃Q mascot is a day-scoped choice, not a rotation. These assert the
/// three things that make it predictable in front of a room: it opens on
/// Claude, a click sticks, and the stickiness expires with the day.
final class PeekMascotChoiceTests: XCTestCase {

    private let today = Date(timeIntervalSince1970: 1_757_500_000)   // 2026-09-10
    private var tomorrow: Date { today.addingTimeInterval(24 * 3600) }

    func testNothingStoredMeansClaude() {
        XCTAssertEqual(
            PeekMascotChoice.resolve(stored: nil, storedDay: nil, now: today), .claude,
            "a day opens on Claude — the courses are Claude courses"
        )
    }

    func testAClickSticksForTheRestOfTheDay() {
        let picked = PeekMascotChoice.flipped(stored: nil, storedDay: nil, now: today)
        XCTAssertEqual(picked, .copilot)
        // Every later press that day sees the same robot: the point of the
        // click is that it is declared once, not before every press.
        XCTAssertEqual(
            PeekMascotChoice.resolve(
                stored: picked.rawValue,
                storedDay: PeekMascotChoice.dayKey(today),
                now: today
            ),
            .copilot
        )
    }

    func testClickingAgainGoesBack() {
        let day = PeekMascotChoice.dayKey(today)
        let back = PeekMascotChoice.flipped(stored: PeekMascot.copilot.rawValue, storedDay: day, now: today)
        XCTAssertEqual(back, .claude, "the gesture is its own undo")
    }

    func testYesterdaysChoiceIsNotTodaysDefault() {
        XCTAssertEqual(
            PeekMascotChoice.resolve(
                stored: PeekMascot.copilot.rawValue,
                storedDay: PeekMascotChoice.dayKey(today),
                now: tomorrow
            ),
            .claude,
            "a Copilot day ends with the day; no midnight timer needed"
        )
    }

    func testAStaleChoiceFlipsAwayFromWhatIsOnScreen() {
        // The stored pick is yesterday's, so what shows today is Claude — and a
        // click must land on Copilot, not flip the *stored* Copilot to Claude
        // and appear to do nothing.
        let day = PeekMascotChoice.dayKey(today)
        XCTAssertEqual(
            PeekMascotChoice.flipped(stored: PeekMascot.copilot.rawValue, storedDay: day, now: tomorrow),
            .copilot
        )
    }

    func testAnUnknownStoredNameFallsBackInsteadOfShowingNothing() {
        XCTAssertEqual(
            PeekMascotChoice.resolve(
                stored: "gemini-icon",
                storedDay: PeekMascotChoice.dayKey(today),
                now: today
            ),
            .claude,
            "renaming a resource must not leave the key drawing nothing"
        )
    }

    /// The raw value IS the resource name, so a typo in the enum is a key that
    /// silently draws nothing. `Bundle.module` here is the *test* bundle, not
    /// the app's, so the check is against the source tree.
    func testEveryMascotNamesAShippedImage() {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // VictorEffectsTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("Sources/VictorEffects/Resources")
        for mascot in PeekMascot.allCases {
            let png = resources.appendingPathComponent("\(mascot.rawValue).png")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: png.path),
                "\(mascot.rawValue).png is not in Resources"
            )
        }
        XCTAssertEqual(PeekMascot.claude.flipped, .copilot)
        XCTAssertEqual(PeekMascot.copilot.flipped, .claude)
    }
}
