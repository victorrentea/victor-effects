import XCTest
@testable import VictorEffects

/// The right-⌥ hold, asserted on the rule rather than on the keyboard.
///
/// Pressing the key and watching means synthesising input on a live machine, so
/// there is no way to do it here — and the dangerous failures are silent ones:
/// a rule that shows the panel on a right-⌥E, or one that leaves it up over the
/// app the user is typing into. Those are the tests.
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
        let (state, actions) = run([.rightOptionDown, .holdTimerFired])
        XCTAssertEqual(actions, [.armHoldTimer, .show])
        XCTAssertTrue(state.shownByHold)
    }

    func testReleasingHidesIt() {
        let (state, actions) = run([.rightOptionDown, .holdTimerFired, .rightOptionUp])
        XCTAssertEqual(actions, [.armHoldTimer, .show, .hide])
        XCTAssertFalse(state.shownByHold)
    }

    func testATapNeverShowsAnything() {
        // Down-up inside the 180 ms: the timer is cancelled and nothing is
        // shown. This is the difference between "hold for the board" and "a
        // soundboard flashes up every time you let go of ⌥".
        let (state, actions) = run([.rightOptionDown, .rightOptionUp])
        XCTAssertEqual(actions, [.armHoldTimer, .cancelHoldTimer])
        XCTAssertFalse(state.shownByHold)
        XCTAssertFalse(state.holdArmed)
    }

    func testATimerThatFiresAfterTheKeyWasReleasedDoesNothing() {
        // The timer is not always cancellable in time; the rule must be the
        // authority, not the dispatch queue.
        let (state, actions) = run([.rightOptionDown, .rightOptionUp, .holdTimerFired])
        XCTAssertEqual(actions, [.armHoldTimer, .cancelHoldTimer])
        XCTAssertFalse(state.shownByHold)
    }

    func testRightOptionEAccentIsNotAPanelRequest() {
        // right-⌥E: the modifier goes down, E follows before 180 ms. The panel
        // must disarm, and — since the tap never swallows — the front app still
        // gets its ´ dead key.
        let (state, actions) = run([.rightOptionDown, .keyWhileRightOption, .rightOptionUp])
        XCTAssertEqual(actions, [.armHoldTimer, .cancelHoldTimer])
        XCTAssertFalse(state.shownByHold)
    }

    func testTypingAShortcutWhileThePanelIsUpHidesIt() {
        // Held long enough to show the board, then ⌥N: get out of the way
        // rather than sit over the app receiving the ˜.
        let (state, actions) = run([.rightOptionDown, .holdTimerFired, .keyWhileRightOption])
        XCTAssertEqual(actions, [.armHoldTimer, .show, .hide])
        XCTAssertFalse(state.shownByHold)
    }

    func testAHiddenPanelIsNotHiddenTwice() {
        // A dead key plus its letter sends several key-downs while the
        // modifier is held. Only the first may produce a `.hide`.
        let (_, actions) = run([.rightOptionDown, .holdTimerFired,
                                .keyWhileRightOption, .keyWhileRightOption, .rightOptionUp])
        XCTAssertEqual(actions, [.armHoldTimer, .show, .hide])
    }

    func testKeyRepeatOnTheModifierDoesNotStackTimers() {
        let (_, actions) = run([.rightOptionDown, .rightOptionDown, .rightOptionDown])
        XCTAssertEqual(actions, [.armHoldTimer])
    }

    func testDisabledMeansTheKeyDoesNothingAtAll() {
        let off = Rule.State(enabled: false)
        let (state, actions) = run([.rightOptionDown, .holdTimerFired, .rightOptionUp], from: off)
        XCTAssertEqual(actions, [])
        XCTAssertFalse(state.shownByHold)
    }

    func testTheRuleOnlyEverListensToTheRightOptionKey() {
        // Not a rule test but the reason there is one: 61 is right ⌥, 58 is
        // left. The tap filters on 61 before any of this runs.
        XCTAssertEqual(EffectsHotkeyTap.VK_RIGHT_OPTION, 61)
    }

    func testTheHoldIsLongEnoughToBeDeliberate() {
        XCTAssertEqual(ThumbnailPanelController.holdDelay, 0.180, accuracy: 0.0001)
    }
}
