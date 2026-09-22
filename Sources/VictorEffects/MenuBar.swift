import AppKit
import ApplicationServices
import Foundation

/// The ⭐ status item. Deliberately tiny compared to the addons menu it was cut
/// from, and smaller again since the panel arrived: a 39-row ⭐️ Effects submenu
/// was a menu of words for a board of pictures, so what is left is the two
/// features that need a no-Accessibility fallback (the panel, one row per page,
/// and ⌃W), the one feature with no other surface at all (the Bluetooth
/// keep-alive, whose tone is inaudible by design), and Quit.
///
/// **Two columns, and every row is in both.** A glyph of emoji width opens each
/// title, and each gesture is right-aligned down a single tab stop
/// (`layOutHints`) — including ⌘Q, which is why no row here carries a real
/// `keyEquivalent`: AppKit draws those in a column of their own that no tab
/// stop can reach into, and one native ⌘Q was enough to pull the right edge
/// crooked (2026-09-14).
///
/// The panic row went the same way, but *upwards* rather than out: stop-all is
/// now **the icon itself**. While anything is running the ⭐ turns 🛑 and a
/// left click stops everything, which is one gesture instead of two (click,
/// aim, click) at the exact moment nobody wants to aim — the effect is on the
/// screen the room is watching. A menu row that is only ever wanted while the
/// menu is hard to read was the wrong home for it.
final class MenuBar: NSObject, NSMenuDelegate {
    /// Rewritten in place by `build-app.sh` before every release build, so the
    /// Version row always says which binary is actually running.
    static let BUILD_TIME = "Sep 22, 15:24"

    // MARK: callbacks (AppDelegate wires them)

