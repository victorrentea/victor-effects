import XCTest
@testable import VictorEffects

/// 🔴 The three things about the red button that are decisions rather than
/// drawing: **where** it lands, **which pixels are it**, and **what order its
/// life happens in**. All three are pure functions in `RedButton`, so they are
/// asserted here without a screen, a window server or an event tap — the same
/// bargain `WazzupCorner` and `SketchArrow` make.
final class RedButtonTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    /// The shipped asset's aspect (468×426), so the numbers below are the real ones.
    private let art = CGSize(width: 468, height: 426)

    // MARK: - Geometry

    func testHeightIsHalfTheScreenAndTheAspectIsTheImages() {
        let f = RedButton.frame(imageSize: art, in: screen, centredOn: CGPoint(x: 800, y: 500))
        XCTAssertEqual(f.height, screen.height / 2, accuracy: 0.001)
        XCTAssertEqual(f.width / f.height, art.width / art.height, accuracy: 0.0001)
    }

    /// The whole effect is "it grows out of P and shrinks back into P". A frame
    /// whose centre is not P would shrink into the wrong pixel.
    func testItIsCentredExactlyOnThePointer() {
        for p in [CGPoint(x: 864, y: 558), CGPoint(x: 0, y: 0), CGPoint(x: 1728, y: 1117)] {
            let f = RedButton.frame(imageSize: art, in: screen, centredOn: p)
            XCTAssertEqual(f.midX, p.x, accuracy: 0.001)
            XCTAssertEqual(f.midY, p.y, accuracy: 0.001)
        }
    }

    /// Deliberately NOT clamped onto the screen: see the doc on `frame`. A
    /// pointer parked in the corner gets a button hanging off the edge, because
    /// the alternative is a button that shrinks into somewhere nobody clicked.
    func testAPointerInTheCornerIsNotNudgedInwards() {
        let f = RedButton.frame(imageSize: art, in: screen, centredOn: CGPoint(x: 4, y: 4))
        XCTAssertLessThan(f.minX, 0)
        XCTAssertLessThan(f.minY, 0)
    }

    func testADegenerateImageOrScreenDoesNotCrashOrDivide() {
        XCTAssertEqual(RedButton.frame(imageSize: .zero, in: screen, centredOn: .zero).size, .zero)
        XCTAssertEqual(RedButton.frame(imageSize: art, in: .zero, centredOn: .zero).size, .zero)
    }

    // MARK: - Alpha hit-test

    /// A 4×4 mask: opaque in the middle 2×2, transparent all round — the shape of
    /// the real problem, which is a round button in a square box.
    private func ringMask() -> RedButton.AlphaMask {
        let o: UInt8 = 255, t: UInt8 = 0
        return RedButton.AlphaMask(width: 4, height: 4, alpha: [
            t, t, t, t,
            t, o, o, t,
            t, o, o, t,
            t, t, t, t,
        ])
    }

    func testTheTransparentCornersAreNotTheButton() {
        let f = CGRect(x: 100, y: 200, width: 400, height: 400)
        let mask = ringMask()
        // Each of the four corners of the bounding box.
        for p in [CGPoint(x: 110, y: 210), CGPoint(x: 490, y: 210),
                  CGPoint(x: 110, y: 590), CGPoint(x: 490, y: 590)] {
            XCTAssertFalse(RedButton.isOpaque(at: p, restingFrame: f, mask: mask),
                           "\(p) is a transparent corner — a click there must reach the app underneath")
        }
        XCTAssertTrue(RedButton.isOpaque(at: CGPoint(x: 300, y: 400), restingFrame: f, mask: mask))
    }

    /// The mask's rows run top-down and the pointer's world runs bottom-up. Get
    /// the flip wrong and the button is hit-tested upside down, which on a
    /// symmetrical circle is invisible until somebody ships an asymmetric asset.
    func testTheVerticalFlipIsApplied() {
        // Opaque only in the TOP-LEFT cell.
        let mask = RedButton.AlphaMask(width: 2, height: 2, alpha: [255, 0,
                                                                     0, 0])
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(RedButton.isOpaque(at: CGPoint(x: 25, y: 75), restingFrame: f, mask: mask),
                      "the image's top-left is the HIGH-y half in pointer coordinates")
        XCTAssertFalse(RedButton.isOpaque(at: CGPoint(x: 25, y: 25), restingFrame: f, mask: mask))
    }

    func testAPointOutsideTheFrameIsNeverTheButton() {
        let f = CGRect(x: 100, y: 200, width: 400, height: 400)
        let mask = RedButton.AlphaMask(width: 1, height: 1, alpha: [255])
        XCTAssertFalse(RedButton.isOpaque(at: CGPoint(x: 99, y: 400), restingFrame: f, mask: mask))
        XCTAssertFalse(RedButton.isOpaque(at: CGPoint(x: 501, y: 400), restingFrame: f, mask: mask))
        XCTAssertFalse(RedButton.isOpaque(at: CGPoint(x: 300, y: 199), restingFrame: f, mask: mask))
        XCTAssertFalse(RedButton.isOpaque(at: CGPoint(x: 300, y: 601), restingFrame: f, mask: mask))
        XCTAssertTrue(RedButton.isOpaque(at: CGPoint(x: 300, y: 400), restingFrame: f, mask: mask))
    }

    func testTheThresholdIsHalfOpaque() {
        let f = CGRect(x: 0, y: 0, width: 10, height: 10)
        let faint = RedButton.AlphaMask(width: 1, height: 1, alpha: [127])
        let half = RedButton.AlphaMask(width: 1, height: 1, alpha: [128])
        XCTAssertFalse(RedButton.isOpaque(at: CGPoint(x: 5, y: 5), restingFrame: f, mask: faint))
        XCTAssertTrue(RedButton.isOpaque(at: CGPoint(x: 5, y: 5), restingFrame: f, mask: half))
    }

    // MARK: - The state machine

    /// Drive a sequence of events and collect everything that happened.
    private func run(_ events: [RedButton.Event],
                     from start: RedButton.Phase = .zoomIn)
        -> (RedButton.Phase, [RedButton.Action]) {
        var phase = start
        var actions: [RedButton.Action] = []
        for e in events {
            let (next, out) = RedButton.next(phase, e)
            phase = next
            actions += out
        }
        return (phase, actions)
    }

    /// The happy path, end to end: appear, hover, press, release, shrink, gone.
    func testTheWholePressFiresTheHookExactlyOnceAndLeavesItPressed() {
        let (phase, actions) = run([.zoomDone, .hoverEnter, .mouseDown, .mouseUp, .shrinkDone])
        XCTAssertEqual(phase, .done)
        XCTAssertEqual(actions, [.highlightOn, .showPressedFrame, .click, .shrinkPressed, .end])
        XCTAssertEqual(actions.filter { $0 == .click }.count, 1)
    }

    /// The distinction the whole machine exists for: a click leaves it pressed,
    /// a timeout brings it back up. Sending the same last event to the two paths
    /// must NOT produce the same exit.
    func testATimeoutShrinksItUnpressedAndFiresNoHook() {
        let (phase, actions) = run([.zoomDone, .hoverEnter, .timeout, .shrinkDone])
        XCTAssertEqual(phase, .done)
        XCTAssertEqual(actions, [.highlightOn, .shrinkRaised, .end])
        XCTAssertFalse(actions.contains(.click))
    }

    /// Held down when the clock ran out: the finger was on it but the click never
    /// completed, so nothing fires and it still comes back up before leaving.
    func testATimeoutWhileHeldDownDoesNotCount() {
        let (_, actions) = run([.zoomDone, .hoverEnter, .mouseDown, .timeout, .shrinkDone])
        XCTAssertFalse(actions.contains(.click))
        XCTAssertTrue(actions.contains(.shrinkRaised))
    }

    /// Press, drag off, release — every other button on the machine cancels, and
    /// so does this one.
    func testAPressDraggedOffIsCancelled() {
        let (phase, actions) = run([.zoomDone, .hoverEnter, .mouseDown, .hoverExit, .mouseUp])
        XCTAssertEqual(phase, .idle, "a released press off the button is not a click")
        XCTAssertFalse(actions.contains(.click))
        XCTAssertEqual(actions, [.highlightOn, .showPressedFrame, .showRaisedFrame, .highlightOff])
    }

    func testHoverIsReversible() {
        let (phase, actions) = run([.zoomDone, .hoverEnter, .hoverExit, .hoverEnter])
        XCTAssertEqual(phase, .hover)
        XCTAssertEqual(actions, [.highlightOn, .highlightOff, .highlightOn])
    }

    /// Escape works from anywhere, including before the zoom has even finished —
    /// and from the shrink it short-circuits straight to the teardown rather than
    /// queueing a second one.
    func testEscapeEndsItFromEveryPhase() {
        for phase in [RedButton.Phase.zoomIn, .idle, .hover, .pressed] {
            let (next, actions) = RedButton.next(phase, .dismiss)
            XCTAssertEqual(next, .shrink, "\(phase) must be dismissable")
            XCTAssertEqual(actions, [.shrinkRaised])
        }
        XCTAssertEqual(RedButton.next(.shrink, .dismiss).0, .done)
        XCTAssertEqual(RedButton.next(.shrink, .dismiss).1, [.end])
    }

    /// The button is not clickable before it has finished arriving, and not
    /// clickable again after it has left. Both directions, because a stray
    /// `mouseUp` delivered during the shrink would otherwise fire the payoff a
    /// second time.
    func testItIsInertBeforeTheZoomEndsAndAfterItIsDone() {
        for event in [RedButton.Event.mouseDown, .mouseUp, .hoverEnter] {
            XCTAssertEqual(RedButton.next(.zoomIn, event).0, .zoomIn)
            XCTAssertTrue(RedButton.next(.zoomIn, event).1.isEmpty)
            XCTAssertEqual(RedButton.next(.done, event).0, .done)
            XCTAssertTrue(RedButton.next(.done, event).1.isEmpty)
            XCTAssertTrue(RedButton.next(.shrink, event).1.isEmpty)
        }
    }

    /// `.end` is what tears the tap and the hit panel down. It must be reachable
    /// from every phase, or a dismissed button leaves an invisible rectangle
    /// eating clicks in the middle of the screen.
    func testEveryPhaseCanReachTheTeardown() {
        for start in [RedButton.Phase.zoomIn, .idle, .hover, .pressed, .shrink] {
            let (phase, actions) = run([.dismiss, .shrinkDone], from: start)
            XCTAssertEqual(phase, .done, "\(start) never reaches .done")
            XCTAssertTrue(actions.contains(.end), "\(start) never tears down")
        }
    }

    // MARK: - The numbers

    /// Not a tautology: these four are what the effect promises the room, and a
    /// stray edit to any of them changes what Victor rehearsed. The deadline in
    /// particular is the self-termination rule for an effect with no clip to
    /// inherit one from.
    func testTheDecidedNumbers() {
        XCTAssertEqual(RedButton.heightFraction, 0.5)
        XCTAssertEqual(RedButton.zoomInDuration, 0.35)
        XCTAssertEqual(RedButton.shrinkDuration, 0.30)
        XCTAssertEqual(RedButton.maxLifetime, 20.0)
    }

    /// The asset is not in this repo, so the effect must degrade to a log line
    /// rather than to a crash. Checked here as the mapping being present while
    /// the file may not be.
    func testTheAssetIsNamedAndPairedWithTileSeven() {
        XCTAssertEqual(RedButton.assetName, "red_button.gif")
        XCTAssertEqual(RedButton.soundName, "07_animated_phone.mp3")
        XCTAssertEqual(SoundEffectMap.pressEffect(for: RedButton.soundName), "red-button")
        XCTAssertNil(SoundEffectMap.stopEffect(for: RedButton.soundName),
                     "the tablet's /sound/stopped must NOT take the button away — it outlives its clip")
    }
}
