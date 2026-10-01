import AppKit

/// Where the room **sees** the cursor — the point an effect drawn "at the cursor"
/// has to be drawn at.
///
/// Normally that is the real pointer. While Victor zooms with **⌥⇧+scroll**
/// (`ShareZoom` in victor-macos-addons — a magnifier done in a window so a Zoom
/// share carries it) it is not: that zoom pans only when the pointer pushes an
/// edge, hides the real cursor and draws a magnified one where the pointer's
/// desktop point appears on the glass. The 💓 heartbeat's bulge, the 🔍 glass and
/// the whip were left beside it, following an invisible pointer.
///
/// The addons app posts the drawn cursor's position as a distributed notification
/// (global Cocoa points, y up — the same space as `NSEvent.mouseLocation`), ~30 Hz
/// while it moves and every 0.5 s while it rests, and an empty one when the zoom
/// ends. A position older than `staleAfter` is ignored, so a crashed or quit addons
/// app costs one and a half seconds of misplacement, never a pinned cursor.
///
/// Nothing else about the effects changes: our overlay is at the maximum window
/// level, above that zoom's window, so effects are drawn unmagnified over the
/// zoomed picture — which already looks the way they look unzoomed. `ScreenZoom`
/// is untouched too; it answers for macOS's own magnifier only.
///
/// Thread-safe: some readers sit on event-tap threads.
enum VisibleCursor {
    static let notification = Notification.Name("ro.victorrentea.share-zoom.cursor")
    static let staleAfter: CFTimeInterval = 1.5

    private static let lock = NSLock()
    private static var drawn: (point: NSPoint, at: CFAbsoluteTime)?
    private static var observer: NSObjectProtocol?

    /// Use this instead of `NSEvent.mouseLocation` wherever something is drawn at
    /// the cursor. Leave `NSEvent.mouseLocation` where the question is about the
    /// real pointer (hover and hit-testing in our own windows).
    static var location: NSPoint {
        lock.lock()
        let d = drawn
        lock.unlock()
        return resolve(drawn: d, now: CFAbsoluteTimeGetCurrent(), real: NSEvent.mouseLocation)
    }

    /// The rule, pure for the tests.
    static func resolve(drawn: (point: NSPoint, at: CFAbsoluteTime)?, now: CFAbsoluteTime,
                        real: NSPoint) -> NSPoint {
        guard let drawn, now - drawn.at < staleAfter else { return real }
        return drawn.point
    }

    static func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: notification, object: nil, queue: nil
        ) { note in
            let point: NSPoint?
            if let x = note.userInfo?["x"] as? Double, let y = note.userInfo?["y"] as? Double {
                point = NSPoint(x: x, y: y)
            } else {
                point = nil
            }
            lock.lock()
            drawn = point.map { ($0, CFAbsoluteTimeGetCurrent()) }
            lock.unlock()
        }
    }
}
