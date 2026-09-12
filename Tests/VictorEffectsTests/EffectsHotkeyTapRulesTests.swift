import XCTest
@testable import VictorEffects

/// The tap itself needs Accessibility, a window server and a run loop, so the
/// rules were split out as a pure function. These are the assertions that
/// matter: a tap that swallows one key too many breaks typing system-wide, and
/// nobody notices from a unit test suite that only exercises the happy key.
final class EffectsHotkeyTapRulesTests: XCTestCase {
    private typealias Tap = EffectsHotkeyTap
    private let VK_W: CGKeyCode = 0x0D
    private let VK_RETURN: CGKeyCode = 0x24
    private let VK_KEYPAD_ENTER: CGKeyCode = 0x4C
    private let VK_A: CGKeyCode = 0x00

    func testControlWTogglesTheWhipAndIsSwallowed() {
        XCTAssertEqual(Tap.decideKey(keyCode: VK_W, flags: [.maskControl], whipShowing: false),
                       .swallowToggleWhip)
        // Also while it is up: ⌃W is the dismiss gesture too.
        XCTAssertEqual(Tap.decideKey(keyCode: VK_W, flags: [.maskControl], whipShowing: true),
                       .swallowToggleWhip)
    }

    func testCommandControlWIsLeftAlone() {
        // ⌘⌃W belongs to a dictation app's paste. The `!hasCmd` clause is the
        // only reason both can live on this keyboard, so it gets its own test.
        XCTAssertEqual(Tap.decideKey(keyCode: VK_W, flags: [.maskControl, .maskCommand], whipShowing: false),
                       .pass)
    }

    func testOtherModifiersOnWAreLeftAlone() {
        XCTAssertEqual(Tap.decideKey(keyCode: VK_W, flags: [.maskControl, .maskAlternate], whipShowing: false), .pass)
        XCTAssertEqual(Tap.decideKey(keyCode: VK_W, flags: [.maskControl, .maskShift], whipShowing: false), .pass)
        XCTAssertEqual(Tap.decideKey(keyCode: VK_W, flags: [.maskCommand], whipShowing: false), .pass)
        XCTAssertEqual(Tap.decideKey(keyCode: VK_W, flags: [], whipShowing: false), .pass)
    }

    func testReturnCracksOnlyWhileTheWhipIsShowing() {
        XCTAssertEqual(Tap.decideKey(keyCode: VK_RETURN, flags: [], whipShowing: true), .crack)
        XCTAssertEqual(Tap.decideKey(keyCode: VK_KEYPAD_ENTER, flags: [], whipShowing: true), .crack)
        // With the whip hidden, Return is just Return — the tap must be inert.
        XCTAssertEqual(Tap.decideKey(keyCode: VK_RETURN, flags: [], whipShowing: false), .pass)
        XCTAssertEqual(Tap.decideKey(keyCode: VK_KEYPAD_ENTER, flags: [], whipShowing: false), .pass)
    }

    func testACrackNeverSwallows() {
        // The Return that cracks the whip is usually also the Return submitting
        // the prompt being interrupted. `.crack` means "act AND pass through";
        // only `.swallowToggleWhip` eats an event.
        for showing in [true, false] {
            let d = Tap.decideKey(keyCode: VK_RETURN, flags: [], whipShowing: showing)
            XCTAssertNotEqual(d, .swallowToggleWhip)
        }
    }

    func testUnrelatedKeysPassThrough() {
        XCTAssertEqual(Tap.decideKey(keyCode: VK_A, flags: [.maskCommand], whipShowing: true), .pass)
        XCTAssertEqual(Tap.decideKey(keyCode: VK_A, flags: [.maskControl], whipShowing: true), .pass)
    }

    func testSideButtonsCrackOnlyWhileShowing() {
        XCTAssertEqual(Tap.decideMouse(button: 5, whipShowing: true), .crack)
        XCTAssertEqual(Tap.decideMouse(button: 6, whipShowing: true), .crack)
        XCTAssertEqual(Tap.decideMouse(button: 5, whipShowing: false), .pass)
        XCTAssertEqual(Tap.decideMouse(button: 6, whipShowing: false), .pass)
        // Button 4 is another app's push-to-talk; it must never be touched.
        XCTAssertEqual(Tap.decideMouse(button: 4, whipShowing: true), .pass)
        XCTAssertEqual(Tap.decideMouse(button: 2, whipShowing: true), .pass)
    }

    // MARK: - The panel modifier (right ⌘, alone)

    private static let VK_RIGHT_COMMAND: CGKeyCode = 54
    private static let VK_LEFT_COMMAND: CGKeyCode = 55
    private static let VK_RIGHT_OPTION: CGKeyCode = 61

    func testRightCommandKeycodeIsNotLeftCommand() {
        // 54 vs 55 is the whole difference between "hold right ⌘ for the panel"
        // and "every ⌘C opens a grid over the screen".
        XCTAssertEqual(EffectsHotkeyTap.VK_RIGHT_COMMAND, 54)
    }

