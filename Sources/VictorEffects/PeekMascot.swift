import AppKit

/// Which robot leans in from the left on ⌘⌃Q.
///
/// The raw value is the bundle resource name, so a mascot is one thing rather
/// than a name plus a lookup table that can disagree with it.
enum PeekMascot: String, CaseIterable {
    case claude = "claude-icon"
    case copilot = "copilot-icon"

    /// The other one. A two-case enum is the whole reason the click is a
    /// *toggle* and not a menu: there is nothing to choose between.
    var flipped: PeekMascot { self == .claude ? .copilot : .claude }
}

/// Who waves on ⌘⌃Q, as pure functions over what is stored.
///
/// **It used to alternate press by press** — Claude, Copilot, Claude — which
/// made the mascot a coin toss: at any given press Victor could not say which
/// robot the room was about to see, and during a Claude course the wrong one
/// arrives half the time. So the rotation is gone (2026-09-10) and the key has
/// a *state* instead:
///
/// - **Every day starts as Claude.** The default is not "whatever was last
///   used" because the courses are mostly Claude courses; a day that opens on
///   Copilot would be a surprise inherited from a day that is over.
/// - **Clicking the mascot while it is on screen flips it**, and the flip is
///   sticky for the rest of that calendar day — a Copilot day is declared once
///   and stays declared, rather than being re-declared before every press.
/// - **Clicking again flips back.** The gesture is its own undo, which is what
///   makes it safe to try mid-session in front of a room.
///
/// Day-scoping is the same trick as `BreakCountries.savedToday()`: store the
/// pick *and* the `yyyy-MM-dd` it was made on, and treat a stamp that is not
/// today as nothing stored. No timer has to fire at midnight and no state has
/// to be cleaned up — a stale pick simply stops being true.
///
/// The functions here take the stored pair rather than reading `UserDefaults`
/// so the day rollover can be tested by passing a date instead of by waiting
/// for one; `PeekMascotStore` is the thin layer that actually persists.
enum PeekMascotChoice {
    /// What a day opens with, before anybody clicks anything.
    static let dayDefault: PeekMascot = .claude

    /// The local calendar day, `yyyy-MM-dd`, used to scope a pick to one day.
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// The mascot a stored pick means at `now` — the default whenever nothing
    /// is stored, the stamp belongs to another day, or the stored name is not a
    /// mascot any more (a rename must not leave the key showing nothing).
    static func resolve(stored: String?, storedDay: String?, now: Date) -> PeekMascot {
        guard let stored, let storedDay,
              storedDay == dayKey(now),
              let mascot = PeekMascot(rawValue: stored) else { return dayDefault }
        return mascot
    }

    /// Where a click lands: the other one, computed from what is showing rather
    /// than from what is stored, so a click on a *stale* pick flips away from
    /// the robot on screen instead of back onto it.
    static func flipped(stored: String?, storedDay: String?, now: Date) -> PeekMascot {
        resolve(stored: stored, storedDay: storedDay, now: now).flipped
    }
}

/// `PeekMascotChoice` with `UserDefaults` behind it.
///
/// Persisting rather than holding the pick in memory is deliberate: this app is
/// rebuilt and restarted several times an hour, and a choice that a `pkill`
/// undoes is not a choice that survives a course day.
enum PeekMascotStore {
    private static let kMascot = "ClaudePeek.mascot"
    private static let kDay = "ClaudePeek.mascot.day"

    private static func stored() -> (String?, String?) {
        let d = UserDefaults.standard
        return (d.string(forKey: kMascot), d.string(forKey: kDay))
    }

    /// Who waves on the next press.
    static func current(now: Date = Date()) -> PeekMascot {
        let (mascot, day) = stored()
        return PeekMascotChoice.resolve(stored: mascot, storedDay: day, now: now)
    }

    /// Flip, persist, and hand back who is on duty now.
    @discardableResult
    static func flip(now: Date = Date()) -> PeekMascot {
        let (mascot, day) = stored()
        let next = PeekMascotChoice.flipped(stored: mascot, storedDay: day, now: now)
        let d = UserDefaults.standard
        d.set(next.rawValue, forKey: kMascot)
        d.set(PeekMascotChoice.dayKey(now), forKey: kDay)
        return next
    }
}

/// The one clickable rectangle on an otherwise click-through overlay.
///
/// The desktop overlay (`OverlayPanel`) sets `ignoresMouseEvents = true` for
/// everything, which is what lets effects be drawn over a Mac somebody is still
/// working on. Flipping that flag while the mascot shows would make the *whole
/// screen* deaf for five seconds, so instead this is a second, tiny panel laid
/// exactly over the icon: a click-target the size of the thing being clicked.
///
/// It costs what it costs — for the mascot's ~5 s a click in that rectangle
/// does not reach the app underneath. That is affordable only because of where
/// the mascot lands: the top-left quarter is the **last** one
/// `TerminalTileLayout.fillOrder` hands out, so of the whole screen it is the
/// least likely to have anything under it worth clicking.
///
/// It is `.nonactivatingPanel` and never becomes key, so clicking the mascot
/// does not take focus off whatever Victor was typing in — the same requirement
/// the Break timer's panel has, and the reason the cursor is set imperatively
/// from a tracking area rather than only through `resetCursorRects`.
final class PeekHitPanel: NSPanel {
    private final class HitView: NSView {
        var onClick: (() -> Void)?

        // Cursor rectangles are AppKit's standard per-region hover cursor and
        // work with the window un-key; the tracking area's `cursorUpdate` is the
        // belt to that braces, because a borderless non-activating panel is
        // exactly the case where cursor rects are least reliable.
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

        override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }

        // Put the plain arrow back by hand: nothing else will, because the
        // panel is not the active app's key window and the mascot can also
        // vanish from under the pointer when its five seconds are up.
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

        override func mouseDown(with event: NSEvent) { onClick?() }
    }

    init(frame: NSRect, onClick: @escaping () -> Void) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        // Above the overlay it sits on: the overlay is at the maximum window
        // level, and a hit target under the thing it is a target for would
        // never see the click.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = HitView(frame: NSRect(origin: .zero, size: frame.size))
        view.onClick = onClick
        contentView = view
        setFrame(frame, display: false)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Take it down, restoring the pointer if it is still sitting on us — the
    /// hand cursor must not outlive the thing it was pointing at.
    func dismiss() {
        if frame.contains(NSEvent.mouseLocation) { NSCursor.arrow.set() }
        orderOut(nil)
    }
}
