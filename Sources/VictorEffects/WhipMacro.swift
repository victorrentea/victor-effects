import AppKit
import CoreGraphics
import Foundation

/// "Whip Claude" macro — OpenWhip's `sendMacro()` ported to native Swift.
///
/// On a whip *click* we send an interrupt (Ctrl+C) to the focused terminal,
/// then — after a short delay so the interrupt registers — type one of the
/// scolding phrases and press Return. This mirrors OpenWhip exactly but uses
/// CGEvents instead of an `osascript` subprocess (no process spawn, layout-
/// independent typing via `keyboardSetUnicodeString`).
enum WhipMacro {

    /// The scolding phrases, ported verbatim from OpenWhip `main.js` `sendMacro()`.
    /// (The README advertises "5 encouraging messages"; the source actually ships
    /// these 7, weighted toward "FASTER".)
    static let phrases: [String] = [
        "FASTER",
        "FASTER",
        "FASTER",
        "GO FASTER",
        "Faster CLANKER",
        "Work FASTER",
        "Speed it up clanker",
    ]

    /// Pick a random phrase. Pure; always returns a member of `phrases`.
    static func randomPhrase() -> String {
        phrases.randomElement() ?? "FASTER"
    }

    private static let keyC: CGKeyCode = 0x08       // kVK_ANSI_C
    private static let keyReturn: CGKeyCode = 0x24  // kVK_Return

    /// Delay between the Ctrl+C interrupt and typing the phrase, matching the
    /// 300ms the original waits so Claude's interrupt lands before a new prompt.
    static let interruptToTypeDelay: TimeInterval = 0.30

    /// Fire the whip macro at the currently-focused app: Ctrl+C immediately, then
    /// after `interruptToTypeDelay` type a random phrase + Return. Optionally
    /// re-activates `app` first as a safety net so the keystrokes land in the
    /// intended terminal. Manages its own async dispatch; safe from any thread.
    static func sendCrackMacro(reactivating app: NSRunningApplication? = nil,
                               phrase: String? = nil) {
        let chosen = phrase ?? randomPhrase()
        let fire = {
            // The whip panel is non-activating, so focus normally stays on the
            // terminal; re-activate as a belt-and-suspenders.
            app?.activate(options: .activateIgnoringOtherApps)
            postKey(keyC, flags: .maskControl)  // Ctrl+C interrupt
            DispatchQueue.global().asyncAfter(deadline: .now() + interruptToTypeDelay) {
                typeString(chosen)
                postKey(keyReturn)
            }
        }
        if Thread.isMainThread {
            DispatchQueue.global().async(execute: fire)
        } else {
            fire()
        }
    }

    // MARK: - CGEvent primitives

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Type arbitrary text via Unicode key events — layout-independent, no
    /// per-character keycode mapping or shift bookkeeping needed.
    static func typeString(_ s: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for scalar in s.unicodeScalars {
            let utf16 = Array(String(scalar).utf16)
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { continue }
            utf16.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
