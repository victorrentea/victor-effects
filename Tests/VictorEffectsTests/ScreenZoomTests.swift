import XCTest
@testable import VictorEffects

/// The built-in retina as the window server reports it: global CG points, y
/// counted DOWN from the top-left of the arrangement, this display first.
private let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)

/// A second display to the right, so the "global, not display-local" part of
/// the conversion is actually exercised.
private let rightHandDisplay = CGRect(x: 1728, y: 0, width: 1920, height: 1080)

private func unit(_ center: CGPoint, _ factor: Double, on bounds: CGRect = display) -> CGRect? {
    ScreenZoom.unitViewport(displayBounds: bounds, center: center, factor: factor)
}

final class ScreenZoomTests: XCTestCase {

    /// What an idle display answers: dead centre, magnification exactly 1. That
    /// is the reading that must mean "draw on the whole screen", or every
    /// overlay shrinks by a rounding error on a Mac nobody zoomed.
    func testAnIdleDisplayIsNotAViewport() {
        XCTAssertNil(unit(CGPoint(x: 864, y: 558), 1.0))
    }

    func testAMagnificationBelowTheThresholdIsIgnored() {
        XCTAssertNil(unit(CGPoint(x: 864, y: 558), 1.005))
    }

    func testDoubleZoomInTheMiddleIsTheMiddleQuarter() {
        let v = unit(CGPoint(x: 864, y: 558.5), 2.0)
        XCTAssertEqual(v?.minX ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(v?.minY ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(v?.width ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(v?.height ?? -1, 0.5, accuracy: 0.0001)
    }

    /// The flip. SkyLight's y grows downward; CALayer's grows upward, so a
    /// viewport centred a quarter of the way down the display must come back
    /// three quarters of the way up it.
    func testTheVerticalAxisIsFlipped() {
        let v = unit(CGPoint(x: 864, y: display.height * 0.25), 4.0)
        XCTAssertEqual(v?.midY ?? -1, 0.75, accuracy: 0.0001)
    }

    /// A centre near an edge describes a slice that would hang off the display.
    /// macOS never shows such a slice, so neither do we — and this is also what
    /// keeps the answer right if a future macOS reports an unclamped point.
    func testAViewportIsPushedBackInsideTheDisplay() {
        let v = unit(CGPoint(x: 0, y: 0), 2.0)
        XCTAssertEqual(v?.minX ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(v?.minY ?? -1, 0.5, accuracy: 0.0001)   // top-left in CG is top-left in layer space

        let bottomRight = unit(CGPoint(x: display.width, y: display.height), 2.0)
        XCTAssertEqual(bottomRight?.minX ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(bottomRight?.minY ?? -1, 0, accuracy: 0.0001)
    }

    /// The centre arrives in the coordinates of the whole arrangement, so a
    /// display that does not start at x = 0 has to have its origin subtracted.
    func testASecondDisplayIsMeasuredFromItsOwnOrigin() {
        let v = unit(CGPoint(x: 2688, y: 540), 2.0, on: rightHandDisplay)
        XCTAssertEqual(v?.minX ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(v?.minY ?? -1, 0.25, accuracy: 0.0001)
    }

    func testADisplayWithNoAreaHasNoViewport() {
        XCTAssertNil(unit(CGPoint(x: 0, y: 0), 2.0, on: CGRect(x: 0, y: 0, width: 0, height: 0)))
    }

    /// `visibleRect` answers in whatever coordinates it was handed, which is how
    /// one helper serves both a CALayer's bounds and an NSPanel's global frame.
    func testVisibleRectFallsBackToTheWholeRectWithoutAScreen() {
        let full = CGRect(x: 1728, y: 37, width: 1920, height: 1080)
        XCTAssertEqual(ScreenZoom.visibleRect(in: full, of: nil), full)
    }
}
