import XCTest
@testable import VictorEffects

final class VisibleCursorTests: XCTestCase {
    private let real = NSPoint(x: 10, y: 20)
    private let drawn = NSPoint(x: 500, y: 600)

    func testNoZoomMeansTheRealPointer() {
        XCTAssertEqual(VisibleCursor.resolve(drawn: nil, now: 100, real: real), real)
    }

    func testAFreshDrawnCursorWins() {
        XCTAssertEqual(VisibleCursor.resolve(drawn: (drawn, 99.9), now: 100, real: real), drawn)
    }

    /// A crashed or quit addons app must not leave the effects pinned to a dead point.
    func testAStaleDrawnCursorIsIgnored() {
        XCTAssertEqual(VisibleCursor.resolve(drawn: (drawn, 98), now: 100, real: real), real)
    }
}
