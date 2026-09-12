import AppKit
import ApplicationServices
import Foundation

/// The 💥 status item. Deliberately tiny compared to the addons menu it was cut
/// from: this app has one job, so the menu is the effect list, the two hotkey
/// features that need a no-Accessibility fallback, and Quit.
final class MenuBar: NSObject, NSMenuDelegate {
    /// Rewritten in place by `build-app.sh` before every release build, so the
    /// Quit row always says which binary is actually running.
    static let BUILD_TIME = "Sep 12, 15:04"

    // MARK: callbacks (AppDelegate wires them)

    /// A row of the ⭐️ Effects submenu was clicked: the effect's route name.
    var onEffect: ((String) -> Void)?
    /// 🔥 Whip Agent — the menu equivalent of ⌃W, kept for a Mac that has not
    /// granted Accessibility (same rationale as addons' 📤 Mail clipboard row).
    var onWhip: (() -> Void)?
    /// Hook point for the thumbnail panel (WI-4): checkbox state changed.
    var onTogglePanel: ((Bool) -> Void)?
    /// Hook point for the thumbnail panel (WI-4): "Show tablet panel now".
    var onShowPanelNow: (() -> Void)?
    /// Hook point for the thumbnail panel (WI-4): "Reload tiles.json".
    var onReloadTiles: (() -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var panelItem: NSMenuItem!
    private var whipItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!

    /// `object(forKey:) as? Bool ?? true` and not `bool(forKey:)`: an unset key
    /// reads `false` from the latter, which would ship the panel switched off
    /// for everyone who never touched the checkbox.
    static let kPanelEnabled = "ThumbnailPanel.enabled"
    static var panelEnabled: Bool {
        get { UserDefaults.standard.object(forKey: kPanelEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: kPanelEnabled) }
    }

    /// Effect route name per row. Same list, same order as the addons submenu
    /// this replaces, so muscle memory survives the move.
    static let effectPairs: [(String, String)] = [
        ("Heart ❤️",        "heart"),
        ("Confetti 🎊",     "confetti"),
        ("Zorro",           "zorro"),
        ("Fear 😱",         "fear"),
        ("Old Film 📽️",    "sepia"),
        ("Fail Stamp",      "fail"),
        ("Fireworks 🎆",    "fireworks"),
        ("Applause 👏",     "applause"),
        ("Nuke ☢️",          "explosion"),
        ("Broken Glass 💥", "broken-glass"),
        ("Game Over",       "game-over"),
        ("Pulse",           "pulse"),
        ("Fire Alarm 🚨",    "fire-alarm"),
        ("Bullet Holes 🎯",  "bullet-holes"),
        ("Phone Ring 📱",   "phone-ring"),
        ("FBI Knock 🚪",    "fbi-knock"),
        ("Beethoven 🎼",     "beethoven"),
        ("Brother 🤢",       "brother"),
        ("Gangnam 💃",       "gangnam"),
        ("Love Hands 🤲",   "love-hands"),
        ("Death Star ☠️",    "star-wars"),
        ("Gong 🔔",          "gong"),
        ("Rainbow 🌈",       "rainbow"),
        ("Snow ❄️",          "snow"),
        ("Cavalry 🐎",       "cavalry"),
        ("Counter-Strike 🔫", "counter-strike"),
        ("Wasn't Me 🙅", "wasnt-me"),
        ("Chainsaw Cursor 🪚", "chainsaw"),
        ("Fire Cursor 🔥",    "fire"),
        ("Microwave ⏲️",      "microwave"),
        ("Wrong X ❌",        "wrong-x"),
        ("Drum Roll 🥁",     "drum-roll"),
        ("Phoenix 🔥",        "phoenix"),
        ("Money 💸",          "money"),
        ("Laugh 🤣",          "laugh"),
        ("Corner Confetti 🎉", "corner-confetti"),
        ("Heartbeat 💓",      "heartbeat"),
        ("Spiral Hearts 💘",  "spiral-hearts"),
        ("Green Flash 🟢",    "green-flash"),
    ]

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

        let effectsItem = NSMenuItem(title: "⭐️ Effects", action: nil, keyEquivalent: "")
        effectsItem.isEnabled = true
        let effectsSubmenu = NSMenu()
        effectsItem.submenu = effectsSubmenu
        for (title, name) in Self.effectPairs {
            let item = NSMenuItem(title: title, action: #selector(effectAction(_:)), keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            item.representedObject = name
            effectsSubmenu.addItem(item)
        }
        menu.addItem(effectsItem)

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

        panelItem = NSMenuItem(title: "Show tablet panel on right-⌘ hold",
                               action: #selector(togglePanelAction), keyEquivalent: "")
        panelItem.target = self
        panelItem.isEnabled = true
        panelItem.state = Self.panelEnabled ? .on : .off
        menu.addItem(panelItem)

        let showNow = NSMenuItem(title: "Show tablet panel now", action: #selector(showPanelNowAction), keyEquivalent: "")
        showNow.target = self
        showNow.isEnabled = true
        menu.addItem(showNow)

        let reload = NSMenuItem(title: "Reload tiles.json", action: #selector(reloadTilesAction), keyEquivalent: "")
        reload.target = self
        reload.isEnabled = true
        menu.addItem(reload)

        menu.addItem(.separator())

        let configItem = NSMenuItem(title: "Open config folder", action: #selector(openConfigFolder), keyEquivalent: "")
        configItem.target = self
        configItem.isEnabled = true
        menu.addItem(configItem)

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

    @objc private func effectAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        onEffect?(name)
    }

    @objc private func stopAllAction() { onEffect?("stop-all") }
    @objc private func whipAction() { onWhip?() }

    @objc private func togglePanelAction() {
        let enabled = !(panelItem.state == .on)
        panelItem.state = enabled ? .on : .off
        Self.panelEnabled = enabled
        onTogglePanel?(enabled)
    }

    @objc private func showPanelNowAction() { onShowPanelNow?() }
    @objc private func reloadTilesAction() { onReloadTiles?() }

    @objc private func openConfigFolder() {
        let dir = EffectsConfig.configDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
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