    func testRightCommandAloneArmsThePanel() {
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_COMMAND,
                                          flags: [.maskCommand],
                                          rightCommandHeld: false), .rightCommandDown)
    }

    func testDroppingTheFlagReleasesIt() {
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_COMMAND,
                                          flags: [],
                                          rightCommandHeld: true), .rightCommandUp)
    }

    func testRightOptionNoLongerTriggersThePanel() {
        // The trigger spent a day on 61. Holding it must now be as uneventful
        // as holding any other key — nothing armed, nothing shown — so the
        // emoji cheat-sheet layers of the 💬 app get the key back.
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_OPTION,
                                          flags: [.maskAlternate],
                                          rightCommandHeld: false), .ignore)
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_OPTION,
                                          flags: [],
                                          rightCommandHeld: false), .ignore)
    }

    func testLeftCommandIsNeverTheTrigger() {
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_LEFT_COMMAND,
                                          flags: [.maskCommand],
                                          rightCommandHeld: false), .ignore)
    }

    func testCommandWithAnotherModifierIsSomebodyElsesShortcut() {
        // ⌃⌘, ⌘⇧ and ⌘⌥ are shortcut layers other apps own. None of them may
        // raise the soundboard.
        for extra: CGEventFlags in [.maskControl, .maskShift, .maskAlternate] {
            XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_COMMAND,
                                              flags: [.maskCommand, extra],
                                              rightCommandHeld: false), .ignore)
        }
    }

    func testAModifierJoiningAHeldCommandCancels() {
        // ⌘ first, ⇧ second: the user is reaching for ⌘⇧, not the panel.
        XCTAssertEqual(Tap.decideModifier(keyCode: 56,
                                          flags: [.maskCommand, .maskShift],
                                          rightCommandHeld: true), .cancel)
    }

    func testModifierTrafficWhileNothingIsHeldIsIgnored() {
        XCTAssertEqual(Tap.decideModifier(keyCode: 56,
                                          flags: [.maskShift],
                                          rightCommandHeld: false), .ignore)
    }

    func testKeyRepeatOnTheModifierIsNotASecondPress() {
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_COMMAND,
                                          flags: [.maskCommand],
                                          rightCommandHeld: true), .ignore)
    }

    // MARK: - 🎬 Right ⌥ as the second page

    private static let VK_LEFT_OPTION: CGKeyCode = 58

    /// `.maskAlternate` cannot say WHICH ⌥ — only the device-dependent bits can,
    /// and the whole feature is the difference between them.
    private func flags(_ base: CGEventFlags, device: UInt64) -> CGEventFlags {
        CGEventFlags(rawValue: base.rawValue | device)
    }
    private var rightOpt: UInt64 { Tap.DEVICE_RIGHT_OPTION }
    private var leftOpt: UInt64 { Tap.DEVICE_LEFT_OPTION }

    func testRightOptionUnderAHeldCommandIsThePageSwitch() {
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_OPTION,
                                          flags: flags([.maskCommand, .maskAlternate], device: rightOpt),
                                          rightCommandHeld: true,
                                          rightOptionHeld: false), .rightOptionDown)
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_OPTION,
                                          flags: [.maskCommand],
                                          rightCommandHeld: true,
                                          rightOptionHeld: true), .rightOptionUp)
    }

    func testRightOptionRepeatIsNotASecondPage() {
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_OPTION,
                                          flags: flags([.maskCommand, .maskAlternate], device: rightOpt),
                                          rightCommandHeld: true,
                                          rightOptionHeld: true), .ignore)
    }

    func testLeftOptionStillCancelsEvenWhereTheRightOneWouldNot() {
        // The one asymmetry worth a test of its own: 61 opens the videos, 58 is
        // half of ⌘⌥ and belongs to whoever else is listening.
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_LEFT_OPTION,
                                          flags: flags([.maskCommand, .maskAlternate], device: leftOpt),
                                          rightCommandHeld: true), .cancel)
        // …and a left ⌥ joining a right ⌥ that is already there cancels too:
        // the chord stopped being this feature's the moment it grew a third key.
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_OPTION,
                                          flags: flags([.maskCommand, .maskAlternate],
                                                       device: leftOpt | rightOpt),
                                          rightCommandHeld: true,
                                          rightOptionHeld: true), .cancel)
    }

    func testRightCommandArrivingSecondStillArms() {
        // Either order. ⌥ first, then ⌘ — the flags on the ⌘ event carry the
        // right-⌥ device bit, and `commandIsAlone` has to let that one through
        // while still refusing every other modifier.
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_COMMAND,
                                          flags: flags([.maskCommand, .maskAlternate], device: rightOpt),
                                          rightCommandHeld: false), .rightCommandDown)
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_COMMAND,
                                          flags: flags([.maskCommand, .maskAlternate], device: leftOpt),
                                          rightCommandHeld: false), .ignore)
    }

    func testAnAmbiguousOptionIsTreatedAsTheLeftOne() {
        // `.maskAlternate` with NEITHER device bit — a synthesised event, a
        // remapped key. The safe answer is the behaviour this feature already
        // had (⌘⌥ cancels), never a board appearing under somebody's chord.
        XCTAssertFalse(Tap.rightOptionOnly([.maskAlternate]))
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_COMMAND,
                                          flags: [.maskCommand, .maskAlternate],
                                          rightCommandHeld: false), .ignore)
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_OPTION,
                                          flags: [.maskCommand, .maskAlternate],
                                          rightCommandHeld: true), .cancel)
    }

    func testControlOrShiftStillCancelEvenAlongsideTheRightOption() {
        for extra: CGEventFlags in [.maskControl, .maskShift] {
            XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_COMMAND,
                                              flags: flags([.maskCommand, .maskAlternate, extra],
                                                           device: rightOpt),
                                              rightCommandHeld: false), .ignore)
        }
    }

    func testRightOptionWithoutCommandIsStillNobodysBusiness() {
        // Unchanged from before the second page existed, and the reason the
        // trigger moved off 61 in the first place.
        XCTAssertEqual(Tap.decideModifier(keyCode: Self.VK_RIGHT_OPTION,
                                          flags: flags([.maskAlternate], device: rightOpt),
                                          rightCommandHeld: false), .ignore)
    }
}
