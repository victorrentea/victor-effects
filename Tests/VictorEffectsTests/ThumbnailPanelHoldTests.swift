import XCTest
@testable import VictorEffects

/// The right-⌘ hold, asserted on the rule rather than on the keyboard.
///
/// The live gesture needs an Accessibility grant this Mac does not have yet, so
/// there is no way to press the key and watch — and the dangerous failures here
/// are silent ones: a rule that shows the panel on a ⌘C, or one that leaves it
/// up over the app the user is typing into. Those are the tests.
final class ThumbnailPanelHoldTests: XCTestCase {
    private typealias Rule = ThumbnailPanelController.PanelHoldRule

    private func run(_ events: [Rule.Event],
                     from start: Rule.State = Rule.State()) -> (Rule.State, [Rule.Action]) {
        var state = start
        var actions: [Rule.Action] = []
        for event in events { actions += Rule.apply(event, to: &state) }
        return (state, actions)
    }

    func testHoldingTheKeyLongEnoughShowsThePanel() {
        let (state, actions) = run([.rightCommandDown, .holdTimerFired])
        XCTAssertEqual(actions, [.armHoldTimer, .show])
        XCTAssertTrue(state.shownByHold)
    }

    func testReleasingHidesIt() {
        let (state, actions) = run([.rightCommandDown, .holdTimerFired, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .show, .hide])
        XCTAssertFalse(state.shownByHold)
    }

    func testATapNeverShowsAnything() {
        // Down-up inside the 180 ms: the timer is cancelled and nothing is
        // shown. This is the difference between "hold for the board" and "a
        // soundboard flashes up every time you let go of ⌘".
        let (state, actions) = run([.rightCommandDown, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .cancelHoldTimer])
        XCTAssertFalse(state.shownByHold)
        XCTAssertFalse(state.holdArmed)
    }

    func testATimerThatFiresAfterTheKeyWasReleasedDoesNothing() {
        // The timer is not always cancellable in time; the rule must be the
        // authority, not the dispatch queue.
        let (state, actions) = run([.rightCommandDown, .rightCommandUp, .holdTimerFired])
        XCTAssertEqual(actions, [.armHoldTimer, .cancelHoldTimer])
        XCTAssertFalse(state.shownByHold)
    }

    func testRightCommandCShortcutIsNotAPanelRequest() {
        // ⌘C with the right hand: the key goes down, C follows before 180 ms.
        // The panel must disarm, and — since the tap never swallows — the copy
        // still happens in the front app.
        let (state, actions) = run([.rightCommandDown, .keyWhileRightCommand, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .cancelHoldTimer])
        XCTAssertFalse(state.shownByHold)
    }

    func testTypingAShortcutWhileThePanelIsUpHidesIt() {
        // Held long enough to show the board, then ⌘V: get out of the way
        // rather than sit over the app receiving the paste.
        let (state, actions) = run([.rightCommandDown, .holdTimerFired, .keyWhileRightCommand])
        XCTAssertEqual(actions, [.armHoldTimer, .show, .hide])
        XCTAssertFalse(state.shownByHold)
    }

    func testAHiddenPanelIsNotHiddenTwice() {
        // ⌘⇧V and friends send several key-downs while the modifier is held.
        // Only the first may produce a `.hide`.
        let (_, actions) = run([.rightCommandDown, .holdTimerFired,
                                .keyWhileRightCommand, .keyWhileRightCommand, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .show, .hide])
    }

    func testKeyRepeatOnTheModifierDoesNotStackTimers() {
        let (_, actions) = run([.rightCommandDown, .rightCommandDown, .rightCommandDown])
        XCTAssertEqual(actions, [.armHoldTimer])
    }

    func testDisabledMeansTheKeyDoesNothingAtAll() {
        let off = Rule.State(enabled: false)
        let (state, actions) = run([.rightCommandDown, .holdTimerFired, .rightCommandUp], from: off)
        XCTAssertEqual(actions, [])
        XCTAssertFalse(state.shownByHold)
    }

    func testTheRuleOnlyEverListensToTheRightCommandKey() {
        // Not a rule test but the reason there is one: 54 is right ⌘, 55 is
        // left. The tap filters on 54 before any of this runs.
        XCTAssertEqual(EffectsHotkeyTap.VK_RIGHT_COMMAND, 54)
    }

    func testTheHoldIsLongEnoughToBeDeliberate() {
        XCTAssertEqual(ThumbnailPanelController.holdDelay, 0.180, accuracy: 0.0001)
    }
}
