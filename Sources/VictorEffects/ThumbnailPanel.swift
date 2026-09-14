import AppKit

/// The window the grid lives in.
///
/// A non-activating `NSPanel` because the gesture is "hold a modifier and
/// click": the app the user is presenting from must keep its focus, its
/// selection and its caret while the panel is up and after a tile is pressed.
/// That rules out anything that can become key.
final class ThumbnailPanel: NSPanel {
    let grid = ThumbnailGridView()
    /// Page 2. Both grids live in the panel for the life of the process and one
    /// of them is hidden, because the whole point of the ⌥ half of the gesture
    /// is that the switch is **instant**: a key that is already held is not a
    /// moment at which to build eighteen views and decode eighteen JPEGs.
    let videoGrid = VideoGridView()
    private(set) var page: PanelPage = .effects

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

        let content = PanelContentView(frame: contentRect(forFrameRect: frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.94).cgColor
        content.layer?.cornerRadius = 18
        content.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        contentView = content

        grid.autoresizingMask = [.width, .height]
        grid.frame = content.bounds
        content.addSubview(grid)

        videoGrid.autoresizingMask = [.width, .height]
        videoGrid.frame = content.bounds
        videoGrid.isHidden = true
        content.addSubview(videoGrid)
    }

    /// Swap which grid is on show. **No slide and no re-show**: the panel is
    /// already up under a held key, and animating it would read as the board
    /// going away rather than as the board changing pages.
    func setPage(_ page: PanelPage) {
        self.page = page
        grid.isHidden = page != .effects
        videoGrid.isHidden = page != .videos
        let visible: NSView = page == .effects ? grid : videoGrid
        visible.frame = contentView?.bounds ?? visible.frame
        visible.needsLayout = true
        visible.layoutSubtreeIfNeeded()
        // The page changed under a key that is still held, i.e. under a pointer
        // that has not moved. Nothing will send an enter; ask instead.
        syncHoverToMouse()
    }

    /// Re-resolve which tile the pointer is on. **Every one of the three callers
    /// is a moment when the BOARD moves and the mouse does not** — the slide
    /// landing, the hug resizing, the page flipping — and a tracking area that
    /// appears under a stationary pointer is never entered. This is why the
    /// highlight looked broken on a two-screen desk in particular: there the
    /// panel fills the second screen, so it lands under wherever the pointer
    /// already was, while on one screen it takes the bottom-right corner and the
    /// pointer usually has to travel in and trigger a real enter.
    func syncHoverToMouse() {
        grid.syncHoverToMouse()
        videoGrid.syncHoverToMouse()
    }

    private func clearHover() {
        grid.clearHover()
        videoGrid.clearHover()
    }

    /// Never key, never main — see the class note. Overridden rather than set,
    /// because `NSPanel` decides this by asking, not by reading a stored flag.
    ///
    /// This is also why the hand over the board is pinned from tracking areas
    /// (`PanelCursor`) and NOT with `addCursorRect`/`invalidateCursorRects`:
    /// cursor *rects* are dispatched to the key window only, so on this panel
    /// they would never fire once and the cursor would keep being decided by the
    /// window underneath.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show at `frame`, sliding in from `offscreenX` (the screen's right edge).
    ///
    /// The window is parked off to the right **at its final size** and only its
    /// origin is animated: the content view never resizes, so 91 tiles are laid
    /// out once instead of on every frame of the slide.
    /// Square off the card's corners when the board covers a whole display.
    ///
    /// The 18 pt radius is what makes the panel read as a card floating over a
    /// slide, which is right in the corner layout. On a screen the board owns
    /// edge to edge there is nothing to float over, and the rounding costs
    /// twice: four notches of desktop at the corners, and — because the same
    /// layer must clip to draw the radius — the corner tiles' hover mark sliced
    /// off against it.
    func setFillsScreen(_ fills: Bool) {
        contentView?.layer?.cornerRadius = fills ? 0 : 18
        contentView?.layer?.masksToBounds = !fills
    }

    func show(at frame: NSRect, slidingFrom offscreenX: CGFloat) {
        slideGeneration += 1

        setFrame(NSRect(x: offscreenX, y: frame.minY,
                        width: frame.width, height: frame.height), display: false)
        let visible: NSView = page == .effects ? grid : videoGrid
        visible.frame = contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
        visible.needsLayout = true
        visible.layoutSubtreeIfNeeded()

        // Fade the first frames in as well as slide them: on a multi-screen
        // desk the parking spot is over the neighbouring screen, and a board
        // that flashes there before it flies in is worse than no animation.
        alphaValue = 0
        // `orderFrontRegardless`, not `makeKeyAndOrderFront`: the second would
        // steal focus from the app being presented even from a panel that
        // refuses key status, by activating this app.
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.slideInDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
            animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            // The board has landed, possibly right under a pointer that never
            // moved — which is the whole gesture. Light the tile it is on.
            self?.syncHoverToMouse()
        })
    }

    /// Resize in place, un-animated: the page switch changes how tall the grid
    /// hugs, and a board that grew a row must not slide to say so.
    func resize(to frame: NSRect) {
        guard isVisible else { return }
        setFrame(frame, display: true)
        let visible: NSView = page == .effects ? grid : videoGrid
        visible.frame = contentView?.bounds ?? visible.frame
        visible.needsLayout = true
        visible.layoutSubtreeIfNeeded()
        syncHoverToMouse()
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
        videoGrid.releaseCursor()
        // Same reason: no `mouseExited` arrives, and a tile left green here is
        // still green on the next show, on whichever tile the mouse is not on.
        clearHover()
    }

    /// Instant, un-animated. The panic path: the feature was switched off, or
    /// the app is going away.
    func hideNow() {
        slideGeneration += 1
        orderOut(nil)
        alphaValue = 1
        grid.releaseCursor()
        videoGrid.releaseCursor()
        clearHover()
    }
}

/// The panel's own content view: dark rounded card, and the same hand.
///
/// The grid fills it, so in practice the pointer is over `ThumbnailGridView`
/// nearly always — but "nearly" is the gap the old behaviour lived in. The
/// padding around the grid, the empty-manifest message, and the frames between
/// the panel appearing and the grid laying out are all this view, and over every
/// one of them the cursor must already be the hand rather than borrow the shape
/// of the window underneath.
final class PanelContentView: NSView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseEnteredAndExited,
                                                 .mouseMoved, .cursorUpdate, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// The panel never becomes key, so every click on it is a "first mouse".
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { PanelCursor.pinArrow() }
    override func mouseMoved(with event: NSEvent) { PanelCursor.pinArrow() }
    override func cursorUpdate(with event: NSEvent) { PanelCursor.pinArrow() }
}
