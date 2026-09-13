---
name: effects-gallery
description: Record every overlay effect over a realistic backdrop and assemble one gallery video, then publish it to a GitHub release. Trigger on "gallery", "record the effects", "video of the effects", "film the overlays", "regenerate the gallery", or a new effect that should appear in it.
---

# The effects gallery

One video that shows what every `/effect/<name>` actually looks like, each clip
labelled with the route that fires it, recorded over a real editor window rather
than over an empty desktop.

The work is in **`tools/record-gallery.sh`** (orchestration) and
**`tools/gallery-recorder.swift`** (capture). This file is for the judgement
calls around them — most of all the one at the top.

## The thing to say out loud first

**This takes the screen for the length of the run** — roughly 6–9 minutes for the
full catalogue. Every effect draws over whatever Victor is doing, and the
recording is of his actual display. So:

- Never start a real recording without asking. `--dry-run` is free and answers
  most questions ("did my new effect land in the list?") without touching
  anything.
- The script re-execs itself under `hands-off run` and `caffeinate -disu`, so the
  🔒 locks are on screen for the whole run and the display cannot sleep
  mid-capture. Do not "simplify" that away: a display that sleeps does not give
  black frames, it gives *no* frames, and the run ends with 50 empty clips and
  no error.
- Tell him the mouse is unusable for the duration. Several effects are anchored
  to the cursor (chainsaw, fire, whip, red button) and a hand on the mouse mid-run
  shows up in the film.
- **The Mac must be unlocked, not merely awake.** This is the failure that looks
  like success: macOS draws the lock screen over everything, ScreenCaptureKit
  records *that*, and the effects fire underneath where no camera can see them.
  The first real run produced twenty flawless clips of a wallpaper and a clock —
  and they even passed a "do the frames differ?" check, because the clock and the
  cursor move. caffeinate does not help; it stops the display sleeping, not the
  session locking. The script now refuses to start while locked and re-checks
  before every effect, so a session that locks mid-run stops the run instead of
  filling the rest of the gallery with wallpaper.

## Two things to clear off the screen first

Both were in every frame of the first good run, and neither is something the
script can fix for you:

- **The ScreenCaptureKit consent prompt.** Sequoia re-asks periodically —
  *"Terminal is requesting to bypass the system private window picker"* — and it
  opens a panel dead centre over the backdrop. It does not block the capture, so
  the run succeeds with a dialog in the middle of all fifty clips. Fire one
  throwaway `--only confetti` first, click **Allow**, then do the real run.
- **Notification banners.** Two *Background Items Added* banners sat in the top
  right corner of the whole fireworks clip. Turn on a Focus mode before a full
  gallery run.

## Running it

```bash
tools/record-gallery.sh --dry-run              # the whole plan, nothing touched
tools/record-gallery.sh                        # the real thing, ~7 min, screen taken
tools/record-gallery.sh --only snow,confetti   # one or two, for a retry
tools/record-gallery.sh --publish              # + upload to the 'gallery' release
```

The app must be running and answering on 55124 (`curl 127.0.0.1:55124/ping`) —
the script checks and refuses otherwise, because the alternative is a
seven-minute recording of a desktop where nothing happens.

Dependencies: **ffmpeg** (`brew install ffmpeg`), **swiftc** (Xcode command line
tools — the recorder is compiled on first run into `.build/gallery/`), **gh**
for `--publish`, and `~/bin/hands-off` from `victor-macos-addons` for the locks.

## Why the script is shaped the way it is

**The effect list is parsed, never written down.** `tools/record-gallery.sh`
reads the `case "…"` labels out of `fireEffect`'s switch in
`EffectsEngine.swift` — the same source `SoundEffectMapDriftTests` parses, and
for the same reason: this repo has already paid once for keeping a second copy
of that list (the ⭐ catalogue note in `CLAUDE.md`). A new effect therefore
appears in the next gallery with no edit here. The parser carries the drift
test's own guard — under 30 names and it dies rather than quietly filming
nothing.

Three effects are named by hand anyway, and the script says so where it does it:
`alarm`, `emoji` and `progress-bar` take arguments, so they have `Route` cases of
their own in `EffectsRouter` and never reach that switch.

