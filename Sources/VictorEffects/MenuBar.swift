import AppKit
import ApplicationServices
import Foundation

/// The 💥 status item. Deliberately tiny compared to the addons menu it was cut
/// from, and smaller again since the panel arrived: a 39-row ⭐️ Effects submenu
/// was a menu of words for a board of pictures, so what is left is the panic
/// row, the two features that need a no-Accessibility fallback (the panel, one
/// row per page, and ⌃W), and Quit.
final class MenuBar: NSObject, NSMenuDelegate {
    /// Rewritten in place by `build-app.sh` before every release build, so the
    /// Quit row always says which binary is actually running.
    static let BUILD_TIME = "Sep 12, 21:46"

    // MARK: callbacks (AppDelegate wires them)

    /// 🛑 Stop all — the panic row, and the only thing left of the effect menu.
    var onStopAll: (() -> Void)?
    /// 🔥 Whip Agent — the menu equivalent of ⌃W, kept for a Mac that has not
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
        statusItem.button?.image = Self.emojiIcon("💥", pt: 15)
        statusItem.menu = menu
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

        let stopItem = NSMenuItem(title: "🛑 Stop all", action: #selector(stopAllAction), keyEquivalent: "")
        stopItem.target = self
        stopItem.isEnabled = true
        menu.addItem(stopItem)

        menu.addItem(.separator())

        // The two panel rows. Plain rows and never a checkbox: the panel is
        // always armed now, so the only question a row can answer is "show me
        // that page", and one row per page is how the hold's two pages are
        // taught to a mouse. Their gesture is shown in the right-hand
        // column, the strip ⌃W sits in — see `layOutHints`.
        addPanelRow(title: "Show Effect Panel", hint: "→⌘", page: .effects)
        addPanelRow(title: "Show Video Panel", hint: "→⌘⇧", page: .videos)

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
        whipItem = NSMenuItem(title: "🔥 Whip Agent", action: #selector(whipAction), keyEquivalent: "")
        whipItem.target = self
        whipItem.isEnabled = true
        menu.addItem(whipItem)
        hintRows.append(HintRow(item: whipItem, title: "🔥 Whip Agent", hint: "⌃W"))

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
        hintRows.append(HintRow(item: item, title: title, hint: hint))
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