    /// 🛑 Stop all. No longer a row: this fires on a plain click of the status
    /// item while it is showing 🛑 (see `statusItemClicked`).
    var onStopAll: (() -> Void)?
    /// Is anything on screen or audible **right now**? Wired by `AppDelegate`
    /// to `EffectsEngine`, which already answers this for `GET /state`.
    ///
    /// Asked from two places for two different reasons: the 0.3 s poll, to pick
    /// which icon to draw, and `statusItemClicked`, to decide what a click
    /// means. The second one is a live read on purpose — see there.
    var isBusy: (() -> Bool)?
    /// 🔥 Whip — the menu equivalent of ⌃W, kept for a Mac that has not
    /// granted Accessibility (same rationale as addons' 📤 Mail clipboard row).
    var onWhip: (() -> Void)?
    /// The ✅/⚪️/🚫 keep-alive row: what to draw, and what a click means.
    /// Asked at menu-open time (like `isBusy`) rather than pushed, so nothing
    /// has to remember to tell the menu bar when a speaker connects.
    var keepAliveState: (() -> BluetoothKeepAlive.State)?
    var onToggleKeepAlive: (() -> Void)?
    /// One of the two panel rows was clicked: show that page of the thumbnail
    /// panel. The mouse-only way in, for a Mac without the Accessibility grant.
    var onShowPanel: ((PanelPage) -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var whipItem: NSMenuItem!
    private var keepAliveItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var accessibilitySeparator: NSMenuItem!

    /// The two faces of the status item. 🛑 means "something is running, and a
    /// click here stops it" — including an armed 🔥 whip, which is a *mode* and
    /// stays up until it is dismissed, so the bar sits on 🛑 for as long as the
    /// whip is out. That is the honest answer: a click there does take it down.
    /// ⭐ means "nothing is running, a click opens the menu". Nothing else is
    /// ever drawn there.
    private static let idleIcon = "⭐"
    private static let busyIcon = "🛑"

    /// Which of the two faces is currently drawn. **Display only** — the click
    /// rule deliberately does NOT consult it (see `statusItemClicked`); it
    /// exists so the poll can skip redrawing an icon that has not changed.
    private var showingBusyIcon = false

    /// How often the icon asks whether anything is still running.
    ///
    /// A poll, not a notification, and that is the point: by the
    /// **self-termination rule** every effect schedules its own removal, so
    /// most of the time nothing calls `stopAll()` at all — the last effect just
    /// stops existing. An icon that only changed when someone *told* it to
    /// would be stuck on 🛑 forever after any normally-ending effect. Asking is
    /// the only way to see an ending nobody announced. 0.3 s is below the
    /// threshold where the bar looks stale and far above the cost of reading
    /// four booleans (the timer does not even fire while the menu is open —
    /// menu tracking runs the run loop in its own mode).
    private static let busyPollInterval: TimeInterval = 0.3
    private var busyTimer: Timer?

    /// A row that shows a gesture on the right, and the two strings
    /// `layOutHints` re-lays it out from.
    private struct HintRow {
        let item: NSMenuItem
        let title: String
        let hint: String
        /// How far the row's own text starts to the right of every other row's,
        /// i.e. the width of its `image` box (0 for the emoji rows, which carry
        /// their glyph *inside* the title). A tab stop is measured from where
        /// the text begins, so an image row needs its stop pulled left by
        /// exactly this much or its hint lands one icon further right than the
        /// rest of the column. Measured in `imageColumn`, never assumed.
        let indent: CGFloat
    }
    private var hintRows: [HintRow] = []
    private var hintTabStop: CGFloat = 0

    /// What `NSMenu` adds around a title: a menu holding one item whose title
    /// has a right tab stop at L comes out L + 30 wide. Measured, not
    /// documented — hence `layOutHints` re-deriving the stop from the
    /// menu's own width instead of trusting this number on its own.
    ///
    /// A native key equivalent is **not** right-aligned against this inset —
    /// the comment here used to say it was, and the crooked ⌘Q of 2026-09-14
    /// was that sentence being wrong. `NSMenu` gives key equivalents a column
    /// of their own outside the title column entirely: the same probe shows a
    /// menu at tab stop 200 coming out 230 pt wide with no key equivalent and
    /// 277 with one ⌘Q in it — the extra 47 pt sitting to the right of every
    /// title, where a tab stop cannot follow. Hence: no row here has one.
    private static let titleInsets: CGFloat = 30
    /// Smallest gap between a title and its hint, so a long title pushes the
    /// menu wider instead of running into the column.
    private static let hintGap: CGFloat = 28

    func setup() {
        buildMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // **`statusItem.menu` is deliberately left nil.** Setting it hands the
        // button to `NSMenu`: AppKit opens the menu on mouse-DOWN and the
        // button's own `action` never fires, so there is no way to make a click
        // mean "stop everything" while a menu is attached. Detaching it moves
        // the decision here, and the menu is re-attached for the length of one
        // `performClick` when it is actually wanted (`openMenu`).
        if let button = statusItem.button {
            button.image = Self.emojiIcon(Self.idleIcon, pt: 15)
            button.target = self
            button.action = #selector(statusItemClicked)
            // Both buttons, and on mouse-UP: the default mask is
            // `.leftMouseUp` alone, so without this a right-click on the item
            // does nothing at all — and the right-click is the escape hatch
            // that keeps the menu reachable while 🛑 owns the left one.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        startBusyPolling()
    }

    /// The whole click rule, in one place:
    ///
    /// | | nothing running | something running |
    /// |---|---|---|
    /// | left click | menu | **stop everything** |
    /// | right click / ⌃-click | menu | menu |
    ///
    /// So the menu is reachable in *both* states by the same gesture, which is
    /// the property that mattered: Quit must never be more than one gesture
    /// away, and "hold ⌃, or use the other button" is a rule that does not
    /// depend on what is happening on screen at the time.
    ///
    /// **The rows of that table are chosen by `isBusy()`, asked right here, at
    /// click time — NOT by which icon happens to be drawn.** They disagree for
    /// up to `busyPollInterval`, and that window is precisely the one that
    /// matters: an effect starts, the bar still shows ⭐ for a third of a
    /// second, and a hand that is already moving lands in it. Reading the drawn
    /// icon would answer that click by *opening a menu* over a demo that has
    /// just gone wrong in front of a room. This is an emergency stop, and an
    /// emergency stop is allowed to look momentarily inconsistent with its own
    /// lamp; it is not allowed to miss. The reverse mismatch is harmless in the
    /// same way — a stale 🛑 over a screen that just went quiet answers with a
    /// `stopAll()` that stops nothing.
    ///
    /// (The icon is still worth drawing, and worth drawing *promptly*: the room
    /// is learning the shortcuts by heart, so this is the one surface a demo can
    /// always be aborted from, and 🛑 is what says so without a word.)
    ///
    /// ⌃-click is spelled out rather than assumed: AppKit turns a control-click
    /// into a contextual-menu event for an ordinary view, but a status item
    /// button delivers it as a plain left click carrying `.control`, so nothing
    /// converts it for us.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event.map {
            $0.type == .rightMouseUp || $0.type == .rightMouseDown
                || $0.modifierFlags.contains(.control)
        } ?? true   // no event to inspect (a synthetic call): the harmless half

        guard !wantsMenu, isBusy?() == true else { openMenu(); return }

        // One click, everything: layered effects, the routed sound, the progress
        // bar and an armed 🔥 whip all go down in this one call (`stopAll`).
        onStopAll?()
        // Repaint now instead of waiting up to `busyPollInterval` for the poll
        // to notice: the click is supposed to feel like the thing that stopped
        // it, and a 🛑 that lingers a third of a second reads as a miss. The
        // poll is still what has the last word — if something survived the
        // stop, the next tick puts 🛑 back.
        refreshIcon()
    }

