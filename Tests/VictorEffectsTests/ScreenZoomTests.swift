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

    // MARK: ZoomSlice — the frozen slice screenshot effects draw into

    /// A 400×200 capture whose TOP half is red, the way a screenshot of a red
    /// menu bar region would be.
    private func topRedImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 100, width: 400, height: 100))   // context y is up: the top half
        return ctx.makeImage()!
    }

    private func isRed(_ image: CGImage) -> Bool {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return px[0] > 200 && px[2] < 50
    }

    /// The flip that is easy to get backwards: the unit viewport counts y UP,
    /// the image's rows count DOWN. A slice at the top of the display must crop
    /// the first rows of the picture, not the last.
    func testCropOfATopSliceTakesTheTopRowsOfTheCapture() {
        let slice = ZoomSlice(unit: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                              rect: CGRect(x: 0, y: 558.5, width: 864, height: 558.5))
        let cropped = slice.crop(topRedImage())!
        XCTAssertEqual(cropped.width, 200)
        XCTAssertEqual(cropped.height, 100)
        XCTAssertTrue(isRed(cropped))
    }

    func testCropOfABottomSliceTakesTheBottomRows() {
        let slice = ZoomSlice(unit: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                              rect: CGRect(x: 864, y: 0, width: 864, height: 558.5))
        XCTAssertFalse(isRed(slice.crop(topRedImage())!))
    }

    func testAnUnzoomedSliceLeavesTheCaptureAlone() {
        let image = topRedImage()
        let slice = ZoomSlice(unit: nil, rect: display)
        XCTAssertTrue(slice.crop(image) === image)
        XCTAssertEqual(slice.local, CGRect(origin: .zero, size: display.size))
    }

    // MARK: - Staging an effect laid out for one slice onto another

    /// Started zoomed in 2× on the left half-ish, then zoomed OUT to 1×: the
    /// effect must grow to cover the whole display, centred on it.
    func testAnEffectLaidOutForASliceGrowsToTheWholeDisplayOnZoomOut() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let slice = CGRect(x: 100, y: 200, width: 864, height: 558.5)
        let g = ZoomFollower.stageGeometry(visible: display, laidOut: slice)
        XCTAssertEqual(g.bounds.size, slice.size, "children keep the size they were laid out for")
        XCTAssertEqual(g.scale, 2, accuracy: 1e-9)
        XCTAssertEqual(g.position, CGPoint(x: display.midX, y: display.midY))
    }

    /// Zoomed further in (2× → 4×) and panned: half the size, centred on the
    /// new slice — which the 4× magnification blows back up to the same glass.
    func testAnEffectLaidOutForASliceFollowsAZoomInAndPan() {
        let slice2x = CGRect(x: 100, y: 200, width: 864, height: 558.5)
        let slice4x = CGRect(x: 900, y: 50, width: 432, height: 279.25)
        let g = ZoomFollower.stageGeometry(visible: slice4x, laidOut: slice2x)
        XCTAssertEqual(g.scale, 0.5, accuracy: 1e-9)
        XCTAssertEqual(g.position, CGPoint(x: slice4x.midX, y: slice4x.midY))
        // On the glass: laid-out width × scale × magnification(4×) = the display width.
        XCTAssertEqual(g.bounds.width * g.scale * 4, 1728, accuracy: 1e-6)
    }

    /// No zoom change: the identity — staging must not move an effect that
    /// started where it still is.
    func testStagingOntoTheSameSliceIsTheIdentity() {
        let slice = CGRect(x: 100, y: 200, width: 864, height: 558.5)
        let g = ZoomFollower.stageGeometry(visible: slice, laidOut: slice)
        XCTAssertEqual(g.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(g.position, CGPoint(x: slice.midX, y: slice.midY))
    }

    // MARK: - Drawing AT the pointer: 1/zoom about the pointer

    func testTheCounterScaleIsTheInverseOfTheZoomAndExactlyOneAtRest() {
        XCTAssertEqual(ScreenZoom.counterScale(for: 2), 0.5)
        XCTAssertEqual(ScreenZoom.counterScale(for: 4), 0.25)
        XCTAssertEqual(ScreenZoom.counterScale(for: 1), 1)
        // Under the threshold is "not zoomed": exactly 1, not 0.995.
        XCTAssertEqual(ScreenZoom.counterScale(for: 1.005), 1)
    }

    /// A pointer stage over the overlay, pinned at the pointer: the pointer
    /// stays where it is, and anything d away from it lands d/zoom away — so
    /// the 2× magnification puts it back exactly d away on the glass.
    func testAPointerStageShrinksItsChildrenAboutThePointer() {
        let (host, stage) = pinnedStage(pivot: CGPoint(x: 1200, y: 300), factor: 2)
        assertPoint(host.convert(CGPoint(x: 1200, y: 300), from: stage), CGPoint(x: 1200, y: 300))
        assertPoint(host.convert(CGPoint(x: 1400, y: 300), from: stage), CGPoint(x: 1300, y: 300))
        assertPoint(host.convert(CGPoint(x: 1200, y: 100), from: stage), CGPoint(x: 1200, y: 200))
        // A child laid out in display coordinates keeps them: its centre on the
        // pointer stays on the pointer, its size halves.
        let child = CALayer()
        child.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        child.position = CGPoint(x: 1200, y: 300)
        stage.addSublayer(child)
        let seen = host.convert(child.frame, from: stage)
        XCTAssertEqual(seen.width, 100, accuracy: 1e-9)
        XCTAssertEqual(seen.height, 50, accuracy: 1e-9)
        assertPoint(CGPoint(x: seen.midX, y: seen.midY), CGPoint(x: 1200, y: 300))
    }

    /// At rest nothing moves: the stage covers the display exactly, unscaled,
    /// wherever the pointer is.
    func testAPointerStageIsTheIdentityAtRest() {
        for factor: CGFloat in [1, 1.005] {
            let (host, stage) = pinnedStage(pivot: CGPoint(x: 37, y: 1050), factor: factor)
            XCTAssertTrue(CATransform3DIsIdentity(stage.transform))
            XCTAssertEqual(stage.frame, display)
            assertPoint(host.convert(CGPoint(x: 1000, y: 10), from: stage), CGPoint(x: 1000, y: 10))
        }
    }

    /// The zoom moves mid-effect (⌥-scroll in, then out): re-pinning follows
    /// it both ways and a pointer that moved meanwhile is still the fixed point.
    func testRepinningAPointerStageFollowsTheZoomAndThePointer() {
        let (host, stage) = pinnedStage(pivot: CGPoint(x: 500, y: 500), factor: 2)
        ScreenZoom.pinPointerStage(stage, full: display, pivot: CGPoint(x: 900, y: 200), factor: 4)
        assertPoint(host.convert(CGPoint(x: 900, y: 200), from: stage), CGPoint(x: 900, y: 200))
        assertPoint(host.convert(CGPoint(x: 1300, y: 200), from: stage), CGPoint(x: 1000, y: 200))
        ScreenZoom.pinPointerStage(stage, full: display, pivot: CGPoint(x: 900, y: 200), factor: 1)
        XCTAssertEqual(stage.frame, display)
    }

    private func pinnedStage(pivot: CGPoint, factor: CGFloat) -> (host: CALayer, stage: CALayer) {
        let host = CALayer()
        host.frame = display
        let stage = CALayer()
        stage.frame = display
        host.addSublayer(stage)
        ScreenZoom.pinPointerStage(stage, full: display, pivot: pivot, factor: factor)
        return (host, stage)
    }

    private func assertPoint(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-6, file: file, line: line)
    }
}
