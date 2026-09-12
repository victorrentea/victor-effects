import XCTest
@testable import VictorEffects

/// The right-⌘ hold, asserted on the rule rather than on the keyboard.
///
/// Pressing the key and watching means synthesising input on a live machine, so
/// there is no way to do it here — and the dangerous failures are silent ones:
/// a rule that shows the panel on a right-⌘C, or one that leaves it up over the
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
        let (state, actions) = run([.rightCommandDown, .holdTimerFired])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.effects)])
        XCTAssertTrue(state.shownByHold)
    }

    func testReleasingHidesIt() {
        let (state, actions) = run([.rightCommandDown, .holdTimerFired, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.effects), .hide])
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

    func testRightCommandCopyIsNotAPanelRequest() {
        // right-⌘C: the modifier goes down, C follows before 180 ms. The panel
        // must disarm, and — since the tap never swallows — the front app still
        // gets its copy.
        let (state, actions) = run([.rightCommandDown, .keyWhileRightCommand, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .cancelHoldTimer])
        XCTAssertFalse(state.shownByHold)
    }

    func testTypingAShortcutWhileThePanelIsUpHidesIt() {
        // Held long enough to show the board, then ⌘V: get out of the way
        // rather than sit over the app receiving the paste.
        let (state, actions) = run([.rightCommandDown, .holdTimerFired, .keyWhileRightCommand])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.effects), .hide])
        XCTAssertFalse(state.shownByHold)
    }

    func testAHiddenPanelIsNotHiddenTwice() {
        // A held shortcut sends several key-downs while the modifier is
        // held. Only the first may produce a `.hide`.
        let (_, actions) = run([.rightCommandDown, .holdTimerFired,
                                .keyWhileRightCommand, .keyWhileRightCommand, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.effects), .hide])
    }

    func testKeyRepeatOnTheModifierDoesNotStackTimers() {
        let (_, actions) = run([.rightCommandDown, .rightCommandDown, .rightCommandDown])
        XCTAssertEqual(actions, [.armHoldTimer])
    }

    func testTheRuleOnlyEverListensToTheRightCommandKey() {
        // Not a rule test but the reason there is one: 54 is right ⌘, 55 is
        // left. The tap filters on 54 before any of this runs.
        XCTAssertEqual(EffectsHotkeyTap.VK_RIGHT_COMMAND, 54)
    }

    func testTheHoldIsLongEnoughToBeDeliberate() {
        XCTAssertEqual(ThumbnailPanelController.holdDelay, 0.180, accuracy: 0.0001)
    }

    // MARK: - 🎬 The second page (right ⌘ + right ⇧)

    func testShiftBeforeTheTimerShowsTheVideosStraightAway() {
        // ⌘ down, ⇧ joins at 90 ms, the timer fires at 180: the panel must
        // appear ALREADY on page 2. Showing the soundboard first and swapping a
        // frame later is the flicker this ordering exists to avoid.
        let (state, actions) = run([.rightCommandDown, .rightShiftDown, .holdTimerFired])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.videos)])
        XCTAssertEqual(state.page, .videos)
    }

    func testShiftAfterThePanelIsUpSwapsTheContentInPlace() {
        // No `.hide` and no second `.show` anywhere in here: the board is up
        // under a key that is still held, and it changes its mind rather than
        // leaving and coming back.
        let (state, actions) = run([.rightCommandDown, .holdTimerFired, .rightShiftDown])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.effects), .setPage(.videos)])
        XCTAssertEqual(state.page, .videos)
    }

    func testTogglingShiftTogglesThePageBothWays() {
        let (state, actions) = run([.rightCommandDown, .holdTimerFired,
                                    .rightShiftDown, .rightShiftUp, .rightShiftDown])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.effects),
                                 .setPage(.videos), .setPage(.effects), .setPage(.videos)])
        XCTAssertEqual(state.page, .videos)
    }

    func testShiftKeyRepeatDoesNotRepaintThePage() {
        // A held modifier can deliver more than one edge; only a real change of
        // page may cost a rebuild of eighteen tiles.
        let (_, actions) = run([.rightCommandDown, .holdTimerFired,
                                .rightShiftDown, .rightShiftDown, .rightShiftDown])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.effects), .setPage(.videos)])
    }

    func testShiftOnItsOwnDoesNothingAtAll() {
        // Right ⇧ with no right ⌘ under it is just a capital letter. The rule
        // may not so much as remember it.
        let (state, actions) = run([.rightShiftDown, .rightShiftUp])
        XCTAssertEqual(actions, [])
        XCTAssertEqual(state.page, .effects)
        XCTAssertFalse(state.shownByHold)
    }

    func testReleasingTheCommandEndsTheVideoPageToo() {
        // One hide, and the next hold starts on the soundboard: ⇧ is held, not
        // latched, so the page must not outlive the gesture that chose it.
        let (state, actions) = run([.rightCommandDown, .rightShiftDown,
                                    .holdTimerFired, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.videos), .hide])
        XCTAssertEqual(state.page, .effects)

        let (again, _) = run([.rightCommandDown, .holdTimerFired], from: state)
        XCTAssertEqual(again.page, .effects)
    }

    func testATapOnBothKeysStillShowsNothing() {
        let (state, actions) = run([.rightCommandDown, .rightShiftDown, .rightCommandUp])
        XCTAssertEqual(actions, [.armHoldTimer, .cancelHoldTimer])
        XCTAssertFalse(state.shownByHold)
        XCTAssertEqual(state.page, .effects)
    }

    func testAShortcutTypedOnTheVideoPageStillGetsOutOfTheWay() {
        // ⌘⇧ with a letter is somebody else's chord even while page 2 is up.
        let (state, actions) = run([.rightCommandDown, .rightShiftDown,
                                    .holdTimerFired, .keyWhileRightCommand])
        XCTAssertEqual(actions, [.armHoldTimer, .show(.videos), .hide])
        XCTAssertFalse(state.shownByHold)
        XCTAssertEqual(state.page, .effects)
    }

    /// The two `enabled: false` cases that used to live here went with the
    /// checkbox they asserted (`ThumbnailPanel.enabled`): with the panel always
    /// armed there is no off state left for the rule to have, and a test kept
    /// alive by a field nobody can set is a test of its own scaffolding.
}
