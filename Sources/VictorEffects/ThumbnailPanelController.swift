import AppKit

/// Owns the thumbnail panel: when it appears, where, and what a tile press does.
///
/// The gesture is **hold the right ⌘ alone for 180 ms**. Right and not left
/// because every ⌘-shortcut on this keyboard is typed with the left hand —
/// binding the left key would flash a soundboard over the screen on every ⌘C.
/// *Alone* because ⌃⌘, ⌘⇧ and ⌘⌥ are shortcut layers other apps own. The 180 ms
/// exist for the same reason from the other side: a right-⌘ shortcut is a tap,
/// not a hold, and a tap must not show anything.
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
        enum Event {
            case rightCommandDown
            case holdTimerFired
            case rightCommandUp
            /// Any other key or modifier went down while the right ⌘ was held:
            /// the user is typing a shortcut, not asking for a soundboard.
            case keyWhileRightCommand
        }

        enum Action: Equatable {
            case armHoldTimer
            case cancelHoldTimer
            case show
            case hide
        }

        struct State: Equatable {
            var enabled = true
            /// A hold timer is pending.
            var holdArmed = false
            /// The panel is up *because of the hold* — as opposed to the menu
            /// row or the test hook, which outlive the key.
            var shownByHold = false
        }

        static func apply(_ event: Event, to state: inout State) -> [Action] {
            switch event {
            case .rightCommandDown:
                guard state.enabled, !state.holdArmed, !state.shownByHold else { return [] }
                state.holdArmed = true
                return [.armHoldTimer]

            case .holdTimerFired:
                guard state.holdArmed else { return [] }
                state.holdArmed = false
                state.shownByHold = true
                return [.show]

            case .rightCommandUp:
                var actions: [Action] = []
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
                    return [.cancelHoldTimer]
                }
                if state.shownByHold {
                    state.shownByHold = false
                    return [.hide]
                }
                return []
            }
        }
    }

    // MARK: - State

    private let router: EffectsRouter
    private let press: SoundboardPress
    private var state: PanelHoldRule.State
    private var panel: ThumbnailPanel?
    private var holdWork: DispatchWorkItem?
    private var autoHide: Timer?
    /// Shown by the menu row or the test hook, i.e. not tied to the key.
    private var shownSticky = false
    /// Manifest hash the grid was built from, so a show does not rebuild 91
    /// views for a file that has not changed.
    private var builtFromHash: String?
    /// The x the panel slides in from and back out to — the right edge of the
    /// screen it was last placed on. Remembered because a hide has no placement
    /// of its own and must not have to recompute one to leave.
    private var offscreenX: CGFloat?

    init(router: EffectsRouter) {
        self.router = router
        self.press = SoundboardPress(router: router)
        self.state = PanelHoldRule.State(enabled: MenuBar.panelEnabled)
        press.onPlayingChanged = { [weak self] tile in
            self?.panel?.grid.setPlaying(asset: tile?.asset)
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Trigger

    func rightCommand(down: Bool) {
        perform(PanelHoldRule.apply(down ? .rightCommandDown : .rightCommandUp, to: &state))
    }

    func keyWhileRightCommand() {
        perform(PanelHoldRule.apply(.keyWhileRightCommand, to: &state))
    }

    func setEnabled(_ enabled: Bool) {
        state.enabled = enabled
        if !enabled {
            perform(PanelHoldRule.apply(.rightCommandUp, to: &state))
            // Switched off: gone now, not in 120 ms.
            autoHide?.invalidate()
            autoHide = nil
            shownSticky = false
            panel?.hideNow()
        }
        effectsInfo("Thumbnail panel \(enabled ? "enabled" : "disabled") (right-⌘ hold)")
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
            case .show:
                show()
            case .hide:
                hide()
            }
        }
    }

    // MARK: - Show / hide

    @discardableResult
    private func show() -> ThumbnailPanelPlacement.Placement? {
        guard let placement = ThumbnailPanelPlacement.choose(
            screens: ThumbnailPanelPlacement.currentScreens(),
            mouse: NSEvent.mouseLocation) else { return nil }

        let panel = self.panel ?? ThumbnailPanel()
        if self.panel == nil {
            panel.grid.onPress = { [weak self] tile in self?.pressed(tile) }
            self.panel = panel
        }
        let hash = TilesManifest.load()?.hash
        if builtFromHash != hash || panel.grid.tiles.isEmpty {
            panel.grid.reload()
            builtFromHash = hash
        }
        // Hug the grid: the cells are square and fit both ways, so a 13-column
        // board across a wide frame leaves a black band above and below the
        // rows. Trim the frame to the height the grid actually draws at,
        // keeping the width rule and the anchor the placement chose.
        let hugged = panel.grid.hugHeight(fitting: placement.frame.size).map {
            ThumbnailPanelPlacement.hug(placement.frame, toContentHeight: $0,
                                        anchor: placement.anchor)
        } ?? placement.frame
        let placed = ThumbnailPanelPlacement.Placement(screen: placement.screen,
                                                       frame: hugged,
                                                       anchor: placement.anchor)

        let offscreen = placement.screen.visibleFrame.maxX
        offscreenX = offscreen
        panel.show(at: hugged, slidingFrom: offscreen)
        panel.grid.setPlaying(asset: press.playing?.asset)
        effectsInfo("Thumbnail panel on \"\(placed.screen.name)\" "
            + "\(Int(hugged.width))×\(Int(hugged.height)) "
            + "at (\(Int(hugged.minX)),\(Int(hugged.minY))) — "
            + "\(panel.grid.tiles.count) tiles "
            + "(trimmed \(Int(placement.frame.height - hugged.height)) pt of band)")
        return placed
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

    /// The menu row: a toggle, so a Mac with no Accessibility grant can still
    /// see the board.
    func toggleFromMenu() {
        if isVisible {
            hide()
        } else {
            shownSticky = true
            show()
        }
    }

    func reloadTiles() {
        TilesManifest.invalidate()
        TileImageCache.shared.clear()
        builtFromHash = nil
        if isVisible {
            panel?.grid.reload()
            builtFromHash = TilesManifest.load()?.hash
        }
        effectsInfo("tiles.json reloaded: \(TilesManifest.load()?.doc.tiles.count ?? 0) tiles")
    }

    // MARK: - Presses

    private func pressed(_ tile: Tile) {
        _ = press.press(tile)
    }

    // MARK: - Test hooks (the panel's half of the router table)

    /// `GET /test/thumbnail-panel` — show it for five seconds and report where
    /// it went, so the placement rule can be checked from a shell on a Mac
    /// nobody is looking at.
    func showForTest() -> String {
        shownSticky = true
        guard let placement = show() else {
            return "{\"ok\":false,\"reason\":\"no-screens\"}"
        }
        autoHide?.invalidate()
        autoHide = Timer.scheduledTimer(withTimeInterval: Self.testShowSeconds, repeats: false) { [weak self] _ in
            self?.hide()
        }
        let f = placement.frame
        let tiles = panel?.grid.tiles.count ?? 0
        let name = placement.screen.name.replacingOccurrences(of: "\"", with: "'")
        return "{\"ok\":true,\"screen\":\"\(name)\",\"primary\":\(placement.screen.isPrimary),"
            + "\"overlayScreen\":\(placement.screen.isOverlay),"
            + "\"frame\":{\"x\":\(Int(f.minX)),\"y\":\(Int(f.minY)),"
            + "\"w\":\(Int(f.width)),\"h\":\(Int(f.height))},"
            + "\"tiles\":\(tiles),\"seconds\":\(Int(Self.testShowSeconds))}"
    }

    /// `GET /test/thumbnail-panel/press/<n>` — exactly what a click does,
    /// without the click. The panel need not be visible: the press path is the
    /// sound semantics, not the window.
    func pressTile(number: Int) -> String {
        guard let tile = TilesManifest.tile(number: number) else {
            return "{\"ok\":false,\"n\":\(number),\"reason\":\"unknown-tile\"}"
        }
        return press.press(tile)
    }

    /// Claims the four hook points the router left open for this work item.
    func claimRouterHooks() {
        router.onPanelShow = { [weak self] in self?.showForTest() ?? "{\"ok\":false}" }
        router.onPanelHide = { [weak self] in self?.hide() }
        router.onPanelPress = { [weak self] n in
            self?.pressTile(number: n) ?? "{\"ok\":false,\"reason\":\"no-panel\"}"
        }
        router.panelVisible = { [weak self] in self?.isVisible ?? false }
    }
}