    /// Show the menu the way a detached menu has to be shown: attach, click the
    /// button *for* AppKit, detach again. The detach happens as soon as
    /// `performClick` returns — that call is modal for as long as the menu is
    /// up, so by then the menu is closed and the button is free for the next
    /// click to reach `statusItemClicked` again.
    ///
    /// `menuWillOpen` still fires from inside this (verified after the switch —
    /// `layOutHints` depends on it, and a menu whose hint column is laid out
    /// from a delegate that never runs comes out with no hints at all).
    private func openMenu() {
        // The one-bool guard is insurance on the assumption the whole dance
        // rests on: that an attached `NSMenu` SWALLOWS `performClick` instead of
        // sending the button's action. If that ever stopped being true, the
        // action would land back in `statusItemClicked`, which would call this
        // again — a menu bar hung in a loop, from a line that looks like a
        // no-op. Cheaper to make it impossible than to debug it in a room.
        guard !openingMenu else { return }
        openingMenu = true
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        openingMenu = false
    }
    private var openingMenu = false

    // MARK: the ⭐ / 🛑 icon

    private func startBusyPolling() {
        busyTimer?.invalidate()
        // Main thread: the timer is scheduled from `applicationDidFinishLaunching`
        // on the main run loop, so both the `isBusy` read (which walks
        // animator/SoundManager state that is main-thread-only) and the image
        // swap happen there.
        busyTimer = Timer.scheduledTimer(withTimeInterval: Self.busyPollInterval, repeats: true) { [weak self] _ in
            self?.refreshIcon()
        }
    }

    private func refreshIcon() {
        let busy = isBusy?() ?? false
        guard busy != showingBusyIcon else { return }   // no needless redraws
        showingBusyIcon = busy
        statusItem?.button?.image = Self.emojiIcon(busy ? Self.busyIcon : Self.idleIcon, pt: 15)
    }

