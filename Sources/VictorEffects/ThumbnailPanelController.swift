import AppKit

/// Which grid the panel is showing.
///
/// Two, because the tablet has two — page 1 the soundboard, page 2 the 🎬 video
/// snippets — and the panel exists to put the tablet's board on the Mac when the
/// tablet is not in reach. A page that stopped at page 1 would be half of that.
enum PanelPage: String, Equatable {
    case effects
    case videos
}

/// Owns the thumbnail panel: when it appears, where, and what a tile press does.
///
/// The gesture is **hold the right ⌘ for 180 ms** — alone for the soundboard,
/// with the **right ⇧** for the videos. Right and not left
/// because every ⌘-shortcut on this keyboard is typed with the left hand —
/// binding the left key would flash a soundboard over the screen on every ⌘C.
/// *Alone* because ⌃⌘, ⌘⌥ and left-hand ⌘⇧ are shortcut layers other apps own —
/// ⌘⌥ most of all, since right ⌘ + right ⌥ is **Wispr Flow's push-to-talk**.
/// The 180 ms
/// exist for the same reason from the other side: a right-⌘ shortcut is a tap,
/// not a hold, and a tap must not show anything. The second modifier is right ⇧
/// and not a number key because the page is a *state of the hold*, not a
/// command: let go of ⇧ and the soundboard is back, with the panel never having
/// gone anywhere.
///
/// Nothing here ever swallows a key. The panel is a passenger on the event tap;
/// if it ever ate the modifier, every ⌘-shortcut typed with the right hand
/// would die with it.
final class ThumbnailPanelController {
    /// How long the key must be held before the panel appears.
    static let holdDelay: TimeInterval = 0.180
    /// How long `/test/thumbnail-panel` leaves it up.
    static let testShowSeconds: TimeInterval = 5

    /// The trigger, as a pure state machine.
    ///
    /// Extracted because the real thing needs Accessibility, an event tap and a
    /// pair of hands: on a Mac without the grant — this one, at the time of
    /// writing — the only way to prove that right-⌘C still reaches the front
    /// app is to assert it on the rule itself.
    enum PanelHoldRule {
        enum Event: Equatable {
            case rightCommandDown
            case holdTimerFired
            case rightCommandUp
            /// Right ⇧ joined the held right ⌘ → page 2.
            case rightShiftDown
            /// …and let go again → back to page 1.
            case rightShiftUp
            /// Any other key or modifier went down while the right ⌘ was held:
            /// the user is typing a shortcut, not asking for a soundboard.
            case keyWhileRightCommand
        }

        enum Action: Equatable {
            case armHoldTimer
            case cancelHoldTimer
            /// Show, on this page. The page rides on the action rather than
            /// being read back off the state by the caller, so a `.show` is a
            /// complete instruction and the two can never disagree.
            case show(PanelPage)
            /// The panel is already up: swap its content, in place.
            case setPage(PanelPage)
            case hide
        }

        struct State: Equatable {
            /// A hold timer is pending.
            var holdArmed = false
            /// The panel is up *because of the hold* — as opposed to the menu
            /// row or the test hook, which outlive the key.
            var shownByHold = false
            /// Which page the *current hold* means. Reset by every end of a
            /// hold, so a gesture always starts on the soundboard: ⇧ is held
            /// down, not latched, and a page that survived the key would be a
            /// mode nobody asked for.
            var page: PanelPage = .effects
        }