**Durations are read from the app, not guessed.** Every `show*` schedules its own
teardown (the lifecycle rule in `docs/overlay-effects.md`) and `GET /state`
reports the effect in `activeEffects` until it does. So the script fires, polls
`/state`, and stops the recorder when the effect stops — with a floor of 3 s (a
1.4 s effect is otherwise unwatchable) and a cap of 16 s (nothing in the
catalogue legitimately runs longer, and an effect that never clears must not
stall the run). The handful that outlive their clip on purpose — the red button,
the whip, the siren, the elephant, the ☕ — are held for a fixed few seconds and
then explicitly stopped, because `/state` would report them forever.

**Capture is ScreenCaptureKit, and that was not a preference.** On this machine
`ffmpeg -f avfoundation -list_devices` lists cameras and microphones and **no
screen device** — AVFoundation's screen input is gone. And `screencapture -v`
answers `capture error The operation could not be completed` when it is started
from a script rather than from a Terminal a human is sitting in; it also refuses
`-l<windowid>` and `-R<rect>` for video, both being image-only flags. Stills
still work, which is why the window-mode backdrop is taken with `screencapture
-x -o`. Everything moving goes through `tools/gallery-recorder.swift`.

**Labels are rendered by that same binary, not by ffmpeg.** The homebrew ffmpeg
here is built without libfreetype, so `drawtext` does not exist — `-vf
drawtext=…` dies with *No such filter*. Rather than make the gallery depend on a
rebuilt ffmpeg, `gallery-recorder --label` draws the name and the route into a
transparent PNG with CoreText and plain `overlay` composites it.

## The two modes, and when the second one is worth it

`--mode display` (the default) records the whole built-in screen. Everything the
app can draw is in the frame, the backdrop is a real editor window, and the
cursor is visible.

`--mode window` records **only the app's own `OverlayPanel`**, with its alpha,
and composites it over a still backdrop inside the recorder. Victor's actual
windows never enter the frames. It is the polite mode, and it is honestly
limited:

- Five effects draw in **their own windows** (whip, red button, claude-peek,
  green-flash, the thumbnail panel) and are simply not in that window's pixels.
- Seven effects **copy the real screen into themselves** to distort it —
  broken-glass/earthquake, chainsaw, heartbeat, fbi-knock, dark-door, beethoven,
  phone-ring, all via `captureBuiltInDisplay*`. In window mode they would smuggle
  the real desktop *inside* the overlay, which is the one thing the mode exists
  to prevent.

The script skips both groups in window mode and prints why. Note that window
mode still *fires* the effects on the real screen — it changes what is
recorded, not what is visible — so the locks stay on either way.

## Can this be automatic?

Short answer: **on this Mac at night, yes. In CI, no.**

- **GitHub Actions hosted macOS runners** — do not build on this. The runner has
  an emulated display and Screen Recording can only be forced by writing to
  `TCC.db` (possible only because SIP is off on the macOS 13+ images), and even
  then the reports are of captures that come back as wallpaper-only, missing
  application windows, or visually corrupted (runner-images issues #8951, #9529,
  #9047; trycua/cua#3725 in 2026 hits exactly the "screen capture only shows
  desktop, not application windows" failure on hosted runners). An unsigned
  locally-built app also gets a fresh TCC identity per run.
- **Docker / any Linux container** — impossible in one line: this is an AppKit
  app that needs a macOS WindowServer. There is nothing to discuss.
- **A scheduled run on Victor's own Mac** — this is the real answer. Everything
  the script needs is already unattended: it discovers the window, waits on
  `/state` rather than on a human, and ends by uploading to a release. A
  LaunchAgent at, say, 03:00 with `RunAtLoad` false and a `StartCalendarInterval`
  would do it, provided the Mac is **logged in and unlocked** — the screen may be
  asleep (caffeinate wakes it), but at the login window there is no session to
  render into and every frame is black. Add `--publish` and that is a gallery
  that regenerates itself, just not from a push.

If Victor wants the push to be the trigger, the honest shape is a workflow that
does nothing but leave a marker, and a launchd job on this Mac that notices it.
Do not promise a hosted runner.

## After a run

The script prints which effects failed (recorder exited non-zero, or no frames).
Re-run just those with `--only`; a single failure is usually the effect having
ended before the recorder's first frame, and a second attempt fixes it.

Publishing is `--publish`, and it is deliberately a **GitHub release asset, not a
committed file**: this repo is public, its entire source tree is under a
megabyte, and a montage of fifty effects is tens of megabytes of binary git
would carry forever. The release gives everyone the same stable link —
`releases/latest/download/effects-gallery.mp4` — and replaces in place on the
next run. `docs/gallery.md` and the README link to that permalink, so neither
needs editing again.
