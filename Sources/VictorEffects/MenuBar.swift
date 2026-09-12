import AppKit
import ApplicationServices
import Foundation

/// The 💥 status item. Deliberately tiny compared to the addons menu it was cut
/// from, and smaller again since the panel arrived: a 39-row ⭐️ Effects submenu
/// was a menu of words for a board of pictures, so what is left is the panic
/// row, the two features that need a no-Accessibility fallback (⌃W and the
/// panel, one row per page), and Quit.
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

        // 🔥 Whip — ⌃W belongs to the event tap; this row is the fallback when
        // Accessibility is not granted (and the place the shortcut is taught).
        whipItem = NSMenuItem(title: "🔥 Whip Agent", action: #selector(whipAction), keyEquivalent: "w")
        whipItem.keyEquivalentModifierMask = .control
        whipItem.target = self
        whipItem.isEnabled = true
        menu.addItem(whipItem)

        // The two panel rows. Plain rows and never a checkbox: the panel is
        // always armed now, so the only question a row can answer is "show me
        // that page", and one row per page is how the hold's two pages are
        // taught to a mouse.
        //
        // **The hint is part of the title.** The gesture is a *held* right ⌘,
        // and an `NSMenuItem` key equivalent cannot be a modifier on its own —
        // `keyEquivalentModifierMask` needs a key to hang off. An attributed
        // title with a grey run was the other candidate and was dropped: the
        // secondary colour does not turn white when the row highlights, so the
        // hint goes muddy exactly when the pointer is on it.
        addPanelRow(title: "Show Effect Panel", hint: "Right ⌘", page: .effects)
        addPanelRow(title: "Show Video Panel", hint: "Right ⌘⇧", page: .videos)

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

    /// One panel row: the title, three spaces, the gesture that does the same
    /// thing without the mouse. Three spaces and not a tab — `NSMenu` lays a tab
    /// out as one space, so `\t` would read as a typo rather than as a gap.
    private func addPanelRow(title: String, hint: String, page: PanelPage) {
        let item = NSMenuItem(title: "\(title)   (\(hint))",
                              action: #selector(showPanelAction(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        item.representedObject = page
        menu.addItem(item)
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
