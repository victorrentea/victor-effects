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

    func testRightCommandKeycodeIsNotLeftCommand() {
        // 54 vs 55 is the whole difference between "hold right ⌘ for the panel"
        // and "every ⌘C opens a grid over the screen".
        XCTAssertEqual(EffectsHotkeyTap.VK_RIGHT_COMMAND, 54)
    }
}
