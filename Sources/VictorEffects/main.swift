import AppKit
import Darwin
import Foundation

// --- Uniform logging ---
// When launched via `open` (Spotlight, Finder, Login Items, manual `open`),
// stdout/stderr go to the unified system log and `/tmp/victor-effects.log`
// stops getting written. Detect that case and redirect ourselves, so launches
// via start.sh AND launches via `open` behave identically log-wise.
func redirectLogsIfNeeded() {
    let logPath = "/tmp/victor-effects.log"
    var st = stat()
    let isRegular = fstat(fileno(stderr), &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
    if isRegular { return }  // start.sh already redirected for us
    let fd = open(logPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    if fd < 0 { return }
    setvbuf(stdout, nil, _IOLBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
    dup2(fd, fileno(stdout))
    dup2(fd, fileno(stderr))
    close(fd)
}
redirectLogsIfNeeded()

// --- Launch identity: LaunchServices, never our own path ---
// **macOS keys a privacy grant to a bundle identifier only for a process it
// launched itself.** A process that starts its own Mach-O is filed by PATH
// instead — a second, unrelated privacy client that happens to share a name,
// wearing the generic `exec` icon macOS gives an unbundled binary. Ticking its
// box in System Settings grants that row and not this app, and the feature stays
// dead with a checkbox next to its name still on. `start.sh` therefore `exec`s
// `open`; this is the backstop for the other way in, which is a person running
// `.../Contents/MacOS/Victor Effects` from a shell to watch the log on stdout.
//
// It runs before the pid-file takeover below, so a stray direct launch never
// stands the healthy instance down on its way to being relaunched properly.
//
// A `swift build` binary is left alone: it lives in `.build`, not inside a
// `.app`, so it has no bundle identity to be mistaken for, and every test and
// `swift run` works exactly as before. `VICTOR_EFFECTS_ALLOW_DIRECT=1` overrides.
func relaunchThroughLaunchServicesIfNeeded() {
    guard ProcessInfo.processInfo.environment["VICTOR_EFFECTS_ALLOW_DIRECT"] == nil else { return }
    // launchd is pid 1 and is the parent of everything LaunchServices starts. A
    // shell that ran the binary is still sitting there as the parent instead.
    guard getppid() != 1 else { return }
    let bundleURL = Bundle.main.bundleURL
    guard bundleURL.pathExtension == "app" else { return }

    effectsInfo("⚠️ Started by path from a shell — macOS would file this as a SECOND privacy "
        + "client keyed by the path (the duplicate row with the generic exec icon in System "
        + "Settings). Relaunching through `open`. Set VICTOR_EFFECTS_ALLOW_DIRECT=1 to stay here.")

    let relaunch = Process()
    relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    // `-n` keeps the meaning of the gesture: someone asked for an instance to
    // start, and the pid-file takeover stands any older one down exactly as it
    // did when the binary was run directly.
    relaunch.arguments = ["-n", "-a", bundleURL.path, "--args"] + CommandLine.arguments.dropFirst()
    do {
        try relaunch.run()
    } catch {
        // Better a duplicate privacy row than an app that refuses to start.
        effectsError("Could not relaunch through `open` (\(error)) — carrying on here.")
        return
    }
    exit(0)
}
relaunchThroughLaunchServicesIfNeeded()

// --- PID lock file: ensure only one instance runs at a time ---
let pidFilePath = "/tmp/VictorEffects.pid"
let myPid = getpid()

// Verify that a PID actually belongs to a Victor Effects process before killing
// it. PIDs can be recycled after a hard crash that left the lock file stale, so
// blindly sending SIGTERM to whatever holds the old PID can murder an unrelated
// process.
func pidIsVictorEffects(_ pid: Int32) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-p", "\(pid)", "-o", "comm="]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return false
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let comm = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return comm.contains("Victor Effects")
}

// Kill any previous instance before we start
if let oldPidStr = try? String(contentsOfFile: pidFilePath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
   let oldPid = Int32(oldPidStr),
   oldPid != myPid {
    if pidIsVictorEffects(oldPid) {
        effectsInfo("Stopping previous instance (pid \(oldPid))...")
        kill(oldPid, SIGTERM)
        for _ in 0..<10 {
            usleep(100_000) // 100ms
            if kill(oldPid, 0) != 0 { break }
        }
        if kill(oldPid, 0) == 0 {
            effectsInfo("Previous instance stuck — force killing")
            kill(oldPid, SIGKILL)
        }
    } else {
        effectsInfo("Stale PID file (\(oldPid)) — not a Victor Effects process, ignoring")
    }
}

// Write our PID (supersedes any previous instance)
try? "\(myPid)".write(toFile: pidFilePath, atomically: true, encoding: .utf8)

// Clean up lock file on exit (only if we still own it)
func cleanupLockFile() {
    if let pidStr = try? String(contentsOfFile: pidFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       let pid = Int32(pidStr),
       pid == myPid {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }
}
atexit { cleanupLockFile() }

// --- Normal startup ---
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no dock icon

// Remember our parent PID (start.sh) — if it dies, we should too
let originalParentPID = getppid()

// No outbound WebSocket here: this app only ever *answers* on its HTTP port and
// fires one optional webhook. Extra argv (start.sh from an older checkout) is
// deliberately ignored rather than rejected.
effectsInfo("Starting Victor Effects (parent pid: \(originalParentPID), my pid: \(myPid))")

let delegate = AppDelegate(pidFilePath: pidFilePath, myPID: myPid)
app.delegate = delegate

// Handle SIGTERM via GCD so a real teardown runs before exiting. Plain signal()
// handlers are restricted to async-signal-safe calls;
// DispatchSource.makeSignalSource runs the handler off the signal stack.
signal(SIGTERM, SIG_IGN) // let GCD handle delivery
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    effectsInfo("SIGTERM received — tearing down")
    delegate.tearDownForReplacement()
    cleanupLockFile()
    exit(0)
}
sigtermSource.resume()

// Periodic self-check: exit if another instance took over OR parent process died
Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
    // Check 1: PID file replaced by newer instance
    if let pidStr = try? String(contentsOfFile: pidFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
       let filePid = Int32(pidStr),
       filePid != myPid {
        effectsInfo("Replaced by newer instance — tearing down")
        delegate.tearDownForReplacement()
        cleanupLockFile()
        exit(0)
    }

    // Check 2: Parent process (start.sh) died — ppid changes to 1 (launchd)
    let currentParent = getppid()
    if currentParent != originalParentPID {
        effectsInfo("Parent process died (\(originalParentPID) → \(currentParent)) — tearing down")
        delegate.tearDownForReplacement()
        cleanupLockFile()
        exit(0)
    }
}

app.run()
