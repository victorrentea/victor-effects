import AppKit
import Foundation

/// "I clicked the app again, so give me a fresh one."
///
/// `main.swift` already implements a correct hand-over between instances: a new
/// process writes its pid to `/tmp/VictorEffects.pid`, SIGTERMs the old one,
/// SIGKILLs it if it does not go quietly, and the old instance also notices the
/// stolen lock file within 2s and leaves. That machinery has never been the
/// problem.
///
/// The problem is that **it almost never gets to run**. LaunchServices treats an
/// `open` of an already-running bundle as an *activation*, not a launch: no
/// second process starts, so nothing ever writes a new pid. Clicking the app in
/// Spotlight while it was wedged therefore did precisely nothing, and the only
/// way out was `pkill` in a terminal.
///
/// This closes that gap from the other side: the running instance turns the
/// reopen it *does* receive into a restart, and relaunches itself.
///
/// The relaunch is done by a **detached shell helper**, not by us, because the
/// one thing that must survive is the relaunch itself. The helper waits for our
/// pid to disappear and only then runs `open -n`, so it works identically
/// whether we exit cleanly, are SIGKILLed, or crash on the way out — and if we
/// somehow never die, it gives up after ~10s and launches anyway.
enum AppRelaunch {
    private static var relaunching = false

    /// Guard against a burst of reopen events (each Spotlight ⏎ can deliver more
    /// than one) turning into a pile of helpers.
    static func relaunch(reason: String) {
        assert(Thread.isMainThread)
        guard !relaunching else {
            effectsInfo("Relaunch already in flight — ignoring '\(reason)'")
            return
        }
        relaunching = true
        effectsInfo("Relaunching: \(reason)")

        guard spawnRelaunchHelper() else {
            // Better a live old instance than no instance at all.
            relaunching = false
            effectsError("Relaunch helper failed to spawn — staying up")
            return
        }

        // Hand off cleanly so the new instance inherits a Mac with no stale
        // event tap and a free HTTP port.
        (NSApp.delegate as? AppDelegate)?.tearDownForReplacement()
        exit(0)
    }

    /// The relaunch target: the `.app` when we run from a bundle (the normal
    /// case), else the bare executable so `swift run` during development
    /// restarts too.
    private static func relaunchCommand() -> String {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            // -n forces a genuinely new process even if LaunchServices still
            // believes the dying one counts as "running".
            return #"exec /usr/bin/open -n "$VE_RELAUNCH_TARGET""#
        }
        return #"exec "$VE_RELAUNCH_TARGET""#
    }

    private static func relaunchTarget() -> String {
        let bundle = Bundle.main.bundleURL
        return bundle.pathExtension == "app" ? bundle.path : CommandLine.arguments[0]
    }

    private static func spawnRelaunchHelper() -> Bool {
        let pid = getpid()
        // 100 × 0.1s = a 10s ceiling. Launching over a still-running instance is
        // survivable (the pid-file handshake sorts it out); never launching at
        // all is not — so the timeout falls through to `open` rather than
        // giving up.
        let script = """
        for _ in $(seq 1 100); do
          kill -0 \(pid) 2>/dev/null || break
          sleep 0.1
        done
        \(relaunchCommand())
        """

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        // The path travels in the environment, NOT in argv, so the helper's
        // command line never contains "Victor Effects" — otherwise the deploy
        // habit of `pkill -f "Victor Effects"` would match and kill the very
        // helper whose job is to bring the app back.
        var env = ProcessInfo.processInfo.environment
        env["VE_RELAUNCH_TARGET"] = relaunchTarget()
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            return true
        } catch {
            effectsError("Relaunch helper: \(error)")
            return false
        }
    }
}
