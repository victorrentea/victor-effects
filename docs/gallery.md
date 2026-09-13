# The gallery — filming every effect

A catalogue you can read is not the same as a catalogue you can *see*.
`docs/overlay-effects.md` explains what each overlay does and why its constants
are what they are; this one is about the video that shows it: every
`/effect/<name>` fired over a real editor window, labelled with the route that
fires it, cut together into one film.

**Watch it:** [effects-gallery.mp4](https://github.com/victorrentea/victor-effects/releases/latest/download/effects-gallery.mp4)

**Make it:**

```bash
tools/record-gallery.sh --dry-run     # the plan, nothing touched
tools/record-gallery.sh --publish     # ~7 minutes, the screen is taken, then uploaded
```

The agent-facing version of this page — when to run it, what to say first, what
to do about failures — is `.claude/skills/effects-gallery/SKILL.md`.

## The two halves

| file | job |
|---|---|
| `tools/record-gallery.sh` | the run: enumerate, fire, time, cut, assemble, publish |
| `tools/gallery-recorder.swift` | one ScreenCaptureKit capture, or one label PNG |
| `tools/gallery-assets/Backdrop.java` | the prop behind the effects |

The recorder is compiled on demand into `.build/gallery/` and is deliberately
**not** a target in `Package.swift`: filming the gallery must never be able to
rebuild — or break — the app.

## The numbers, and why they are those numbers

| constant | value | why |
|---|---|---|
| `SETTLE` | 1.0 s | the previous effect's `stop-all` has to finish *drawing* before the next capture starts, or the last frame of snow opens the confetti clip |
| `WARMUP` | 0.8 s | `SCStream.startCapture` returns before the first frame arrives; fire the effect earlier and its opening is missing |
| `MIN_CLIP` | 3.0 s | counter-strike is ~1.4 s. A clip that short reads as a glitch in a montage |
| `MAX_CLIP` | 16 s | longer than anything in the catalogue that self-terminates, so it only ever catches an effect that is stuck |
| `WIDTH` | 1440 px | the retina panel is 3456 px wide; four times the pixels of a clip anybody watches |

## Three things that are not obvious

**The effect list is parsed out of `EffectsEngine.swift`.** Not out of
`EffectsCatalog` — that answers a different question (which *sounds* also animate
the desktop) — and not out of a list in the script. `fireEffect`'s switch is the
only place that knows every name, and it is the same source
`SoundEffectMapDriftTests` parses. The parser carries that test's guard too:
fewer than 30 names and the run aborts rather than quietly film nothing. A new
effect shows up in the next gallery with no edit anywhere. The three that take
arguments — `alarm`, `emoji`, `progress-bar` — have `Route` cases of their own
and never reach that switch, so the script names them by hand, next to the
parser that cannot see them.

**Lengths come from `/state`, not from a sleep.** The lifecycle rule says every
`show*` schedules its own teardown; `activeEffects` in `GET /state` is that
teardown made visible. The script fires, polls, and stops the recorder when the
effect stops. The exceptions are the effects that outlive their clip on purpose
(the red button waits for a click, the whip and the siren are toggles, the ☕
waits for a cursor that never comes) — those get a fixed hold and an explicit
stop, because `/state` would report them until the heat death of the laptop.

**macOS has quietly removed both obvious ways to record a screen from a script.**
`ffmpeg -f avfoundation -list_devices` lists no screen device any more, and
`screencapture -v` fails with `capture error The operation could not be
completed` unless a human's Terminal is its parent — and refuses `-l<windowid>`
and `-R<rect>` for video regardless. ScreenCaptureKit is what is left, which is
why there is a Swift file here at all. Its labels are drawn with CoreText for a
second removal: the homebrew ffmpeg is built without libfreetype, so `drawtext`
does not exist.

## Two modes

`--mode display` films the whole built-in screen — everything the app draws,
over a real editor window, cursor included.

`--mode window` films **only the `OverlayPanel`**, alpha and all, composited over
a still backdrop inside the recorder, so none of Victor's own windows are in the
frames. It costs twelve effects, which the script skips by name and reason:

- **their own window, not the panel** — whip, red-button, claude-peek,
  green-flash (`WhipOverlay`, `RedButton`, `PeekMascot`, `EdgeFlash`);
- **they copy the real screen into themselves** — broken-glass, earthquake,
  chainsaw, heartbeat, fbi-knock, dark-door, beethoven, phone-ring, all through
  `captureBuiltInDisplay*`. Filming the panel alone would smuggle the real
  desktop in *through the effect*, which is what the mode exists to prevent.

Window mode changes what is recorded, not what is on screen: the effects still
fire on the real display, so the 🔒 locks are raised either way.

## Why it is not in CI, and where it could be automatic

A GitHub-hosted macOS runner has an emulated display, no pre-granted Screen
Recording (forcing it means writing to `TCC.db`, which only works because SIP is
off on those images), and a documented history of captures coming back as
wallpaper only, missing every application window. A Linux container cannot run
an AppKit app at all.

What *can* be unattended is this Mac. The script waits on `/state` rather than on
a person, discovers its own window id, holds the display awake and ends by
uploading to a release — so a LaunchAgent at 03:00 with `--publish` is a gallery
that regenerates itself. The one hard requirement is a **logged-in, unlocked**
session: at the login window there is no session to render into and every frame
is black.

## Publishing

The montage goes to the **`gallery` GitHub release**, not into the repo. This
checkout's whole source tree is under a megabyte and a film of fifty effects is
tens of megabytes that git would keep forever; a release asset is replaceable in
place and gives everyone one stable link. That link
(`releases/latest/download/effects-gallery.mp4`) never changes, which is why the
README and this page can point at it once and never be edited again.
