# Installing and releasing

## For users: `install.sh`

`curl -fsSL https://raw.githubusercontent.com/victorrentea/victor-effects/master/install.sh | bash`
downloads the latest GitHub release (`Victor-Effects.zip`, a universal ad-hoc
signed app), installs it to `/Applications` (`~/Applications` if not writable),
registers a LaunchAgent that runs `open -a` at login, waits for `/ping`, fires
confetti, and reads `/state.permissions` to tell the user which of the two TCC
switches is still off (opening that pane). `--from-source`, `--no-login-item`,
`--uninstall`, `--version <tag>`; `VICTOR_EFFECTS_ZIP_URL` points it at a zip
that is not released yet (the VM tests use it).

Nothing here needs Xcode, a config file or a sounds folder: `soundsDir` falls
back to the bundled `starter-pack/`.

## For the maintainer: `tools/release.sh [tag]`

Universal build (`UNIVERSAL=1`), ad-hoc signature (`CODESIGN_IDENTITY=-`; a
self-signed identity means nothing on another Mac), into `dist/`, zipped, then
`gh release create`. It refuses uncommitted changes in `Sources/` or
`starter-pack/`, and runs `check-starter-pack.py` and `copyright-guard.py`
first. Not notarized: `curl` sets no quarantine flag, so Gatekeeper never asks.

## What the clean-VM runs taught (2026-10-14)

Tested on a fresh Tart clone of `ghcr.io/cirruslabs/macos-sequoia-base`
(external disk, `TART_HOME=/Volumes/Vic/tart`, VM `fx-lab`), by running the
installer and by letting an agent (Claude Code, `--restricted`, shell only via
SSH into the VM) install both apps from a one-sentence request.

- **`Bundle.module` crashed any copied app** — it knows only an absolute
  `.build/` path. Resources now ship in `Contents/Resources` (`EffectsResources`).
- **The first sound after a boot froze the app for minutes.** The first
  `AVAudioPlayer` of a session makes a synchronous XPC call to the audio
  component registrar (2 min 48 s, then 11 min, on the VM), on the main
  thread — where every HTTP answer waits. Fix: `SoundManager.warmUpAudioStack()`
  at launch, off the main thread, and every player goes through
  `SoundManager.player(…)`, which refuses until that warm-up is done
  (`AudioGateTests`).
- **Login item + `open` = a restart.** The LaunchAgent's `RunAtLoad` launches
  the app; a second `open` during that launch counts as a reopen, which this
  app answers by relaunching. The installer waits for the login item first.
- **An unanswered `/state` is not "granted".** The installer counts a grant only
  when `/state` says `true`.
- First launch on a just-booted Mac can take most of a minute; the installer
  waits 60 s and warns rather than failing.
