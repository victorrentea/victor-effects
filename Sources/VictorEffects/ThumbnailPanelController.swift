import AppKit

/// Owns the thumbnail panel: when it appears, where, and what a tile press does.
///
/// The gesture is **hold the right ⌥ alone for 180 ms**. Right and not left
/// because every ⌥-shortcut on this keyboard is typed with the left hand —
/// binding the left key would flash a soundboard over the screen on every ⌥←.
/// *Alone* because ⌃⌥ and ⌥⇧ are layers other apps own. The 180 ms exist for
/// the same reason from the other side: right-⌥E to type an accent is a tap,
/// not a hold, and a tap must not show anything.
///
/// Nothing here ever swallows a key. The panel is a passenger on the event tap;
/// if it ever ate the modifier, every ⌥-accent typed with the right hand would
/// die with it.
final class ThumbnailPanelController {
    /// How long the key must be held before the panel appears.
    static let holdDelay: TimeInterval = 0.180
    /// How long `/test/thumbnail-panel` leaves it up.
    static let testShowSeconds: TimeInterval = 5

    /// The trigger, as a pure state machine.
    ///
    /// Extracted because the real thing needs Accessibility, an event tap and a
    /// pair of hands: on a Mac without the grant — this one, at the time of
    /// writing — the only way to prove that right-⌥E still reaches the front
    /// app is to assert it on the rule itself.
    enum PanelHoldRule {
        enum Event {
            case rightOptionDown
            case holdTimerFired
            case rightOptionUp
            /// Any other key or modifier went down while the right ⌥ was held:
            /// the user is typing an accent, not asking for a soundboard.
            case keyWhileRightOption
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
            case .rightOptionDown:
                guard state.enabled, !state.holdArmed, !state.shownByHold else { return [] }
                state.holdArmed = true
                return [.armHoldTimer]

            case .holdTimerFired:
                guard state.holdArmed else { return [] }
                state.holdArmed = false
                state.shownByHold = true
                return [.show]

            case .rightOptionUp:
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

            case .keyWhileRightOption:
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

    func rightOption(down: Bool) {
        perform(PanelHoldRule.apply(down ? .rightOptionDown : .rightOptionUp, to: &state))
    }

    func keyWhileRightOption() {
        perform(PanelHoldRule.apply(.keyWhileRightOption, to: &state))
    }

    func setEnabled(_ enabled: Bool) {
        state.enabled = enabled
        if !enabled {
            perform(PanelHoldRule.apply(.rightOptionUp, to: &state))
            hide()
        }
        effectsInfo("Thumbnail panel \(enabled ? "enabled" : "disabled") (right-⌥ hold)")
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
        panel.show(at: placement.frame)
        panel.grid.setPlaying(asset: press.playing?.asset)
        effectsInfo("Thumbnail panel on \"\(placement.screen.name)\" "
            + "\(Int(placement.frame.width))×\(Int(placement.frame.height)) "
            + "at (\(Int(placement.frame.minX)),\(Int(placement.frame.minY))) — "
            + "\(panel.grid.tiles.count) tiles")
        return placement
    }

    func hide() {
        autoHide?.invalidate()
        autoHide = nil
        shownSticky = false
        panel?.hideNow()
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
