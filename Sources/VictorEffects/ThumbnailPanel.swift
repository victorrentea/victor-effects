import AppKit

/// The window the grid lives in.
///
/// A non-activating `NSPanel` because the gesture is "hold a modifier and
/// click": the app the user is presenting from must keep its focus, its
/// selection and its caret while the panel is up and after a tile is pressed.
/// That rules out anything that can become key.
final class ThumbnailPanel: NSPanel {
    let grid = ThumbnailGridView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Mouse events are the point, unlike the effects overlay which is
        // click-through.
        ignoresMouseEvents = false
        // One below the effects overlay: a confetti burst fired from a tile
        // should still land on top of the panel that fired it.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let content = NSView(frame: contentRect(forFrameRect: frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.94).cgColor
        content.layer?.cornerRadius = 18
        content.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        contentView = content

        grid.autoresizingMask = [.width, .height]
        grid.frame = content.bounds
        content.addSubview(grid)
    }

    /// Never key, never main — see the class note. Overridden rather than set,
    /// because `NSPanel` decides this by asking, not by reading a stored flag.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(at frame: NSRect) {
        setFrame(frame, display: true)
        grid.frame = contentView?.bounds ?? frame
        grid.needsLayout = true
        // `orderFrontRegardless`, not `makeKeyAndOrderFront`: the second would
        // steal focus from the app being presented even from a panel that
        // refuses key status, by activating this app.
        orderFrontRegardless()
    }

    func hideNow() {
        orderOut(nil)
    }
}
