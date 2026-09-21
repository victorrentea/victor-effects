import XCTest
@testable import VictorEffects

/// 🔥 A whip crack makes the ⌘⌃Q mascot jump — *ca ars de bici*.
///
/// Two things can go wrong with it, and neither shows up until a room is
/// watching: the robot's head can leave through the top of the screen (the
/// overlay clips there, so a beheaded flinch reads as a broken effect), and a
/// crack can stop reaching the mascot at all because a second call site was
/// added next to `playCrack()` instead of to the funnel. One is geometry, one is
/// a convention — so one is asserted on the pure function and the other on the
/// source, the same way `SoundEffectMapDriftTests` guards the ⭐ promise.
final class PeekWhipJumpTests: XCTestCase {

    /// The aspects of the two shipped cut-outs (461×363 and 455×362). The frame
    /// is sized off the *height*, so these should barely matter — which is
    /// itself worth asserting, since a rise that depended on the aspect would
    /// mean the two mascots jump differently.
    private let aspects: [CGFloat] = [461.0 / 363.0, 455.0 / 362.0]

    /// Screens this actually runs on: the built-in retina, the projector, and a
    /// 4K to catch anything that only works at one scale.
    private let screens: [CGRect] = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),    // MacBook built-in
        CGRect(x: 0, y: 0, width: 1920, height: 1080),   // projector
        CGRect(x: 0, y: 0, width: 3456, height: 2234),   // 4K
    ]

    // MARK: - It stays on the screen

    func testTheJumpNeverPushesTheHeadOffTheTop() {
        for screen in screens {
            for aspect in aspects {
                let frame = EmojiAnimator.claudePeekFrame(in: screen, aspect: aspect)
                let rise = EmojiAnimator.peekWhipRise(frame: frame, in: screen)
                XCTAssertLessThanOrEqual(
                    frame.maxY + rise, screen.maxY + 0.001,
                    "at \(screen.size) the mascot jumps through the top edge — the overlay clips there"
                )
            }
        }
    }

    /// The clamp must not be what picks the number in normal use: if the chosen
    /// fraction had grown past the clearance, every screen would jump to exactly
    /// the top edge and the head would sit in the menu bar — legal, but not the
    /// effect anyone asked for.
    func testTheFractionFitsWithoutBeingClamped() {
        for screen in screens {
            for aspect in aspects {
                let frame = EmojiAnimator.claudePeekFrame(in: screen, aspect: aspect)
                let wanted = frame.height * EmojiAnimator.peekWhipJumpFraction
                XCTAssertEqual(
                    EmojiAnimator.peekWhipRise(frame: frame, in: screen), wanted, accuracy: 0.001,
                    "the clearance above the mascot no longer fits the jump — lower peekWhipJumpFraction "
                    + "or move claudePeekFrame down, do not rely on the clamp"
                )
            }
        }
    }

    /// The clamp is still the safety net it is there to be.
    func testARiseWithNoRoomIsClampedToTheRoomThereIs() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let flush = CGRect(x: 80, y: 600, width: 400, height: 480)   // top at the bezel
        XCTAssertEqual(EmojiAnimator.peekWhipRise(frame: flush, in: screen), 0,
                       "an icon already at the top edge cannot rise at all")

        let tenBelow = flush.offsetBy(dx: 0, dy: -10)
        XCTAssertEqual(EmojiAnimator.peekWhipRise(frame: tenBelow, in: screen), 10, accuracy: 0.001,
                       "with 10 pt overhead the jump is 10 pt, not the fraction")
    }

    // MARK: - It scales with the mascot

    /// The mascot doubled in size once already (21 Sep 2026, 21% → 42% of the
    /// screen height). A jump measured in points would have stayed the hop it
    /// was when the robot was half as tall.
    func testDoublingTheMascotDoublesTheJump() {
        let roomy = CGRect(x: 0, y: 0, width: 1920, height: 4000)
        let small = CGRect(x: 100, y: 100, width: 250, height: 200)
        let big = CGRect(x: 100, y: 100, width: 500, height: 400)
        XCTAssertEqual(
            EmojiAnimator.peekWhipRise(frame: big, in: roomy),
            EmojiAnimator.peekWhipRise(frame: small, in: roomy) * 2, accuracy: 0.001)
    }

    /// Both robots have to jump the same, or the effect would tell the room
    /// which costume is on duty.
    func testBothMascotsJumpTheSameHeight() {
        for screen in screens {
            let rises = aspects.map { aspect -> CGFloat in
                let frame = EmojiAnimator.claudePeekFrame(in: screen, aspect: aspect)
                return EmojiAnimator.peekWhipRise(frame: frame, in: screen)
            }
            XCTAssertEqual(rises[0], rises[1], accuracy: 0.001,
                           "Claude and Copilot must flinch identically — the frame is sized off the height")
        }
    }

    /// Big enough to see from the back of a room: at least 3% of the screen
    /// height. A flinch nobody can see is a flinch that did not happen.
    func testTheJumpIsVisibleFromTheBackOfTheRoom() {
        for screen in screens {
            let frame = EmojiAnimator.claudePeekFrame(in: screen, aspect: aspects[0])
            XCTAssertGreaterThan(
                EmojiAnimator.peekWhipRise(frame: frame, in: screen), screen.height * 0.03,
                "at \(screen.size) the jump is too small to read on a projector")
        }
    }

    // MARK: - It runs in every direction, and comes back

    /// The flinch stopped being one hop upwards on 2026-09-21: being burnt
    /// makes you run *away*, and away is not a direction you pick in advance.
    /// A route that only ever moves on `y` is the pogo stick this replaced.
    func testTheScamperMovesSideways() {
        for screen in screens {
            for aspect in aspects {
                let frame = EmojiAnimator.claudePeekFrame(in: screen, aspect: aspect)
                let path = EmojiAnimator.peekWhipPath(frame: frame, in: screen)
                XCTAssertGreaterThan(path.map { abs($0.x) }.max() ?? 0, frame.height * 0.1,
                                     "at \(screen.size) the mascot only jumps up and down again")
                XCTAssertGreaterThan(path.filter { $0.x > 0 }.count, 0, "he never goes right")
                XCTAssertGreaterThan(path.filter { $0.x < 0 }.count, 0, "he never goes left")
            }
        }
    }

    /// Four hops, not one: a single arc is a flinch, and what was asked for was
    /// somebody scrambling. Counted as the number of times he leaves the ground
    /// (every apex between two ground frames).
    func testHeTakesOffMoreThanOnce() {
        let apexes = EmojiAnimator.peekWhipHopShape.enumerated()
            .filter { $0.offset.isMultiple(of: 2) == false }
        XCTAssertGreaterThanOrEqual(apexes.count, 4,
                                    "one crack should launch him several times, not once")
        for (offset, point) in EmojiAnimator.peekWhipHopShape.enumerated() where offset.isMultiple(of: 2) {
            XCTAssertEqual(point.y, 0, accuracy: 0.0001,
                           "even entries are the ground — the timing functions depend on the alternation")
        }
        for (_, point) in apexes {
            XCTAssertGreaterThan(point.y, 0, "an apex at ground level is not a hop")
        }
    }

    /// However far he runs, he has to land on the pixel he left: the click
    /// target (`PeekHitPanel`) stays at the landed frame and does not chase him,
    /// and twenty cracks in a row must not walk him across the screen.
    func testHeLandsExactlyWhereHeTookOff() {
        XCTAssertEqual(EmojiAnimator.peekWhipHopShape.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(EmojiAnimator.peekWhipHopShape.last, CGPoint(x: 0, y: 0))
        for screen in screens {
            let frame = EmojiAnimator.claudePeekFrame(in: screen, aspect: aspects[0])
            let path = EmojiAnimator.peekWhipPath(frame: frame, in: screen)
            XCTAssertEqual(path.first, CGPoint(x: 0, y: 0))
            XCTAssertEqual(path.last, CGPoint(x: 0, y: 0))
        }
    }

    /// `keyTimes` and `values` are handed to the same `CAKeyframeAnimation`, and
    /// `timingFunctions` has to be one shorter than both. CoreAnimation does not
    /// complain about a mismatch — it silently plays something else.
    func testTheTimingLinesUpWithTheRoute() {
        let times = EmojiAnimator.peekWhipKeyTimes
        XCTAssertEqual(times.count, EmojiAnimator.peekWhipHopShape.count,
                       "one key time per point, or the hops land at the wrong moments")
        XCTAssertEqual(times.first, 0)
        XCTAssertEqual(times.last, 1)
        for (a, b) in zip(times, times.dropFirst()) {
            XCTAssertLessThan(a, b, "key times must climb, or a hop plays backwards")
        }
    }

    /// The apex constant is what is checked against the clearance overhead, so
    /// it has to stay the actual top of the route — a shape edited to go higher
    /// without touching the constant would clear the clamp's audit and then be
    /// cut off by the bezel.
    func testTheJumpFractionIsTheTopOfTheRoute() {
        XCTAssertEqual(EmojiAnimator.peekWhipHopShape.map(\.y).max() ?? 0,
                       EmojiAnimator.peekWhipJumpFraction, accuracy: 0.0001)
    }

    /// The whole route stays on the screen — this is the sideways version of
    /// "the head does not leave through the top".
    func testTheScamperStaysOnTheScreen() {
        for screen in screens {
            for aspect in aspects {
                let frame = EmojiAnimator.claudePeekFrame(in: screen, aspect: aspect)
                for hop in EmojiAnimator.peekWhipPath(frame: frame, in: screen) {
                    let moved = frame.offsetBy(dx: hop.x, dy: hop.y)
                    XCTAssertTrue(screen.insetBy(dx: -0.001, dy: -0.001).contains(moved),
                                  "at \(screen.size) the mascot runs off the screen: \(moved)")
                }
            }
        }
    }

    /// The left bezel is the tight side — `claudePeekFrame` insets him by only
    /// 4.5% of the width — so the leftward hop is the one most likely to start
    /// being decided by the clamp instead of by the shape. If it is, he stops
    /// bouncing off the same spot on every screen.
    func testTheLeftwardHopIsNotTheClampDoingTheWork() {
        let wanted = EmojiAnimator.peekWhipHopShape.map(\.x).min() ?? 0
        for screen in screens {
            for aspect in aspects {
                let frame = EmojiAnimator.claudePeekFrame(in: screen, aspect: aspect)
                let got = EmojiAnimator.peekWhipPath(frame: frame, in: screen).map(\.x).min() ?? 0
                XCTAssertEqual(got, wanted * frame.height, accuracy: 0.001,
                               "at \(screen.size) the left bezel is clipping the scamper — pull the "
                               + "leftmost hop in, do not rely on the clamp")
            }
        }
    }

    /// Both robots have to run the same route, or the effect would tell the
    /// room which costume is on duty.
    func testBothMascotsRunTheSameRoute() {
        for screen in screens {
            let routes = aspects.map { aspect -> [CGPoint] in
                EmojiAnimator.peekWhipPath(
                    frame: EmojiAnimator.claudePeekFrame(in: screen, aspect: aspect), in: screen)
            }
            XCTAssertEqual(routes[0], routes[1],
                           "Claude and Copilot must scramble identically — the route is sized off the height")
        }
    }

    /// The clamp is still the safety net it is there to be, on every side.
    func testAMascotWithNoRoomIsClampedToTheRoomThereIs() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let boxedIn = CGRect(x: 0, y: 600, width: 400, height: 480)   // left bezel, top bezel
        for hop in EmojiAnimator.peekWhipPath(frame: boxedIn, in: screen) {
            XCTAssertGreaterThanOrEqual(hop.x, 0, "nowhere to go left, so he does not go left")
            XCTAssertEqual(hop.y, 0, accuracy: 0.001, "nowhere to go up, so he does not go up")
        }
    }

    // MARK: - Every crack reaches it

    /// `WhipController` announces cracks through one funnel, `cracked()`, which
    /// plays the sound and then calls `onCrack`. Two call sites used to call
    /// `playCrack()` directly, and the whole point of the funnel is that a third
    /// one cannot quietly skip the second half.
    ///
    /// Reads the source rather than a copy of it, so the only way to make this
    /// pass is to make the real thing true.
    func testEveryCrackGoesThroughTheFunnel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VictorEffectsTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let swift = try String(
            contentsOf: root.appendingPathComponent("Sources/VictorEffects/WhipOverlay.swift"),
            encoding: .utf8)

        // Code lines only: the doc comment on `cracked()` names `playCrack()` on
        // purpose, and so may any future one.
        let calls = swift
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") }
            .filter { $0.contains("playCrack()") }

        XCTAssertEqual(
            calls, ["private func playCrack() {", "playCrack()"],
            "playCrack() is called from somewhere other than cracked() — that crack plays a sound but "
            + "never reaches onCrack, so the mascot does not flinch for it. Call cracked() instead."
        )

        XCTAssertTrue(swift.contains("onCrack?()"),
                      "cracked() no longer notifies onCrack — nothing listens to the whip any more")
    }
}
