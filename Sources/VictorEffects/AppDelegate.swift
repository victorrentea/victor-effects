import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pidFilePath: String
    private let myPID: Int32

    let menuBar = MenuBar()

    private var overlayPanel: OverlayPanel!
    private(set) var engine: EffectsEngine!
    private(set) var router: EffectsRouter!
    private var server: EffectsHttpServer!
    private var hotkeyTap: EffectsHotkeyTap!
    private var coffeeMonitor: CoffeeChargeMonitor!
    private var panelController: ThumbnailPanelController!
    private var keepAlive: BluetoothKeepAlive?
    private var accessibilityRetry: Timer?

    init(pidFilePath: String, myPID: Int32) {
        self.pidFilePath = pidFilePath
        self.myPID = myPID
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = EffectsConfig.shared   // logs what it loaded

        // Both grants are asked for ONCE, here, before anything needs them.
        requestPermissionsAtLaunch()

        guard !NSScreen.screens.isEmpty else { fatalError("No screens available") }
        overlayPanel = OverlayPanel(screen: Screens.overlayScreen() ?? NSScreen.screens[0])
        overlayPanel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        engine = EffectsEngine(overlayPanel: overlayPanel)
        engine.startWatchdog()

        router = EffectsRouter(engine: engine)
        // The tap IS the feature now: the checkbox that used to have to agree
        // with it is gone, so `panelMonitor` means exactly "the right-⌘ hold is
        // being watched".
        router.panelMonitorActive = { [weak self] in self?.hotkeyTap?.isActive == true }

        panelController = ThumbnailPanelController(router: router)
        panelController.claimRouterHooks()

        server = EffectsHttpServer(router: router)
        server.start(port: EffectsConfig.shared.port)

        coffeeMonitor = CoffeeChargeMonitor(animator: engine.animator)
        coffeeMonitor.start()

        keepAlive = BluetoothKeepAlive()
        keepAlive?.start()

        installHotkeyTap()

        menuBar.setup()
        menuBar.onStopAll = { [weak self] in self?.engine.stopAll() }
        // The 🛑 face of the status item. Handed the engine's own answer rather
        // than a flag this class would have to keep in step: anything that
        // starts or ends an effect — a route, a tile press, the panel, an
        // effect's own self-termination timer — moves it without knowing the
        // menu bar exists.
        menuBar.isBusy = { [weak self] in self?.engine.isAnythingRunning ?? false }
        menuBar.onWhip = { [weak self] in self?.engine.toggleWhip() }
        menuBar.onShowPanel = { [weak self] page in self?.panelController.showFromMenu(page: page) }
        menuBar.onQuit = { [weak self] in self?.tearDownForReplacement() }

        // Warm the manifest (a few MB of SHA-256) off the main thread: /ping is
        // proxied with about a 1.5 s budget and answers from this cache only.
        SoundsManifest.warm()
        DispatchQueue.global(qos: .utility).async { _ = TilesManifest.tilesHash }
        // Same for the brother GIF, whose decode is long enough to be visible.
        EmojiAnimator.warmBrotherCache()

        effectsInfo("Victor Effects ready — build \(MenuBar.BUILD_TIME), port \(EffectsConfig.shared.port)")
    }

    // MARK: - Hotkeys

    private func installHotkeyTap() {
        let tap = EffectsHotkeyTap()
        hotkeyTap = tap
        tap.whipShowing = { [weak self] in self?.engine.whipIsShowing ?? false }
        tap.onToggleWhip = { [weak self] in self?.engine.toggleWhip() }
        tap.onCrack = { [weak self] in self?.engine.whip?.forceCrack() }
        // The panel is a listener on this tap, never an owner: `onRightCommand`
        // fires on the way past and the event continues to the front app.
        tap.onRightCommand = { [weak self] down in self?.panelController.rightCommand(down: down) }
        tap.onRightShift = { [weak self] down in self?.panelController.rightShift(down: down) }
        tap.onKeyWhileRightCommand = { [weak self] in self?.panelController.keyWhileRightCommand() }

        if tap.start() {
            menuBar.setAccessibilityTrusted(true)
            return
        }
        menuBar.setAccessibilityTrusted(false)
        // Retry rather than give up: the grant usually arrives a minute after
        // the first launch, and an app that needs restarting to notice is an app
        // that gets reported as broken.
        accessibilityRetry?.invalidate()
        accessibilityRetry = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.hotkeyTap.start() {
                self.menuBar.setAccessibilityTrusted(true)
                t.invalidate()
                self.accessibilityRetry = nil
            }
        }
    }

    @objc private func screensChanged() {
        overlayPanel?.refreshScreenFrame()
    }

    // MARK: - Permissions

    /// Ask for **both** grants once, at launch, with the prompting calls.
    ///
    /// Accessibility used to be checked quietly here, on the argument that a
    /// modal at login is one nobody can usefully answer. The argument is wrong
    /// in the only way that matters: **the prompting call is also the
    /// registration**. An app that has only ever called `AXIsProcessTrusted()`
    /// is not a privacy client at all, so System Settings shows a list without
    /// it in it, and "grant Accessibility" becomes a trip through `+` and
    /// /Applications that nobody completes. `AXIsProcessTrustedWithOptions`
    /// puts the row in the pane; the dialog is the side effect, not the point.
    ///
    /// Once per launch, never in the 30 s retry: the retry asks quietly
    /// (`tap.start()` → `AXIsProcessTrusted()`), so a grant that arrives a
    /// minute later still installs the tap without a restart, and a denial does
    /// not turn into a dialog every half minute.
    private func requestPermissionsAtLaunch() {
        // --- Accessibility (the one CGEventTap: ⌃W, the crack, right ⌘) ---
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        effectsInfo(axTrusted
            ? "🔐 Accessibility: granted"
            : "🔐 Accessibility: NOT granted — asked, so the app is now listed in "
              + "System Settings → Privacy & Security → Accessibility")

        // --- Screen Recording (the effects that distort what is on screen) ---
        // CGPreflightScreenCaptureAccess correctly returns false when permission
        // is not granted. (CGDisplayCreateImage always succeeds but captures
        // only the desktop wallpaper when denied — a silent wrong answer, which
        // is why this one is worth a line in the log on every launch.)
        let capture = CGPreflightScreenCaptureAccess()
        effectsInfo("🔐 Screen Recording (CGPreflightScreenCaptureAccess): \(capture ? "granted" : "NOT granted")")
        if !capture {
            CGRequestScreenCaptureAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !CGPreflightScreenCaptureAccess() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
            }
        }

        // The failure mode that cost a day: **macOS asks once.** After a "Don't
        // Allow" (or a dialog dismissed at login), the row sits in TCC with
        // auth_value 0 and every later `CGRequestScreenCaptureAccess()` and
        // prompting `AXIsProcessTrustedWithOptions` is a silent no-op — no
        // dialog, no error, nothing in the pane moving. The only ways out are a
        // human ticking the box or `tccutil reset`, so the log says both rather
        // than leaving a person to rediscover it.
        if !axTrusted || !capture {
            effectsInfo("🔐 No dialog? Then it was denied before, and macOS never asks twice. "
                + "Tick the row by hand in System Settings, or clear the denial with: "
                + "tccutil reset Accessibility ro.victorrentea.victor-effects ; "
                + "tccutil reset ScreenCapture ro.victorrentea.victor-effects")
        }
    }

    // MARK: - Lifecycle

    /// Reopening the bundle (Spotlight ⏎, Finder, `open`) means "give me a fresh
    /// one", not "bring the wedged one forward" — see `AppRelaunch`.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppRelaunch.relaunch(reason: "reopened from Finder/Spotlight")
        return true
    }

    /// Called from `main.swift` on SIGTERM and on a pid-file takeover, and from
    /// `AppRelaunch` before it exits. Must be idempotent.
    func tearDownForReplacement() {
        effectsInfo("Tearing down")
        coffeeMonitor?.stop()
        // Release the port before the replacement tries to bind it — the
        // listener sets allowLocalEndpointReuse, but a stale listener answering
        // requests the new instance should own is worse than a moment's 503.
        server?.stop()
        engine?.stopAll()
    }
}
