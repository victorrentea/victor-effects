import XCTest
@testable import VictorEffects

final class FireAlarmTests: XCTestCase {

    /// The bell's own rectangle on screen, bottom-origin.
    private func bellOnScreen(in bounds: CGRect) -> CGRect {
        let f = FireAlarm.frame(in: bounds)
        let s = f.width / FireAlarm.canvasSide
        return CGRect(x: f.minX + FireAlarm.bell.minX * s,
                      y: f.minY + (FireAlarm.canvasSide - FireAlarm.bell.maxY) * s,
                      width: FireAlarm.bell.width * s,
                      height: FireAlarm.bell.height * s)
    }

    func testTheBellFillsTheWidthOfTheBoxAsDrawn_on1920by1080() {
        let bell = bellOnScreen(in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(bell.minX, 104, accuracy: 0.5)
        XCTAssertEqual(bell.maxX, 481, accuracy: 0.5)
        // Top-origin 102…537 in the drawing, so bottom-origin 543…978.
        XCTAssertGreaterThanOrEqual(bell.minY, 543)
        XCTAssertLessThanOrEqual(bell.maxY, 978)
        XCTAssertEqual(bell.midY, 760.5, accuracy: 0.5)
    }

    func testItStaysInsideTheSameBoxOnA16by10Retina() {
        let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let bell = bellOnScreen(in: bounds)
        XCTAssertGreaterThanOrEqual(bell.minX, 1512 * FireAlarm.boxLeft - 0.5)
        XCTAssertLessThanOrEqual(bell.maxX, 1512 * FireAlarm.boxRight + 0.5)
        XCTAssertGreaterThanOrEqual(bell.minY, 982 * (1 - FireAlarm.boxBottom) - 0.5)
        XCTAssertLessThanOrEqual(bell.maxY, 982 * (1 - FireAlarm.boxTop) + 0.5)
    }

    func testTheWholeCanvasStaysOnTheGlass() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(bounds.contains(FireAlarm.frame(in: bounds)))
    }
}
