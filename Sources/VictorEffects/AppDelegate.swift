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
    private var keepAlive: BluetoothKeepAlive?
    private var accessibilityRetry: Timer?

    init(pidFilePath: String, myPID: Int32) {
        self.pidFilePath = pidFilePath
        self.myPID = myPID
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = EffectsConfig.shared   // logs what it loaded

        // Accessibility: check, never prompt. The prompt is a modal the user
        // cannot answer usefully at launch, and the tap retries every 30 s
        // anyway. Screen Recording DOES prompt: the effects that distort what is
        // on screen silently capture wallpaper without it, which looks like a
        // bug rather than a missing permission.
        requestScreenRecordingPermissions(promptUser: true)

        guard !NSScreen.screens.isEmpty else { fatalError("No screens available") }
        overlayPanel = OverlayPanel(screen: Screens.overlayScreen() ?? NSScreen.screens[0])
        overlayPanel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        engine = EffectsEngine(overlayPanel: overlayPanel)
        engine.startWatchdog()

        router = EffectsRouter(engine: engine)
        router.panelMonitorActive = { [weak self] in self?.hotkeyTap?.isActive == true && MenuBar.panelEnabled }

        server = EffectsHttpServer(router: router)
        server.start(port: EffectsConfig.shared.port)

        coffeeMonitor = CoffeeChargeMonitor(animator: engine.animator)
        coffeeMonitor.start()

        keepAlive = BluetoothKeepAlive()
        keepAlive?.start()

        installHotkeyTap()

        menuBar.setup()
        menuBar.onEffect = { [weak self] name in
            guard let self else { return }
            // The menu goes through `menuEffect`, not `runEffect`: menu runs are
            // silent and fixed-length because no sound's duration is available
            // to end a looping effect.
            name == "stop-all" ? self.engine.stopAll() : self.engine.menuEffect(name)
        }
        menuBar.onWhip = { [weak self] in self?.engine.toggleWhip() }
        menuBar.onReloadTiles = { [weak self] in
            TilesManifest.invalidate()
            let count = TilesManifest.load()?.doc.tiles.count ?? 0
            effectsInfo("tiles.json reloaded: \(count) tiles")
            _ = self
        }
        menuBar.onQuit = { [weak self] in self?.tearDownForReplacement() }

        // Warm the manifest (a few MB of SHA-256) off the main thread so the
        // first /ping does not pay for it.
        DispatchQueue.global(qos: .utility).async {
            _ = SoundsManifest.combinedHash
            _ = TilesManifest.tilesHash
        }
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
        // Hook point for the thumbnail panel (WI-4): a no-op until the panel
        // controller claims it. The tap never swallows right ⌘, so leaving it
        // unclaimed costs nothing.
        tap.onRightCommand = { _ in }
        tap.onKeyWhileRightCommand = { }

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

    private func requestScreenRecordingPermissions(promptUser: Bool) {
        // CGPreflightScreenCaptureAccess correctly returns false when permission
        // is not granted. (CGDisplayCreateImage always succeeds but captures
        // only the desktop wallpaper when denied — a silent wrong answer.)
        if CGPreflightScreenCaptureAccess() { return }
        effectsInfo("⚠️ Screen Recording not granted (System Settings → Privacy & Security → Screen Recording)")
        guard promptUser else { return }
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !CGPreflightScreenCaptureAccess() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }
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
