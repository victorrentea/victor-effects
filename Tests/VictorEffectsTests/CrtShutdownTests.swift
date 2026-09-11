import XCTest
import QuartzCore
@testable import VictorEffects

/// 📺 The CRT shutdown is built by a pure function, so the shape of the gag —
/// the shutters meeting exactly in the middle, the line being a line, the phases
/// running back to back with no gap — is checkable without a screen.
final class CrtShutdownTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1200)

    /// Each shutter is parked fully off-screen and travels exactly half a screen,
    /// so the two inner edges land on the middle: any other travel leaves either
    /// a transparent seam across the desktop or a line drawn over a shutter that
    /// already crossed the centre.
    func testShuttersTravelHalfAScreenAndMeetInTheMiddle() {
        let top = CrtShutdown.topShutterTravel(in: screen)
        let bottom = CrtShutdown.bottomShutterTravel(in: screen)

        XCTAssertEqual(top.from - top.to, screen.height / 2, accuracy: 0.001)
        XCTAssertEqual(bottom.to - bottom.from, screen.height / 2, accuracy: 0.001)

        // A full-screen-sized rectangle centred on `to`: its inner edge is the
        // middle of the screen, its outer edge is off-screen.
        XCTAssertEqual(top.to - screen.height / 2, screen.midY, accuracy: 0.001)
        XCTAssertEqual(bottom.to + screen.height / 2, screen.midY, accuracy: 0.001)
    }

    /// Both shutters move the same distance in opposite directions — that
    /// symmetry is what makes the effect correct whether or not the host layer's
    /// geometry is flipped.
    func testShutterTravelIsSymmetric() {
        let top = CrtShutdown.topShutterTravel(in: screen)
        let bottom = CrtShutdown.bottomShutterTravel(in: screen)
        XCTAssertEqual(top.from - screen.midY, screen.midY - bottom.from, accuracy: 0.001)
        XCTAssertEqual(top.to - screen.midY, screen.midY - bottom.to, accuracy: 0.001)
    }

    func testLineIsAFullWidthTenPointBandAcrossTheMiddle() {
        let line = CrtShutdown.lineFrame(in: screen)
        XCTAssertEqual(line.width, screen.width, accuracy: 0.001)
        XCTAssertEqual(line.height, 10, accuracy: 0.001)
        XCTAssertEqual(line.midY, screen.midY, accuracy: 0.001)
    }

    /// The phases are consecutive: the line lights up before the shutters finish,
    /// holds, collapses, flashes, then the black fades. A regression that
    /// reordered or overlapped them would show as a stutter mid-gag.
    func testPhasesRunBackToBackAndTotalIsTheirSum() {
        XCTAssertLessThan(CrtShutdown.lineOnAt, CrtShutdown.closeDuration)
        XCTAssertEqual(CrtShutdown.collapseAt, CrtShutdown.closeDuration + CrtShutdown.lineHold, accuracy: 0.0001)
        XCTAssertEqual(CrtShutdown.dotAt, CrtShutdown.collapseAt + CrtShutdown.collapseDuration, accuracy: 0.0001)
        XCTAssertEqual(CrtShutdown.revealAt,
                       CrtShutdown.dotAt + CrtShutdown.dotFade + CrtShutdown.blackHold, accuracy: 0.0001)
        XCTAssertEqual(CrtShutdown.totalDuration,
                       CrtShutdown.closeDuration + CrtShutdown.lineHold + CrtShutdown.collapseDuration
                       + CrtShutdown.dotFade + CrtShutdown.blackHold + CrtShutdown.revealDuration,
                       accuracy: 0.0001)
    }

    /// The close has to be quick — it is the punctuation on a 1.6 s clip, not a
    /// second effect. These are the bounds the room was happy with.
    func testCloseAndCollapseStayInTheirAgreedWindows() {
        XCTAssertGreaterThanOrEqual(CrtShutdown.closeDuration, 0.6)
        XCTAssertLessThanOrEqual(CrtShutdown.closeDuration, 0.8)
        XCTAssertEqual(CrtShutdown.lineHold, 0.15, accuracy: 0.0001)
        XCTAssertEqual(CrtShutdown.collapseDuration, 0.4, accuracy: 0.0001)
    }

    func testMakeLayerBuildsShuttersLineAndDotOnOneContainer() throws {
        let layer = try XCTUnwrap(CrtShutdown.makeLayer(in: screen))
        XCTAssertEqual(layer.frame, screen)
        // two shutters + line + dot
        XCTAssertEqual(layer.sublayers?.count, 4)
        XCTAssertNotNil(layer.animation(forKey: "crtReveal"))

        let shutters = try XCTUnwrap(layer.sublayers).prefix(2)
        for shutter in shutters {
            // Model settles CLOSED, so the fill of a finished close cannot be
            // undone by an implicit animation half a second later.
            XCTAssertEqual(shutter.bounds.size, screen.size)
            let close = try XCTUnwrap(shutter.animation(forKey: "crtClose") as? CABasicAnimation)
            XCTAssertEqual(close.duration, CrtShutdown.closeDuration, accuracy: 0.0001)
            XCTAssertFalse(close.isRemovedOnCompletion)
        }

        let line = try XCTUnwrap(layer.sublayers?[2])
        XCTAssertEqual(line.bounds.size, CrtShutdown.lineFrame(in: screen).size)
        let collapse = try XCTUnwrap(line.animation(forKey: "crtLineCollapse") as? CABasicAnimation)
        XCTAssertEqual(collapse.keyPath, "transform.scale.x")   // both ends inwards, not one
        XCTAssertEqual(collapse.toValue as? Double, 0.0)
    }

    /// The overlay panel can be mid-resize; the iris makes the same guard.
    func testDegenerateScreenBuildsNothing() {
        XCTAssertNil(CrtShutdown.makeLayer(in: .zero))
        XCTAssertNil(CrtShutdown.makeLayer(in: CGRect(x: 0, y: 0, width: 1920, height: 0)))
    }
}