        static func apply(_ event: Event, to state: inout State) -> [Action] {
            switch event {
            case .rightCommandDown:
                guard !state.holdArmed, !state.shownByHold else { return [] }
                // A fresh hold starts on the soundboard. When right ⇧ is ALREADY
                // down the tap follows this immediately with `.rightShiftDown`,
                // which is how "either order" is one ordering in here.
                state.page = .effects
                state.holdArmed = true
                return [.armHoldTimer]

            case .holdTimerFired:
                guard state.holdArmed else { return [] }
                state.holdArmed = false
                state.shownByHold = true
                return [.show(state.page)]

            case .rightShiftDown, .rightShiftUp:
                let wanted: PanelPage = event == .rightShiftDown ? .videos : .effects
                // ⇧ on its own is somebody else's key: the page only exists
                // inside a hold, armed or shown.
                guard state.holdArmed || state.shownByHold else { return [] }
                guard state.page != wanted else { return [] }
                state.page = wanted
                // Before the timer fires there is nothing to swap — the page is
                // simply what the pending `.show` will carry. After it fires the
                // content changes **in place**: no hide, no show, no slide.
                return state.shownByHold ? [.setPage(wanted)] : []

            case .rightCommandUp:
                var actions: [Action] = []
                state.page = .effects
                if state.holdArmed {
                    state.holdArmed = false
                    actions.append(.cancelHoldTimer)
                }
                if state.shownByHold {
                    state.shownByHold = false
                    actions.append(.hide)
                }
                return actions

            case .keyWhileRightCommand:
                // Before the panel is up: the hold was an accent, disarm.
                // After it is up: get out of the way rather than fight ⌥E.
                if state.holdArmed {
                    state.holdArmed = false
                    state.page = .effects
                    return [.cancelHoldTimer]
                }
                if state.shownByHold {
                    state.shownByHold = false
                    state.page = .effects
                    return [.hide]
                }
                return []
            }
        }
    }

    // MARK: - State

    private let router: EffectsRouter
    private let press: SoundboardPress
    /// Page 2's press semantics. A second object and not a branch inside
    /// `SoundboardPress`, because the two share nothing but the word "press":
    /// one is a sequence of in-process routes on this Mac's own sound engine,
    /// the other is a single HTTP call to a player in another process.
    private let videoPress = VideoPress()
    private var state: PanelHoldRule.State
    private var panel: ThumbnailPanel?
    private var holdWork: DispatchWorkItem?
    private var autoHide: Timer?
    /// Shown by a menu row or the test hook, i.e. not tied to the key.
    private var shownSticky = false
    /// The page currently on screen. The rule's `state.page` cannot answer it:
    /// that one is a property of the *hold* and is reset the moment the key goes
    /// up, while a panel opened from a menu row outlives every key.
    private var shownPage: PanelPage = .effects
    /// Manifest hash the grid was built from, so a show does not rebuild 91
    /// views for a file that has not changed.
    private var builtFromHash: String?
    /// The x the panel slides in from and back out to — the right edge of the
    /// screen it was last placed on. Remembered because a hide has no placement
    /// of its own and must not have to recompute one to leave.
    private var offscreenX: CGFloat?
    /// The placement the panel was last shown at — kept so a live page switch
    /// can re-hug to the other page's height without re-running the screen
    /// choice, which would be free to pick a different screen mid-gesture.
    private var lastPlacement: ThumbnailPanelPlacement.Placement?

