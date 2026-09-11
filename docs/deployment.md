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
  before the build, so the `Quit – built …` row always says which binary is
  actually running. When that row disagrees with what you just changed, you are
  looking at an old process.
- **No sounds step.** Unlike the app this was extracted from, nothing
  dereferences a sounds folder into the bundle: the mp3s are read live from
  `EffectsConfig.soundsDir`, so a changed sound needs no rebuild and no symlink
  ever reaches `.build`.
- **The icon** is generated from `Sources/VictorEffects/Resources/icon_fireworks.png`
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

Accessibility is **checked and never prompted at launch** (`AXIsProcessTrusted()`):
a modal at login is one nobody can usefully answer. Screen Recording *does*
prompt, because its failure mode is invisible. The menu's ⚠️ row uses the
**prompting** check (`AXIsProcessTrustedWithOptions`) on purpose — an app that
has only ever asked quietly does not appear in the Accessibility list at all, so
opening the pane would show a list without it in it.

## Two apps, side by side

Effects (🎆, `ro.victorrentea.victor-effects`, port 55124) and addons (💬,
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

`start.sh` exports `VICTOR_EFFECTS_ROOT` and `exec`s the **installed bundle
binary**, appending to `/tmp/victor-effects.log` — so a LaunchAgent boot and an
`open` from Spotlight log to the same file. There is no `adb reverse` here and no
outbound WebSocket: clients still reach the addons app on 55123, which forwards.

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
