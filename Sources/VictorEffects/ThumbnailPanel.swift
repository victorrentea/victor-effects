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

    // MARK: ⌥-scroll zoom (`ZoomedPanel`)

    /// The frame the board is laid out for — global points on the UNZOOMED
    /// screen, the frame the controller chose. The window itself sits at this
    /// frame mapped into the slice on the glass (`ZoomedPanel.frame`), and the
    /// content view keeps this size as its bounds, so tiles are laid out once at
    /// the same size zoomed or not and clicks land on the tile that is drawn.
    private var designFrame: NSRect?
    /// The display the board is on — the one whose zoom it follows. Not
    /// necessarily the overlay screen: on a two-screen desk the board goes on
    /// the other one, and macOS zooms each display on its own.
    private var zoomScreen: NSScreen?
    /// The slice the frame was last mapped into, so the follower is one zoom
    /// read per tick while nothing moves.
    private var appliedVisible: CGRect?
    /// Re-maps the board while it is up and landed, because the viewport pans
    /// with the pointer — and the pointer is travelling to a tile. 60 Hz, not
    /// the caption's 30: this one is clicked, and a frame left behind by a pan
    /// is a click on the neighbouring tile.
    private var zoomPin: Timer?
    static let zoomFollowInterval: TimeInterval = 1.0 / 60

    /// The zoom shrink applied to the window right now (1 at rest), for the
    /// test hook's report.
    var zoomScale: CGFloat {
        guard let designFrame, designFrame.width > 0 else { return 1 }
        return frame.width / designFrame.width
    }

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
        level = NSWindow.Level(rawValue: EffectsLevel.overlay.rawValue - 1)
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

    /// `frame` and `offscreenX` are in UNZOOMED global points; under ⌥-scroll
    /// zoom both are mapped into the slice on `screen`'s glass here, so the
    /// board lands — and slides in from the edge of — what the room sees.
    func show(at frame: NSRect, on screen: NSScreen?, slidingFrom offscreenX: CGFloat) {
        slideGeneration += 1
        let generation = slideGeneration
        stopZoomPin()

        designFrame = frame
        zoomScreen = screen
        let slice = currentVisible(design: frame)
        appliedVisible = slice
        let target = glassFrame(frame, slice)
        let parked = glassFrame(NSRect(x: offscreenX, y: frame.minY,
                                       width: frame.width, height: frame.height), slice)
        ZoomedPanel.apply(self, frame: parked, designSize: frame.size, display: false)
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
            animator().setFrame(target, display: true)
            animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            // The board has landed, possibly right under a pointer that never
            // moved — which is the whole gesture. Light the tile it is on.
            self?.syncHoverToMouse()
            // Follow the zoom only once landed: re-placing it mid-slide would
            // fight `animator().setFrame`. A slide-out that overtook this one
            // owns the window now and must not be followed.
            guard let self, self.slideGeneration == generation else { return }
            self.startZoomPin()
        })
    }

    /// Resize in place, un-animated: the page switch changes how tall the grid
    /// hugs, and a board that grew a row must not slide to say so.
    /// `frame` is the new DESIGN frame, mapped onto the glass like `show`'s.
    func resize(to frame: NSRect) {
        guard isVisible else { return }
        designFrame = frame
        let slice = currentVisible(design: frame)
        appliedVisible = slice
        ZoomedPanel.apply(self, frame: glassFrame(frame, slice), designSize: frame.size)
        fitPagesToContent()
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
        stopZoomPin()

        // Out to the parking spot mapped like the board itself — the right edge
        // of the slice on the glass, not of the unzoomed screen, which zoomed in
        // is somewhere off the glass entirely.
        var out = frame
        if let designFrame {
            out.origin.x = glassFrame(NSRect(x: offscreenX, y: designFrame.minY,
                                             width: designFrame.width, height: designFrame.height),
                                      currentVisible(design: designFrame)).minX
        } else {
            out.origin.x = offscreenX
        }

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
        stopZoomPin()
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
        stopZoomPin()
        orderOut(nil)
        alphaValue = 1
        grid.releaseCursor()
        videoGrid.releaseCursor()
        clearHover()
    }
}

extension ThumbnailPanel {
    /// The slice of the board's screen on the glass now — the screen itself at
    /// rest, or when the screen is unknown (then nothing is mapped at all).
    fileprivate func currentVisible(design: NSRect) -> CGRect {
        guard let zoomScreen else { return design }
        return ZoomedPanel.visible(on: zoomScreen, fallback: zoomScreen.frame)
    }

    fileprivate func glassFrame(_ design: NSRect, _ slice: CGRect) -> NSRect {
        guard let zoomScreen else { return design }
        return ZoomedPanel.frame(design: design, screen: zoomScreen.frame, visible: slice)
    }

    /// Both pages back onto the content's (design-sized) bounds. A resize of a
    /// view with scaled bounds autoresizes its subviews by the INTERMEDIATE
    /// bounds AppKit computes before ours are re-asserted, so this is not
    /// optional after a zoom change.
    fileprivate func fitPagesToContent() {
        guard let bounds = contentView?.bounds else { return }
        for view in [grid, videoGrid] as [NSView] where view.frame != bounds {
            view.frame = bounds
            view.needsLayout = true
        }
        let visible: NSView = page == .effects ? grid : videoGrid
        visible.needsLayout = true
        visible.layoutSubtreeIfNeeded()
    }

    fileprivate func startZoomPin() {
        stopZoomPin()
        // Nothing to follow on a screen nobody can zoom into (unknown screen).
        guard zoomScreen != nil else { return }
        let timer = Timer(timeInterval: Self.zoomFollowInterval, repeats: true) { [weak self] _ in
            self?.followZoom()
        }
        RunLoop.main.add(timer, forMode: .common)
        zoomPin = timer
    }

    fileprivate func stopZoomPin() {
        zoomPin?.invalidate()
        zoomPin = nil
    }

    /// One tick: a no-op while the slice has not moved; otherwise the board is
    /// re-mapped onto the glass and the hover re-resolved, since the board just
    /// moved under a pointer that did not.
    private func followZoom() {
        guard isVisible, let designFrame else { stopZoomPin(); return }
        let slice = currentVisible(design: designFrame)
        guard slice != appliedVisible else { return }
        appliedVisible = slice
        ZoomedPanel.apply(self, frame: glassFrame(designFrame, slice), designSize: designFrame.size)
        fitPagesToContent()
        syncHoverToMouse()
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