    init(router: EffectsRouter) {
        self.router = router
        self.press = SoundboardPress(router: router)
        self.state = PanelHoldRule.State()
        press.onPlayingChanged = { [weak self] tile in
            self?.panel?.grid.setPlaying(asset: tile?.asset)
        }
        videoPress.onPlayingChanged = { [weak self] tile in
            self?.panel?.videoGrid.setPlaying(id: tile?.id)
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Trigger

    func rightCommand(down: Bool) {
        perform(PanelHoldRule.apply(down ? .rightCommandDown : .rightCommandUp, to: &state))
    }

    /// Right ⇧ went down / came up underneath a held right ⌘ — the page switch.
    func rightShift(down: Bool) {
        perform(PanelHoldRule.apply(down ? .rightShiftDown : .rightShiftUp, to: &state))
    }

    func keyWhileRightCommand() {
        perform(PanelHoldRule.apply(.keyWhileRightCommand, to: &state))
    }

    private func perform(_ actions: [PanelHoldRule.Action]) {
        for action in actions {
            switch action {
            case .armHoldTimer:
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.holdWork = nil
                    self.perform(PanelHoldRule.apply(.holdTimerFired, to: &self.state))
                }
                holdWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
            case .cancelHoldTimer:
                holdWork?.cancel()
                holdWork = nil
            case .show(let page):
                show(page: page)
            case .setPage(let page):
                switchPage(to: page)
            case .hide:
                hide()
            }
        }
    }

    // MARK: - Show / hide

    @discardableResult
    private func show(page: PanelPage) -> ThumbnailPanelPlacement.Placement? {
        guard let placement = ThumbnailPanelPlacement.choose(
            screens: ThumbnailPanelPlacement.currentScreens(),
            mouse: NSEvent.mouseLocation) else { return nil }

        let panel = ensurePanel()
        build(page: page, in: panel)
        panel.setPage(page)

        // Hug the grid: the cells fit both ways, so a board across a wide frame
        // leaves a black band above and below the rows. Trim the frame to the
        // height the grid actually draws at, keeping the width rule and the
        // anchor the placement chose. Page 2 answers the same question with its
        // own arithmetic — five 16:9 tiles a row rather than thirteen squares —
        // so the two pages are different heights and each hugs its own.
        let hugged = hug(placement, page: page, in: panel)
        let placed = ThumbnailPanelPlacement.Placement(screen: placement.screen,
                                                       frame: hugged,
                                                       anchor: placement.anchor)

        shownPage = page
        let offscreen = placement.screen.visibleFrame.maxX
        offscreenX = offscreen
        lastPlacement = placement
        panel.show(at: hugged, slidingFrom: offscreen)
        panel.grid.setPlaying(asset: press.playing?.asset)
        panel.videoGrid.setPlaying(id: videoPress.playing?.id)
        effectsInfo("Thumbnail panel (\(page.rawValue)) on \"\(placed.screen.name)\" "
            + "\(Int(hugged.width))×\(Int(hugged.height)) "
            + "at (\(Int(hugged.minX)),\(Int(hugged.minY))) — "
            + "\(tileCount(page: page, in: panel)) tiles "
            + "(trimmed \(Int(placement.frame.height - hugged.height)) pt of band)")
        return placed
    }

    private func ensurePanel() -> ThumbnailPanel {
        if let panel { return panel }
        let panel = ThumbnailPanel()
        panel.grid.onPress = { [weak self] tile in self?.pressed(tile) }
        panel.videoGrid.onPress = { [weak self] tile in self?.pressedVideo(tile) }
        self.panel = panel
        return panel
    }

    /// Fill the page that is about to be shown, and only that one.
    ///
    /// Page 1 **re-reads `tiles.json` on every show** and rebuilds only when the
    /// bytes moved (91 views for an unchanged file is work nobody asked for).
    /// The re-read is what retired the `Reload tiles.json` menu row: a manifest
    /// edited in the tablet's repo now reaches the board on the next hold
    /// instead of on the next click of a row somebody had to remember. It costs
    /// one read and one SHA-256 of a ~30 KB file per show. Page 2 re-asks addons
    /// **on every show**,
    /// because a video added with the `add-training-video` skill has to appear
    /// without restarting this app — and falls back on the last good list when
    /// the answer does not come, which is the whole reason `VideosManifest`
    /// caches at all.
    private func build(page: PanelPage, in panel: ThumbnailPanel) {
        switch page {
        case .effects:
            TilesManifest.invalidate()
            let hash = TilesManifest.load()?.hash
            if builtFromHash != hash || panel.grid.tiles.isEmpty {
                // A manifest that moved may have moved its pictures too, and the
                // cache is keyed by path: a tile re-pointed at a file that was
                // replaced in place would otherwise keep the old thumbnail for
                // the life of the process.
                if builtFromHash != nil { TileImageCache.shared.clear() }
                panel.grid.reload()
                builtFromHash = hash
            }
        case .videos:
            panel.videoGrid.reload(with: VideosManifest.refresh())
        }
    }

    private func tileCount(page: PanelPage, in panel: ThumbnailPanel) -> Int {
        page == .effects ? panel.grid.tiles.count : panel.videoGrid.tiles.count
    }

    private func hug(_ placement: ThumbnailPanelPlacement.Placement,
                     page: PanelPage,
                     in panel: ThumbnailPanel) -> NSRect {
        let content = page == .effects
            ? panel.grid.hugHeight(fitting: placement.frame.size)
            : panel.videoGrid.hugHeight(fitting: placement.frame.size)
        return content.map {
            ThumbnailPanelPlacement.hug(placement.frame, toContentHeight: $0,
                                        anchor: placement.anchor)
        } ?? placement.frame
    }

    /// Flip the page of a panel that is already up. **No slide, no re-show** —
    /// the key is still held and the board must read as changing its mind, not
    /// as leaving and coming back. The frame still moves, because the two pages
    /// hug to different heights; it is set rather than animated for the same
    /// reason.
    private func switchPage(to page: PanelPage) {
        guard let panel, panel.isVisible else { return }
        build(page: page, in: panel)
        panel.setPage(page)
        shownPage = page
        panel.grid.setPlaying(asset: press.playing?.asset)
        panel.videoGrid.setPlaying(id: videoPress.playing?.id)
        if let placement = lastPlacement {
            panel.resize(to: hug(placement, page: page, in: panel))
        }
        effectsInfo("Thumbnail panel → \(page.rawValue) page "
            + "(\(tileCount(page: page, in: panel)) tiles)")
    }

    func hide() {
        autoHide?.invalidate()
        autoHide = nil
        shownSticky = false
        // Slide back out rather than blink away — and from wherever the window
        // has got to, so a key released mid-slide-in still leaves cleanly.
        if let offscreen = offscreenX {
            panel?.slideOut(to: offscreen)
        } else {
            panel?.hideNow()
        }
    }

    /// One of the two menu rows, so a Mac with no Accessibility grant can still
    /// see either board. Page-specific, because the rows are: the hold teaches
    /// the two pages with ⇧, and a mouse-only user has to be able to reach the
    /// second one too.
    ///
    /// Still a toggle on the row that is already showing — clicking `Show Effect
    /// Panel` twice puts the board away — while the *other* row swaps the page
    /// in place rather than hiding, which is what the ⇧ half of the gesture does.
    func showFromMenu(page: PanelPage) {
        if isVisible {
            if shownPage == page { hide(); return }
            switchPage(to: page)
            return
        }
        shownSticky = true
        show(page: page)
    }

    // MARK: - Presses

    private func pressed(_ tile: Tile) {
        _ = press.press(tile)
    }

    private func pressedVideo(_ tile: VideoTile) {
        _ = videoPress.press(tile)
    }

    // MARK: - Test hooks (the panel's half of the router table)

    /// `GET /test/thumbnail-panel` — show it for five seconds and report where
    /// it went, so the placement rule can be checked from a shell on a Mac
    /// nobody is looking at.
    func showForTest(page: PanelPage = .effects) -> String {
        shownSticky = true
        guard let placement = show(page: page) else {
            return "{\"ok\":false,\"reason\":\"no-screens\"}"
        }
        autoHide?.invalidate()
        autoHide = Timer.scheduledTimer(withTimeInterval: Self.testShowSeconds, repeats: false) { [weak self] _ in
            self?.hide()
        }
        let f = placement.frame
        let tiles = panel.map { tileCount(page: page, in: $0) } ?? 0
        let name = placement.screen.name.replacingOccurrences(of: "\"", with: "'")
        return "{\"ok\":true,\"page\":\"\(page.rawValue)\","
            + "\"screen\":\"\(name)\",\"primary\":\(placement.screen.isPrimary),"
            + "\"overlayScreen\":\(placement.screen.isOverlay),"
            + "\"frame\":{\"x\":\(Int(f.minX)),\"y\":\(Int(f.minY)),"
            + "\"w\":\(Int(f.width)),\"h\":\(Int(f.height))},"
            + "\"tiles\":\(tiles),\"seconds\":\(Int(Self.testShowSeconds))}"
    }

    /// `GET /test/thumbnail-panel/press/<n>` — exactly what a click does,
    /// without the click. The panel need not be visible: the press path is the
    /// sound semantics, not the window.
    func pressTile(number: Int, page: PanelPage = .effects) -> String {
        if page == .videos {
            // The list has to exist before a number can mean anything, and the
            // hook is the one caller that may arrive without a show first.
            if VideosManifest.cached.isEmpty { VideosManifest.refresh() }
            guard let video = VideosManifest.tile(number: number) else {
                return "{\"ok\":false,\"n\":\(number),\"reason\":\"unknown-video\"}"
            }
            return videoPress.press(video)
        }
        guard let tile = TilesManifest.tile(number: number) else {
            return "{\"ok\":false,\"n\":\(number),\"reason\":\"unknown-tile\"}"
        }
        return press.press(tile)
    }

    /// Claims the four hook points the router left open for this work item.
    func claimRouterHooks() {
        router.onPanelShow = { [weak self] page in
            self?.showForTest(page: page) ?? "{\"ok\":false}"
        }
        router.onPanelHide = { [weak self] in self?.hide() }
        router.onPanelPress = { [weak self] n, page in
            self?.pressTile(number: n, page: page) ?? "{\"ok\":false,\"reason\":\"no-panel\"}"
        }
        router.panelVisible = { [weak self] in self?.isVisible ?? false }
    }
}
