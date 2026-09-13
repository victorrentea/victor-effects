import AppKit
import ApplicationServices
import Foundation

/// The 💥 status item. Deliberately tiny compared to the addons menu it was cut
/// from, and smaller again since the panel arrived: a 39-row ⭐️ Effects submenu
/// was a menu of words for a board of pictures, so what is left is the two
/// features that need a no-Accessibility fallback (the panel, one row per page,
/// and ⌃W), and Quit.
///
/// The panic row went the same way, but *upwards* rather than out: stop-all is
/// now **the icon itself**. While anything is running the 💥 turns 🛑 and a
/// left click stops everything, which is one gesture instead of two (click,
/// aim, click) at the exact moment nobody wants to aim — the effect is on the
/// screen the room is watching. A menu row that is only ever wanted while the
/// menu is hard to read was the wrong home for it.
final class MenuBar: NSObject, NSMenuDelegate {
    /// Rewritten in place by `build-app.sh` before every release build, so the
    /// Quit row always says which binary is actually running.
    static let BUILD_TIME = "Sep 13, 09:02"

    // MARK: callbacks (AppDelegate wires them)

    /// 🛑 Stop all. No longer a row: this fires on a plain click of the status
    /// item while it is showing 🛑 (see `statusItemClicked`).
    var onStopAll: (() -> Void)?
    /// Is anything on screen or audible right now? Polled (see
    /// `startBusyPolling`) to pick between 💥 and 🛑. Wired by `AppDelegate` to
    /// `EffectsEngine`, which already answers this for `GET /state`.
    var isBusy: (() -> Bool)?
    /// 🔥 Whip — the menu equivalent of ⌃W, kept for a Mac that has not
    /// granted Accessibility (same rationale as addons' 📤 Mail clipboard row).
    var onWhip: (() -> Void)?
    /// One of the two panel rows was clicked: show that page of the thumbnail
    /// panel. The mouse-only way in, for a Mac without the Accessibility grant.
    var onShowPanel: ((PanelPage) -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var whipItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var accessibilitySeparator: NSMenuItem!

    /// The two faces of the status item. 🛑 means "something is running, and a
    /// click here stops it"; 💥 means "nothing is running, a click opens the
    /// menu". Nothing else is ever drawn there.
    private static let idleIcon = "💥"
    private static let busyIcon = "🛑"

    /// Which of the two is on screen right now. The **click rule reads this,
    /// not `isBusy`**: what a click does must be what the icon was promising
    /// when the mouse went down, even if the last effect ended in between.
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
    }
    private var hintRows: [HintRow] = []
    private var hintTabStop: CGFloat = 0

    /// What `NSMenu` adds around a title: a menu holding one item whose title
    /// has a right tab stop at L comes out L + 30 wide, and a native key
    /// equivalent is right-aligned against that same inset. Measured, not
    /// documented — hence `layOutHints` re-deriving the stop from the
    /// menu's own width instead of trusting this number on its own.
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
    /// | | 💥 idle | 🛑 running |
    /// |---|---|---|
    /// | left click | menu | **stop everything** |
    /// | right click / ⌃-click | menu | menu |
    ///
    /// So the menu is reachable in *both* states by the same gesture, which is
    /// the property that mattered: Quit must never be more than one gesture
    /// away, and "hold ⌃, or use the other button" is a rule that does not
    /// depend on what is happening on screen at the time.
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

        guard !wantsMenu, showingBusyIcon else { openMenu(); return }

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

    // MARK: the 💥 / 🛑 icon

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
        addPanelRow(title: "Effects", hint: "→⌘", page: .effects)
        addPanelRow(title: "Videos", hint: "→⌘⇧", page: .videos)

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

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit – built " + MenuBar.BUILD_TIME,
                                  action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
    }

    /// Shown/hidden by `AppDelegate`'s 30 s Accessibility retry.
    func setAccessibilityTrusted(_ trusted: Bool) {
        accessibilityItem?.isHidden = trusted
        accessibilitySeparator?.isHidden = trusted
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) { layOutHints() }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for row in hintRows {
            row.item.attributedTitle = hintTitle(row, highlighted: row.item === item)
        }
    }

    // MARK: actions

    @objc private func stopAllAction() { onStopAll?() }
    @objc private func whipAction() { onWhip?() }

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
        hintRows.append(HintRow(item: item, title: item.title, hint: hint))
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
            let text = (row.title as NSString).size(withAttributes: [.font: font]).width
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
        style.tabStops = [NSTextTab(textAlignment: .right, location: hintTabStop, options: [:])]
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
    /// the bar, so 💥 ends up visibly lower than its neighbours.
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
