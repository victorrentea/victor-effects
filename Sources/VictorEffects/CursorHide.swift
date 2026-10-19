import AppKit

/// A cursor hide that can be released exactly once, by whichever teardown
/// path gets there first.
///
/// `NSCursor.hide()`/`unhide()` and `CGDisplayHideCursor`/`ShowCursor` are
/// **counted**, so a double release does not merely do nothing — it cancels
/// somebody else's hide (the 😱 fear face's, say, which hides the pointer for
/// its own reasons). The heartbeat has three ends that all have to be safe:
/// the follow timer noticing the effect is over, the capture completion
/// finding itself preempted, and an absolute backstop for when neither runs.
/// A box that can only be opened once is cheaper than three call sites
/// agreeing on who wins.
///
/// Born in the heartbeat; shared since 2026-10-20 with the 🔥 whip and the
/// 🙏 hands, which hide the pointer for as long as they are up (Victor:
/// *"whenever the whip or the praying man is displayed, the mouse should be
/// hidden"*).
///
/// Main thread only — the counters behind it are not thread-safe.
final class CursorHide {
    /// Hides issued and not yet undone: one from `init`, plus one per
    /// `reassert()`. `release()` undoes exactly this many.
    private var depth = 0
    private var rehideUntil: CFTimeInterval = 0
    private var nextRehideAt: CFTimeInterval = 0

    /// How close to a screen edge counts as "near the system UI".
    static let edgeBand: CGFloat = 100

    init() {
        // Lifts the "only while frontmost" restriction: our overlay floats
        // over whatever app Victor is actually in, so without this the real
        // arrow keeps showing over the beat.
        hide()
    }
    /// Hide ONCE MORE while already hidden. The screen edges are where the
    /// system UI lives (the menu bar, the auto-hidden Dock, hot corners), and
    /// the pointer touching one gives the real arrow back — the trick
    /// `ShareZoom` in victor-macos-addons learned first (2026-10-01).
    func reassert() {
        guard depth > 0 else { return }
        hide()
    }
    /// For a per-frame caller: re-hide at 4 Hz while the pointer is within
    /// `edgeBand` of an edge of `screen`, and for 2 s after it leaves — the
    /// magnifier's rule, for overlays that follow the pointer everywhere.
    func reassertNearEdge(pointer p: NSPoint, screen: NSRect) {
        let now = CACurrentMediaTime()
        let band = Self.edgeBand
        if p.x <= screen.minX + band || p.x >= screen.maxX - band
            || p.y <= screen.minY + band || p.y >= screen.maxY - band {
            rehideUntil = now + 2
        }
        if now < rehideUntil, now >= nextRehideAt {
            nextRehideAt = now + 0.25
            reassert()
        }
    }
    func release() {
        while depth > 0 {
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
            depth -= 1
        }
    }
    private func hide() {
        EmojiAnimator.armBackgroundCursorHiding()
        NSCursor.hide()
        CGDisplayHideCursor(CGMainDisplayID())
        depth += 1
    }
}