    private func buildMenu() {
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // ⚠️ row, hidden while Accessibility is granted (see setAccessibilityTrusted)
        accessibilityItem = NSMenuItem(title: "⚠️ Grant Accessibility for ⌃W / right-⌘",
                                       action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        accessibilityItem.isEnabled = true
        accessibilityItem.isHidden = true
        menu.addItem(accessibilityItem)

        // The ⚠️ row's separator, and it comes and goes with it. With the panic
        // row gone this separator would otherwise be the FIRST visible item of
        // the menu whenever Accessibility is granted — a stray line above
        // "Effects" — because AppKit only collapses separators it has a reason
        // to, and a hidden item above one is not such a reason.
        accessibilitySeparator = .separator()
        accessibilitySeparator.isHidden = true
        menu.addItem(accessibilitySeparator)

        // The two panel rows. Plain rows and never a checkbox: the panel is
        // always armed now, so the only question a row can answer is "show me
        // that page", and one row per page is how the hold's two pages are
        // taught to a mouse. Their gesture is shown in the right-hand
        // column, the strip ⌃W sits in — see `layOutHints`.
        //
        // One word each, no "Show " in front: the verb was the same on both
        // rows and a menu row is a verb already. What is left is the only part
        // that differs — which board, and the gesture that brings it up.
        //
        // Every row in this menu now opens with a glyph in the same column —
        // ✨ 🎦 🔥 ✅ ⚠️, and ⏻ on Quit — because a menu where only *some* rows
        // do reads as the others being indented (2026-09-14: "🔥 Whip" next to
        // a bare "Effects" was the whole of what looked crooked). One emoji
        // each, the same width, so the words start on one line down the left
        // edge exactly the way the gestures end on one line down the right.
        addPanelRow(title: "✨ Effects", hint: "→⌘", page: .effects)
        addPanelRow(title: "🎦 Videos", hint: "→⌘⇧", page: .videos)

        // 🔥 Whip — ⌃W belongs to the event tap; this row is the fallback when
        // Accessibility is not granted (and the place the shortcut is taught).
        // Kept last of the actions, right above Quit: it is the only row here
        // that fires something at the agent instead of opening a panel.
        //
        // ⌃W is drawn the same way as the panel gestures instead of being a
        // real `keyEquivalent`, because the two schemes cannot share a column:
        // `NSMenu` lays the key equivalents out in a column of their own to the
        // *right* of the titles, so a hint that lives inside a title can never
        // reach that far. All three in one scheme, or none. What is lost is a
        // shortcut that only ever fired while the menu was already open — the
        // real ⌃W is the event tap's, and this row is here for the mouse.
        whipItem = NSMenuItem(title: "🔥 Whip", action: #selector(whipAction), keyEquivalent: "")
        whipItem.target = self
        whipItem.isEnabled = true
        menu.addItem(whipItem)
        giveHint("⌃W", to: whipItem)

        // ✅ Keep Speaker Awake — the Bluetooth keep-alive's switch and its only
        // lamp. It belongs in *this* app (moved here with the effects split) for
        // the same reason the soundboard did: it is audio. It gets a row, unlike
        // everything else that self-gates, because its tone is inaudible by
        // design — without the row there is no way to tell a working keep-alive
        // from a broken one — and because "stop playing into that speaker" is a
        // thing that has to be possible in the middle of a recording or a call.
        //
        // No hint column: there is no key to teach. The title is rewritten on
        // every open (`refreshKeepAliveRow`), which is also why it is built with
        // an empty one — the state is a live read, never a stored flag here.
        keepAliveItem = NSMenuItem(title: "", action: #selector(toggleKeepAliveAction), keyEquivalent: "")
        keepAliveItem.target = self
        keepAliveItem.isEnabled = true
        menu.addItem(keepAliveItem)

        menu.addItem(.separator())

        // The build stamp on its own disabled row, above Quit (2026-09-13). It
        // used to be inlined into the Quit title to save a line; Victor asked
        // for the two to be separated, and for Quit to carry ⌘Q like any app.
        // The shortcut only fires while the menu is open (a status-item app
        // never becomes key), but the hint is what makes the row read as Quit.
        let versionItem = NSMenuItem(title: "Version: " + MenuBar.BUILD_TIME,
                                     action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        // ⌘Q is drawn as a hint like every other gesture here, and Quit carries
        // **no `keyEquivalent`** — that is what fixes the crooked right edge
        // (2026-09-14). `NSMenu` gives key equivalents a column of their own to
        // the RIGHT of every title, so the one native shortcut in the menu was
        // adding ~47 pt the tab stop knew nothing about: ⌘Q sat hard against
        // the menu's edge while →⌘ / →⌘⇧ / ⌃W stopped an icon and a half short
        // of it. Two columns for one kind of information, and no tab stop can
        // reach into the second one — measured, see `layOutHints`.
        //
        // The shortcut itself is not lost: `menuHasKeyEquivalent` claims ⌘Q
        // while the menu is open, which is the only time it could ever have
        // fired (a status-item app never becomes key).
        //
        // ⏻ comes from SF Symbols as an *image*, copied from addons' Quit row
        // (which copied Walkie Talkie's): the text glyph ⏻ is ~12 pt against an
        // emoji's 19 and would sit visibly narrow in a column of emoji, while an
        // image lands in the menu's own icon box, 21 pt wide — near enough to
        // an emoji that the words stay aligned.
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.image = Self.symbolIcon("power")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        giveHint("⌘Q", to: quitItem)
    }

    /// An SF Symbol sized for a menu row's icon box. Template, so AppKit paints
    /// it in the menu's own text colour and inverts it on the highlighted row.
    private static func symbolIcon(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let sized = image.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? image
        sized.isTemplate = true
        return sized
    }

    /// Shown/hidden by `AppDelegate`'s 30 s Accessibility retry.
    func setAccessibilityTrusted(_ trusted: Bool) {
        accessibilityItem?.isHidden = trusted
        accessibilitySeparator?.isHidden = trusted
    }

    // MARK: NSMenuDelegate

    /// The keep-alive row is retitled BEFORE the hints are laid out, never
    /// after: its title is one of the widths `layOutHints` measures the column
    /// from, and a row that changes width after the measurement moves the
    /// column it was supposed to help place.
    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        refreshKeepAliveRow()
        layOutHints()
    }

    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    /// ⌘Q, for the length of one open menu — the shortcut Quit's row gave up
    /// its native `keyEquivalent` for (see `buildMenu`). Claimed here and
    /// nowhere else on purpose: this app has no main menu and never becomes
    /// key, so an unconditional claim could only ever surprise someone — the
    /// thumbnail panel is the one window it owns, and ⌘Q over it must keep
    /// meaning whatever the front app means by it.
    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent,
                              target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        guard menuIsOpen,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "q" else { return false }
        target.pointee = self
        action.pointee = #selector(quitApp)
        return true
    }
    private var menuIsOpen = false

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for row in hintRows {
            row.item.attributedTitle = hintTitle(row, highlighted: row.item === item)
        }
    }

    // MARK: actions

    @objc private func whipAction() { onWhip?() }

    @objc private func toggleKeepAliveAction() {
        onToggleKeepAlive?()
        // Repaint straight away rather than waiting for the next open: on the
        // way *off* the row is the only confirmation that the tone stopped, and
        // AppKit keeps the menu up for the length of the flash it gives the
        // clicked row.
        refreshKeepAliveRow()
    }

    /// One row, one live read. The label names what the switch does, not the
    /// mechanism — "Bluetooth keep-alive" is what it is called in the log and in
    /// `BluetoothKeepAlive`, but the row has to say what it is *for* to someone
    /// looking at it mid-workshop with a JBL on the table.
    private func refreshKeepAliveRow() {
        guard let keepAliveItem else { return }
        let state = keepAliveState?() ?? .off
        keepAliveItem.title = "\(state.emoji) Keep Speaker Awake"
        keepAliveItem.toolTip = {
            switch state {
            case .running: return "A near-silent tone is playing into the Bluetooth speaker so its amp never mutes and the next sound is not clipped. Click to switch it off."
            case .idle: return "Armed, but the default output is not a Bluetooth speaker that needs it. Click to switch it off."
            case .off: return "Switched off: nothing is played into the speaker, and the first sound after a silence may be clipped. Click to switch it back on."
            }
        }()
    }

    @objc private func showPanelAction(_ sender: NSMenuItem) {
        guard let page = sender.representedObject as? PanelPage else { return }
        onShowPanel?(page)
    }

    @objc private func openAccessibilitySettings() {
        // The PROMPTING check, not the quiet one the app uses at launch. An app
        // that has only ever called `AXIsProcessTrusted()` does not appear in the
        // Accessibility list at all, so opening the pane would show Victor a list
        // without this app in it and no obvious way in short of the "+" button
        // and a trip through /Applications. Asking registers it.
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if !AXIsProcessTrustedWithOptions(options) {
            // Asking is a no-op once it has been denied — macOS never puts the
            // dialog up a second time. Say so here too, because this row is
            // where someone lands when the launch prompt did nothing.
            effectsInfo("🔐 Accessibility still not granted. If no dialog appeared it was denied before: "
                + "tick Victor Effects in the pane that is about to open, or clear the denial with "
                + "`tccutil reset Accessibility ro.victorrentea.victor-effects` and restart the app.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        effectsInfo("Quit")
        onQuit?()
        exit(0)
    }

    // MARK: helpers

    /// One panel row: the title on the left, the gesture that does the same
    /// thing without the mouse over on the right, in the same column ⌃W uses.
    private func addPanelRow(title: String, hint: String, page: PanelPage) {
        let item = NSMenuItem(title: title, action: #selector(showPanelAction(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        item.representedObject = page
        menu.addItem(item)
        giveHint(hint, to: item)
    }

    /// Put `hint` in the right-hand column of an already-built row.
    ///
    /// It takes the row, never a title, because `layOutHints` re-lays each row
    /// from `HintRow.title`: a hint registered with a *second copy* of the
    /// title would quietly rename the row back to that copy the first time the
    /// menu opened. Reading `item.title` here means there is only ever one
    /// place a row's words are written down. (The renames of 2026-09-13 —
    /// `Show Effect Panel` → `Effects`, `🔥 Whip Agent` → `🔥 Whip` — are
    /// exactly the edit that would have hit that trap.)
    private func giveHint(_ hint: String, to item: NSMenuItem) {
        hintRows.append(HintRow(item: item, title: item.title, hint: hint,
                                indent: Self.imageColumn(for: item.image)))
    }

    /// How much an `NSMenuItem.image` pushes that row's text to the right,
    /// asked of `NSMenu` itself instead of being written down: build the same
    /// row twice, once with the image and once without, and take the
    /// difference. (21 pt for the 13 pt ⏻ on this Mac — but a number that comes
    /// from the OS cannot go stale the way the same number typed here would.)
    private static func imageColumn(for image: NSImage?) -> CGFloat {
        guard let image else { return 0 }
        func width(_ img: NSImage?) -> CGFloat {
            let probe = NSMenu()
            let row = NSMenuItem(title: "X", action: nil, keyEquivalent: "")
            row.image = img
            probe.addItem(row)
            return probe.size.width
        }
        return width(image) - width(nil)
    }

    /// Right-aligns every gesture hint in one column down the right edge.
    ///
    /// `NSMenuItem` will not put the panel gestures there by itself: each one
    /// is a *held* modifier, and a key equivalent cannot be a modifier on its
    /// own — `keyEquivalentModifierMask` needs a key to hang off, and only the
    /// first character of `keyEquivalent` is ever drawn, so no amount of ⌘/⇧/→
    /// in that string comes out as "→⌘". What does work is an attributed title
    /// with a right-aligned tab stop, which is what this builds. (The arrow is
    /// the *side of the keyboard* — →⌘ is the right ⌘ key, the one the hold
    /// listens for. The left one is deliberately not a trigger.)
    ///
    /// The tab stop has to be recomputed rather than hardcoded, because the
    /// column it defines moves: the ⚠️ row is by far the widest title in the
    /// menu and it comes and goes with the Accessibility grant. Measure the
    /// menu with plain titles, and a tab stop at `width - titleInsets` puts the
    /// hints on exactly the inset `NSMenu` would have right-aligned them to.
    private func layOutHints() {
        guard !hintRows.isEmpty else { return }
        let font = NSFont.menuFont(ofSize: 0)
        for row in hintRows {
            row.item.attributedTitle = nil
            row.item.title = row.title
        }
        var width = menu.size.width
        for row in hintRows {
            let text = row.indent
                + (row.title as NSString).size(withAttributes: [.font: font]).width
                + Self.hintGap
                + (row.hint as NSString).size(withAttributes: [.font: font]).width
            width = max(width, text + Self.titleInsets)
        }
        hintTabStop = width - Self.titleInsets
        for row in hintRows { row.item.attributedTitle = hintTitle(row, highlighted: false) }
    }

    /// The trap the first attempt fell into: an attributed title is drawn with
    /// the colours it carries, so a grey hint stays grey — muddy — when the row
    /// highlights, and a `labelColor` title stays dark on the blue. Hence the
    /// repaint from `menu(_:willHighlight:)`; nothing else about the string
    /// changes, so the row does not move while the pointer crosses it.
    private func hintTitle(_ row: HintRow, highlighted: Bool) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        // Minus the row's own icon box: the tab stop is measured from where the
        // row's text starts, and on an image row that is one icon in.
        style.tabStops = [NSTextTab(textAlignment: .right, location: hintTabStop - row.indent, options: [:])]
        let font = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString(
            string: row.title + "\t",
            attributes: [.font: font,
                         .paragraphStyle: style,
                         .foregroundColor: highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor])
        result.append(NSAttributedString(
            string: row.hint,
            attributes: [.font: font,
                         .paragraphStyle: style,
                         .foregroundColor: highlighted ? NSColor.selectedMenuItemTextColor : NSColor.secondaryLabelColor]))
        return result
    }

    /// An emoji rendered into a status-item-sized image. A plain `button.title`
    /// works too but sits on a different baseline than every icon-based item in
    /// the bar, so ⭐ ends up visibly lower than its neighbours.
    static func emojiIcon(_ emoji: String, pt: CGFloat) -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: pt)]
        let str = NSAttributedString(string: emoji, attributes: attrs)
        let strSize = str.size()
        str.draw(at: NSPoint(x: (size.width - strSize.width) / 2,
                             y: (size.height - strSize.height) / 2))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
