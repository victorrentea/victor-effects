import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pidFilePath: String
    private let myPID: Int32

    let menuBar = MenuBar()

    init(pidFilePath: String, myPID: Int32) {
        self.pidFilePath = pidFilePath
        self.myPID = myPID
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        EffectsConfig.shared.reload()
        menuBar.setup()
        menuBar.onQuit = { [weak self] in self?.tearDownForReplacement() }
        effectsInfo("Victor Effects ready — build \(MenuBar.BUILD_TIME)")
    }

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
    }
}
