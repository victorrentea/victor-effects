import AppKit

/// The window the grid lives in.
///
/// A non-activating `NSPanel` because the gesture is "hold a modifier and
/// click": the app the user is presenting from must keep its focus, its
/// selection and its caret while the panel is up and after a tile is pressed.
/// That rules out anything that can become key.
final class ThumbnailPanel: NSPanel {
    let grid = ThumbnailGridView()

    /// The slide in from the right edge of the screen. Fast on purpose: the
    /// gesture is a hold, so every millisecond of animation is a millisecond
    /// the board is not yet readable.
    static let slideInDuration: TimeInterval = 0.20
    /// Shorter going out — an exit nobody is waiting for.
    static let slideOutDuration: TimeInterval = 0.12

    /// Bumped by every show and every hide. A slide-out completion that finds a
    /// newer generation has been overtaken by a show and must NOT order the
    /// window out: releasing and re-holding the key faster than 120 ms is
    /// exactly how a panel ends up invisible but "visible".
    private var slideGeneration = 0

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

    /// Show at `frame`, sliding in from `offscreenX` (the screen's right edge).
    ///
    /// The window is parked off to the right **at its final size** and only its
    /// origin is animated: the content view never resizes, so 91 tiles are laid
    /// out once instead of on every frame of the slide.
    func show(at frame: NSRect, slidingFrom offscreenX: CGFloat) {
        slideGeneration += 1

        setFrame(NSRect(x: offscreenX, y: frame.minY,
                        width: frame.width, height: frame.height), display: false)
        grid.frame = contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
        grid.needsLayout = true
        grid.layoutSubtreeIfNeeded()

        // Fade the first frames in as well as slide them: on a multi-screen
        // desk the parking spot is over the neighbouring screen, and a board
        // that flashes there before it flies in is worse than no animation.
        alphaValue = 0
        // `orderFrontRegardless`, not `makeKeyAndOrderFront`: the second would
        // steal focus from the app being presented even from a panel that
        // refuses key status, by activating this app.
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.slideInDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
            animator().alphaValue = 1
        }
    }

    /// Slide back out to `offscreenX` and then order out.
    ///
    /// Interrupting a slide-in is the normal case — the key is released before
    /// the board has landed — so the animation starts from wherever the window
    /// visually is, not from the frame it was aiming at.
    func slideOut(to offscreenX: CGFloat) {
        guard isVisible else { hideNow(); return }
        slideGeneration += 1
        let generation = slideGeneration

        var out = frame
        out.origin.x = offscreenX

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.slideOutDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(out, display: false)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.finishSlideOut(generation)
        })

        // Belt and braces. A completion handler that never arrives would leave
        // a transparent, unreachable panel parked off-screen and `isVisible`
        // answering true for the rest of the session.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideOutDuration + 0.25) {
            [weak self] in self?.finishSlideOut(generation)
        }
    }

    private func finishSlideOut(_ generation: Int) {
        guard slideGeneration == generation else { return }  // a show overtook us
        orderOut(nil)
        alphaValue = 1
        // The board usually disappears while the mouse is still on it (the key
        // was released), and a window ordering out does not owe the view a
        // `mouseExited`. Without this the pointing hand outlives the panel.
        grid.releaseCursor()
    }

    /// Instant, un-animated. The panic path: the feature was switched off, or
    /// the app is going away.
    func hideNow() {
        slideGeneration += 1
        orderOut(nil)
        alphaValue = 1
        grid.releaseCursor()
    }
}
