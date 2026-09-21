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
