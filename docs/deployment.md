# Deployment & App Lifecycle

```bash
./build-app.sh                                  # → /Applications/Victor Effects.app
pkill -f "Victor Effects"; open "/Applications/Victor Effects.app"
./install-startup.sh                            # optional: start at login
```

## `build-app.sh`

`swift build -c release`, then a bundle assembled by hand. Four details are
load-bearing:

- **The `BUILD_TIME` stamp.** A `sed` rewrites `MenuBar.BUILD_TIME` in place
  before the build, so the disabled `Version: …` row above Quit always says which binary is
  actually running. When that row disagrees with what you just changed, you are
  looking at an old process.
- **No sounds step.** Unlike the app this was extracted from, nothing
  dereferences a sounds folder into the bundle: the mp3s are read live from
  `EffectsConfig.soundsDir`, so a changed sound needs no rebuild and no symlink
  ever reaches `.build`.
- **The icon** is generated from `Sources/VictorEffects/Resources/icon_explosion.png`
  (itself produced by `tools/make-icon.swift`) through `sips` + `iconutil`.
- **`Bundle.module` is deliberately *not* copied into the `.app`.** The
  generated resource accessor resolves it from an **absolute** `.build/…`
  path. Anything placed at the `.app` root, outside `Contents/`, counts as
  unsealed content and makes `codesign` fall back to an ad-hoc signature — which
  breaks TCC persistence. The trade is explicit: **always deploy from this same
  checkout, and never `swift package clean`**, or the app loses its resources.

## Code signing — why it matters here

macOS ties Accessibility and Screen Recording grants to a **bundle id plus a
signing identity**. An ad-hoc signature changes on every build, so every rebuild
would re-prompt for both — and until they are re-granted, ⌃W, the right-⌘ panel
and every screen-capturing effect are silently dead.

`build-app.sh` therefore looks for a stable identity in `login.keychain-db`, in
order: `$CODESIGN_IDENTITY`, then `Victor Effects Local Code Signing`, then
**`Victor Addons Local Code Signing`** — reusing the sibling app's self-signed
cert is deliberate, since a second one buys nothing. With none of them present
it signs ad-hoc and says so.

The lookup uses `grep`, not `rg`: this runs under `bash`, where `rg` may be a
zsh-only shim, and a silently failing lookup falls straight through to the
ad-hoc branch — which is exactly the thing that revokes the grants.

## Permissions (TCC)

| permission | why | without it |
|---|---|---|
| **Accessibility** | the one `CGEventTap` (`EffectsHotkeyTap`): ⌃W is swallowed, right ⌘ is watched | the tap is not installed; the menu shows `⚠️ Grant Accessibility for ⌃W / right-⌘` and `AppDelegate` retries every 30 s |
| **Screen Recording** | `CGDisplayCreateImage` for the effects that distort what is on screen (heartbeat lens, broken glass, FBI knock, beethoven, chainsaw) | those effects draw over wallpaper instead of the desktop — a silent wrong answer, not an error |

Nothing else: no microphone, no location, no Bluetooth permission, no full disk
access.

**Both are prompted for once at launch**, and the prompting call is the point:
`AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` is what
*registers* the app as a privacy client. An app that has only ever called
`AXIsProcessTrusted()` does not appear in the Accessibility list at all, so
opening the pane shows a list without it in it and the only way in is `+` and a
trip through /Applications. The dialog is a side effect of registering, not the
reason for the call — which is why it happens once per launch and never in the
30 s retry. That retry still asks quietly, so a grant that arrives a minute
later installs the tap with no restart.

Every launch logs both answers, `CGPreflightScreenCaptureAccess()` included:
Screen Recording's failure mode is a picture of the wallpaper, not an error, and
a line in the log is the only thing that distinguishes the two.

### macOS asks **once** — and that is the whole bug

A denial is permanent and silent. After a "Don't Allow", or a dialog dismissed
in the pile that appears at login, the row sits in TCC at `auth_value = 0` and
**every later `CGRequestScreenCaptureAccess()` and prompting
`AXIsProcessTrustedWithOptions` is a no-op**: no dialog, no error, nothing in
the pane moving, the app looping "⚠️ Accessibility not granted" forever. This is
what happened on 2026-09-11 — both rows denied at 11:38, one second apart, by
one pass through two dialogs:

```
kTCCServiceScreenCapture  | ro.victorrentea.victor-effects | 0 | 0 | 2026-09-11 11:38:53
kTCCServiceAccessibility  | ro.victorrentea.victor-effects | 0 | 0 | 2026-09-11 11:38:54
                                             client_type ─┘   └─ auth_value: 0 = DENIED, 2 = allowed
```

Read it with (no `sudo`, but the terminal needs Full Disk Access):

```bash
# Accessibility + Screen Recording — SYSTEM db
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "select service,client,client_type,auth_value,datetime(last_modified,'unixepoch') \
   from access where client like '%victor-effects%'"
# Automation, microphone, folders — USER db
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "select ... "
```

