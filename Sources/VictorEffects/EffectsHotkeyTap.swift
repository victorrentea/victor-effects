import AppKit
import Foundation

/// One `CGEventTap` for every key and button this app listens to.
///
/// One and not three, because a tap is a shared, fragile resource: macOS
/// disables it on timeout and *something* has to turn it back on, and three taps
/// would mean three re-enable paths and three Accessibility failures to explain.
///
/// It needs **Accessibility**, because rule 1 swallows its key. The other rules
/// would be happy with a listen-only tap.
final class EffectsHotkeyTap {
    // Keycodes. `kVK_*` equivalents, spelled out so the rules read as rules.
    private static let VK_W: CGKeyCode = 0x0D
    private static let VK_RETURN: CGKeyCode = 0x24        // Return
    private static let VK_KEYPAD_ENTER: CGKeyCode = 0x4C  // Enter (keypad / Fn-Return)
    /// Right ⌥. Left ⌥ is 58 and is deliberately NOT matched: the left key is
    /// the one every ⌥-shortcut and every ⌥-accent is typed with.
    static let VK_RIGHT_OPTION: CGKeyCode = 61

    private static let MOUSE_BUTTON_6: Int64 = 5  // physical "button 6"
    private static let MOUSE_BUTTON_7: Int64 = 6  // physical "button 7"

    /// What a key/button event means here. Pure, so the rules can be tested
    /// without an event tap, a permission grant or a window server.
    enum Decision: Equatable {
        /// ⌃W — toggle the whip and **eat the key** (it must not reach the app
        /// underneath, where it would delete a word).
        case swallowToggleWhip
        /// Crack the whip, and let the event continue on its way.
        case crack
        /// Not ours.
        case pass
    }

    /// The whole hotkey contract in one function.
    ///
    /// - ⌃W with no other modifier → toggle the whip, swallowed. ⌘⌃W is left
    ///   alone on purpose: it belongs to a dictation app, and the `!hasCmd`
    ///   clause is the only reason both can coexist.
    /// - While the whip is up, Return / keypad Enter and mouse buttons 6/7 crack
    ///   it and still go through. Return especially: the key that cracks the
    ///   whip is usually also the key submitting the prompt.
    static func decideKey(keyCode: CGKeyCode, flags: CGEventFlags, whipShowing: Bool) -> Decision {
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasOpt = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)

        if keyCode == VK_W && hasCtrl && !hasCmd && !hasOpt && !hasShift {
            return .swallowToggleWhip
        }
        if whipShowing && (keyCode == VK_RETURN || keyCode == VK_KEYPAD_ENTER) {
            return .crack
        }
        return .pass
    }

    /// What a `.flagsChanged` event means for the panel.
    ///
    /// Separate from `decideKey` because modifiers are not keys: there is no
    /// "down" field, only a flag that is either still set or no longer set, and
    /// the interesting question — *is right ⌥ the only thing being held* — is
    /// answered by the flags of a completely different key's event.
    enum ModifierDecision: Equatable {
        /// Right ⌥ went down **alone**: arm the hold.
        case rightOptionDown
        /// Right ⌥ came back up.
        case rightOptionUp
        /// Another modifier joined while right ⌥ was held (⌃⌥, ⌥⇧, ⌘⌥ …).
        /// Same meaning as a letter key: this is a shortcut, not the panel.
        case cancel
        /// Not ours.
        case ignore
    }

    /// `⌥ alone` means ⌥ and nothing else from the shortcut-forming trio.
    ///
    /// Caps lock and fn are deliberately not in the set: caps lock is a latch
    /// somebody may be sitting on for an hour, and neither of them is a
    /// modifier a ⌥-shortcut is built out of.
    private static func optionIsAlone(_ flags: CGEventFlags) -> Bool {
        !flags.contains(.maskCommand)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskShift)
    }

    static func decideModifier(keyCode: CGKeyCode,
                               flags: CGEventFlags,
                               rightOptionHeld: Bool) -> ModifierDecision {
        guard keyCode == VK_RIGHT_OPTION else {
            // Any *other* modifier moving while right ⌥ is down: ⌃⌥, ⌥⇧ and
            // friends belong to whatever else is listening (the emoji layers in
            // the 💬 app among them), so the panel steps aside.
            return rightOptionHeld ? .cancel : .ignore
        }
        let down = flags.contains(.maskAlternate)
        if down {
            guard !rightOptionHeld else { return .ignore }   // key repeat
            return optionIsAlone(flags) ? .rightOptionDown : .ignore
        }
        return rightOptionHeld ? .rightOptionUp : .ignore
    }

    static func decideMouse(button: Int64, whipShowing: Bool) -> Decision {
        if whipShowing && (button == MOUSE_BUTTON_6 || button == MOUSE_BUTTON_7) {
            return .crack
        }
        return .pass
    }

    // MARK: - Wiring

    var onToggleWhip: (() -> Void)?
    var onCrack: (() -> Void)?
    var whipShowing: () -> Bool = { false }

    /// Right-⌥ held down / released, for the thumbnail panel (WI-4).
    ///
    /// A closure and not a hardcoded call because the panel is a separate work
    /// item and this tap is the only place that can see the key. The default is
    /// a no-op, and the rule NEVER swallows: ⌥-accents (right-⌥E, right-⌥N …)
    /// must keep reaching the front app whether or not something is listening.
    var onRightOption: ((Bool) -> Void)?
    /// A key was pressed while right ⌥ is held — the user is typing an accent
    /// or a shortcut, not asking for the panel.
    var onKeyWhileRightOption: (() -> Void)?

    private var tapPort: CFMachPort?
    private var rightOptionHeld = false
    var isActive: Bool { tapPort != nil }

    /// Installs the tap. Returns false when Accessibility is not granted (or the
    /// tap could not be created) — the caller retries and the menu says so.
    @discardableResult
    func start() -> Bool {
        guard tapPort == nil else { return true }
        guard AXIsProcessTrusted() else {
            effectsInfo("⚠️ Accessibility not granted — ⌃W and the right-⌥ panel are off "
                + "(System Settings → Privacy & Security → Accessibility). The menu rows still work.")
            return false
        }

        let eventsOfInterest: CGEventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: effectsTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            effectsError("EffectsHotkeyTap: could not create the event tap despite being trusted")
            return false
        }
        tapPort = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "EffectsHotkeyTap"
        thread.start()
        effectsInfo("⌨️ Hotkey tap installed (⌃W whip, Return/buttons 6-7 crack, right ⌥ panel)")
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap that took too long in a callback once, as a
        // warning. Turning it back on here is the difference between "the whip
        // stopped working after a heavy effect" and a tap that survives the day.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tapPort { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let passThrough = Unmanaged.passUnretained(event)

        switch type {
        case .flagsChanged:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            switch Self.decideModifier(keyCode: keyCode,
                                       flags: event.flags,
                                       rightOptionHeld: rightOptionHeld) {
            case .rightOptionDown:
                rightOptionHeld = true
                DispatchQueue.main.async { [weak self] in self?.onRightOption?(true) }
            case .rightOptionUp:
                rightOptionHeld = false
                DispatchQueue.main.async { [weak self] in self?.onRightOption?(false) }
            case .cancel:
                DispatchQueue.main.async { [weak self] in self?.onKeyWhileRightOption?() }
            case .ignore:
                break
            }
            return passThrough

        case .keyDown:
            if rightOptionHeld {
                DispatchQueue.main.async { [weak self] in self?.onKeyWhileRightOption?() }
            }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            switch Self.decideKey(keyCode: keyCode, flags: event.flags, whipShowing: whipShowing()) {
            case .swallowToggleWhip:
                DispatchQueue.main.async { [weak self] in self?.onToggleWhip?() }
                return nil
            case .crack:
                DispatchQueue.main.async { [weak self] in self?.onCrack?() }
                return passThrough
            case .pass:
                return passThrough
            }

        case .otherMouseDown:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            if Self.decideMouse(button: button, whipShowing: whipShowing()) == .crack {
                DispatchQueue.main.async { [weak self] in self?.onCrack?() }
            }
            return passThrough

        default:
            return passThrough
        }
    }
}

private func effectsTapCallback(proxy: CGEventTapProxy,
                                type: CGEventType,
                                event: CGEvent,
                                userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EffectsHotkeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