`client_type` is the other half of the diagnostic: **`0` is a bundle id, `1` is
a path**. A path row is the duplicate this app's launch rule exists to prevent.

Two ways out of a denial, and only two:

1. Tick the row by hand in System Settings (it *is* there — denied, not missing).
2. Clear it, so the app can ask again:

```bash
tccutil reset Accessibility ro.victorrentea.victor-effects
tccutil reset ScreenCapture  ro.victorrentea.victor-effects
launchctl bootout   gui/$(id -u)/ro.victorrentea.victor-effects
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ro.victorrentea.victor-effects.plist
```

The restart is not optional: a running process keeps the answer it was given at
launch, so the prompts only come back on the next one. `tccutil` takes a bundle
identifier and therefore cannot name a path row at all — those are removable
only by selecting them in System Settings and pressing `−`.

## Two apps, side by side

Effects (🌟, `ro.victorrentea.victor-effects`, port 55124) and addons (💬,
`ro.victorrentea.macos-addons`, port 55123) are **separate processes with
separate bundle ids, separate LaunchAgents and separate TCC grants**. Nothing
orders their startup and neither waits for the other: the proxy answers
`effectsUp:false` while this app is down, and this app's webhook is
fire-and-forget.

`pkill -f "Victor Addons"` does not touch this app, and vice versa — the deploy
line names the app you actually changed.

**Never start either by its binary path** (`.../Contents/MacOS/Victor Effects`).
macOS records TCC grants per launch path: a process started that way registers
as a *second* app with the same name, a generic icon and none of the grants.
`open "/Applications/Victor Effects.app"` is the only correct way.

## LaunchAgent

`./install-startup.sh` writes `ro.victorrentea.victor-effects.plist` into
`~/Library/LaunchAgents` and loads it. The plist in the repo carries a
`__START_SH__` placeholder rather than anybody's home directory; the installer
substitutes this checkout's `start.sh` on the way through.

### `start.sh` runs `open`, not the binary

**The one rule this file exists for.** macOS keys a privacy grant to a bundle
identifier only for a process **LaunchServices** launched. A process that starts
its own Mach-O — `exec "$APP/Contents/MacOS/Victor Effects"`, which is what
`start.sh` used to do — is filed by **path** instead: a second, unrelated
privacy client with the same name and the generic `exec` icon macOS gives an
unbundled binary. The two rows are indistinguishable in the pane, so the box
someone ticks may grant one this app never uses, and the feature stays dead with
a checkbox next to its name switched on.

So `start.sh` ends in:

```bash
exec /usr/bin/open --env "VICTOR_EFFECTS_ROOT=$DIR" -a "/Applications/Victor Effects.app"
```

- **`--env`** because LaunchServices does *not* forward the caller's
  environment; a plain `export` before `open` is silently lost.
- **No `-W`.** `open` hands the app to launchd and exits, so `pgrep -f "Victor
  Effects"` finds exactly one process and `pkill -f "Victor Effects"` still means
  the app rather than a waiting `open`. The LaunchAgent job simply completes
  while the app goes on running under launchd — which is what a LaunchServices
  app looks like. `ps` shows its parent as pid 1 either way; the difference the
  grant turns on is *who* started it, not what the parent is.
- **The log still lands in `/tmp/victor-effects.log`**, because
  `redirectLogsIfNeeded()` in `main.swift` redirects itself whenever stderr is
  not already a regular file — which is the case for every LaunchServices
  launch, this one and Spotlight's alike.

`main.swift`'s `relaunchThroughLaunchServicesIfNeeded()` is the backstop for the
remaining way in: running the bundle binary from a shell to watch stdout. It
re-execs through `open -n` and exits, before the pid-file takeover, so a stray
direct launch never stands the healthy instance down on its way out.
`VICTOR_EFFECTS_ALLOW_DIRECT=1` overrides it, and a `swift build` binary is
ignored — it lives outside a `.app` and has no bundle identity to mistake.

There is no `adb reverse` here and no outbound WebSocket: clients still reach the
addons app on 55123, which forwards.

## Single instance, reopen-replaces-it

`/tmp/VictorEffects.pid` holds the running instance; a new launch takes the file
over and SIGTERMs the old one, verifying the process name first so a stale pid
from a hard crash cannot kill an unrelated process.

`AppDelegate.applicationShouldHandleReopen` → `AppRelaunch.relaunch`: for a
menu-bar app with no windows, "I opened it again" only ever means "give me a
fresh one". LaunchServices treats `open` of a running bundle as an *activation*,
not a launch, so without this, clicking the app while it is wedged does
precisely nothing. The relaunch is performed by a detached `/bin/sh` helper that
waits for this pid to disappear and then runs `open -n`, so it behaves the same
whether the app exits cleanly, is SIGKILLed, or crashes on the way out.

`tearDownForReplacement()` is idempotent and stops the coffee monitor, releases
the listener port before the replacement tries to bind it, and stops every
effect.
