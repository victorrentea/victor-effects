# Desktop Effects — the catalogue

Every overlay this app can draw, why it looks the way it does, and the numbers
behind it. Read the zone before touching an effect: most of the constants here
were arrived at by being wrong in front of a room first.

## How an effect is addressed

An effect has **one name** and three ways in, all of which end at the same
switch (`EffectsEngine.fireEffect`):

- `GET /effect/<name>` on port 55124 — the canonical form. Nested names work
  (`/effect/pulse/stop`, `/effect/chainsaw/stop`). An unknown name answers
  **200** and logs `unknown effect '<name>'`: a client firing a name this build
  does not have yet is not an error worth failing a soundboard press over.
- `GET /test/<name>` — historical aliases for about twenty of them, kept so
  every script and muscle-memory `curl` survived the extraction. See
  `docs/testing.md`.
- **A paired sound.** A client reports `GET /sound/pressed/<file>` and
  `GET /sound/stopped/<file>` by bare filename, and *the Mac* decides which
  visual goes with it (`SoundEffectMap`). Changing a pairing is a Mac-side
  edit; no client is redeployed.

**There is no longer a fourth door through the menu.** The ⭐ menu used to carry
a 39-row ⭐️ Effects submenu, fired through an `EffectsEngine.menuEffect` of its
own — silent and fixed-length, because no routed sound's duration was there to
end a looping effect. It went on 2026-09-12 along with `menuEffect` itself: the
thumbnail panel shows the same effects as *pictures*, on a board the room
already knows from the tablet, and a menu of words for a board of pictures was
only a second list to keep in step. `🛑 Stop all` is what stayed — and on
2026-09-13 it stopped being a row too.

### 🛑 The status item IS stop-all

The menu-bar icon has two faces, and it is the one surface that answers
`/effect/stop-all` without opening anything:

| | nothing running (⭐) | something running (🛑) |
|---|---|---|
| left click | opens the menu | **stops everything, in one call** |
| right click, or ⌃-click | opens the menu | opens the menu |

"Everything" is `EffectsEngine.stopAll()`, so however many effects are layered
they all go at once, along with the routed sound, the progress bar and an armed
whip.

Right-click is the rule that does not depend on the screen: Quit and the two
panel rows stay one gesture away whatever is playing, which is why the 🛑 state
is allowed to take the left click at all.

**Which row of that table applies is decided by a LIVE read of
`isAnythingRunning`, at click time — not by the icon that happens to be drawn.**
The two disagree for up to one poll interval, and that window is the whole
point: an effect starts, the bar still says ⭐ for a third of a second, and a
hand that is already moving lands in it. Honouring the drawn icon there would
answer the click by opening a menu over a demo that has just gone wrong in front
of a room. This is an emergency stop: it is allowed to look momentarily
inconsistent with its own lamp, it is not allowed to miss. (The reverse
mismatch costs nothing — a stale 🛑 over a quiet screen fires a `stopAll()` that
stops nothing.) The icon is still drawn promptly, because the room learns the
shortcuts by heart and this is the one surface a demo can always be aborted
from.

**An armed 🔥 whip counts as running**, and this is the one entry that is a
*mode* rather than an animation: while the whip is up, Return and mouse buttons
6/7 crack it and a click types the scold macro into the front app
(`EffectsHotkeyTap` gates all three on `whipIsShowing`). One click on the 🛑
disarms it through the same `stopAll()` that clears everything else —
`WhipController.hide()` takes the panel down, drops the Esc monitors and stops
the Bluetooth warm, after which the tap stops gating. The whip has no deadline
of its own, so the price is that the status item shows 🛑 for as long as the
whip is out: `docs/whip.md`.

The two mechanics worth knowing before editing `MenuBar`:

- **The menu is detached** (`statusItem.menu` stays nil). An attached `NSMenu`
  opens on mouse-*down* and swallows the button's action entirely, so no click
  could ever mean "stop". It is re-attached for the length of one
  `performClick(nil)` and detached again the moment that returns. The button
  also needs `sendAction(on: [.leftMouseUp, .rightMouseUp])` — the default mask
  is left-up alone, so a right-click would otherwise do nothing at all.
- **The icon polls**, every 0.3 s, and this follows from the lifecycle rule
  below rather than from laziness: effects self-terminate, so usually *nothing*
  calls `stopAll()` and there is no event to listen for. An icon that waited to
  be told would sit on 🛑 forever after any effect that simply ran out. The
  question it asks is `EffectsEngine.isAnythingRunning`, which is deliberately
  the same four things `stopAll()` clears — routed sound, `activeEffects`, the
  progress bar, the whip — and the same state `GET /state` publishes. The icon
  promises a click will clear the screen, so watching a wider set than stop-all
  can clear would make it lie. (The overlays kept outside `activeEffects` on
  purpose — the 🕳️ iris, the 🪚 chainsaw cursor, the spiral hearts — therefore do
  not raise it, and neither do untracked spawns like rising emoji or confetti,
  which are gone before a hand reaches the menu bar.)

Everything is drawn as `CALayer`s on `OverlayPanel`'s `hostLayer` — one
click-through, all-spaces panel covering `Screens.overlayScreen()` (the
built-in display by default, see `EffectsConfig.overlayScreen`). Bitmaps and
gif frames come from `Bundle.module`; the seven large/licensed ones come from
`EffectsConfig.assetsDir` via `assetURL(_:)` and the effect quietly does
nothing when they are absent. Audio comes from `EffectsConfig.soundsDir`
(`docs/sound-routing.md`) — **no soundboard mp3 is in this repo**.

### 🔍 When the screen is zoomed, the edges move

macOS screen zoom (⌥-scroll, Accessibility › Zoom) magnifies the
**framebuffer**, overlay panel included. So an effect that hugs "the edges of
the screen" hugs the edges of the *unzoomed* display: at 2× the alarm's red
border is a full screen away from the glass in every direction and the room
sees no alarm at all — which is exactly how this was found, mid-workshop,
zoomed in on a method.

`ScreenZoom` asks the window server which slice is blown up and hands back the
part of a rect that is really on the glass:

```swift
let live = ScreenZoom.visibleRect(in: hostLayer.bounds, of: Screens.overlayScreen())
```

Whatever coordinates go in come back out — the viewport is worked out as a
**fraction of the display** and only then mapped onto the rect it was given —
so one helper serves a CALayer's `bounds` (the vignette) and an `NSPanel`'s
global frame (`EdgeFlash`) without either knowing about the other's axes.

Three things worth knowing before touching it:

- **The getter is private.** Nothing public answers this: `UAZoomEnabled()` only
  says *whether* zoom is on and `UAZoomChangeFocus` only *moves* it. The answer
  is `SLSGetZoomParametersForDisplay(cid, display, &centre, &factor, &smoothing)`
  in SkyLight, whose `centre` is the middle of the visible slice in global CG
  points (y down) and whose `factor` is the magnification — `1.0` and the
  display's own middle while that display is at rest, which is what makes "not
  zoomed" and "zoomed to nothing" the same reading. Every lookup is a `dlsym`
  allowed to fail: a macOS that renames the symbol costs the zoom-awareness and
  nothing else, because `visibleRect` then answers the whole rect it was handed,
  which is the behaviour that existed before the file.
- **The clamp is load-bearing, not hygiene.** macOS keeps the viewport inside
  the display, so a centre reported near an edge describes a slice that hangs
  off it. Clamping reproduces what is actually on the glass — and keeps the
  answer right even if a future macOS starts reporting an unclamped focus point
  instead of a clamped centre.
- **A three-second effect outlives the pan.** The viewport moves with the
  pointer, so `visibleRect` alone would leave the border behind the first time
  Victor pans while talking. `ZoomFollower.shared.track(layer, full:)` re-pins a
  layer at 30 Hz, with implicit animation off (an animated 33 ms correction
  reads as the border swimming). Entries are **weak** and are dropped the moment
  a layer is deallocated or leaves its superlayer, and the timer stops with the
  last one — the follower must never be what keeps an effect alive, nor what
  has to be told an effect ended (the self-termination rule).

The **borders** were first: the **🚨 alarm / danger vignette** (`showVignette` — the
radial gradient carries the frame, the container only carries the opacity
animation, so there is one frame to re-pin) and the **green `EdgeFlash`**. The
flash does *not* follow a pan: it is an acknowledgement that is over in a
second, not an effect you talk over.

Since 2026-09-23 the rest of the effects that were landing off the glass use
one of two more tools (Victor: *"efecte … doar pe zona în care e zumat
ecranul"*):

- **`ZoomSlice` — frozen once, for effects drawn once.** `ZoomSlice.current(in:)`
  snapshots the viewport; the effect lays its layer over `slice.rect` and, if
  it shows a screenshot, shows `slice.crop(capture)`. The capture is the
  *unzoomed* framebuffer, so a full-screen screenshot lined up fine before —
  but the motion did not: the knock scaled about the middle of the display, the
  crack started at a random point of it, the phone rang in its bottom-left
  corner, all off the glass. Over the slice with the matching crop, the
  magnification blows the effect back up to exactly how it looks unzoomed. The
  frame and the crop come from **one** snapshot, so a pan between two reads
  cannot hand the layer one slice and the picture another. Used by
  **❌ fail (#19)**, **🚪 dark door (#25)**, **🎼 Beethoven (#51)**, **🚔 FBI knock
  (#64)**, **☎️ phone ring (#10)** and **💥 broken glass (#90)**, and by the
  **🔍 Pink Panther magnifier (#6)** for its *size* only: the lens is two
  thirds of the slice's height, since two thirds of the display at 2× was a
  lens taller than the glass. It still rides the pointer, which is inside the
  slice anyway.
- **`ZoomFollower.stage(_:full:)` — for a long effect you talk over.** The
  container keeps its children laid out over the whole display and is itself
  scaled by `1/factor` and centred on the slice, re-pinned at 30 Hz like the
  borders. Nothing inside learns about the zoom; clouds sliding in from outside
  the display now slide in from outside the slice. Used by **⛈️ storm (#20)**,
  whose clip is long enough that Victor pans during it.

  Also used by **💓 heartbeat** (2026-09-24), for the 🐶/🐱 only: they sit on a
  staged sublayer, and the pointer they follow is mapped into the stage's
  full-display coordinates (`heartbeatStagedCursor`). The screenshot is NOT
  staged — it has to line up with the desktop — and the lens radius is sized on
  the slice instead, re-read on every follow tick so ⌥-scroll mid-beat keeps the
  bulge the same fraction of the glass as unzoomed.

Not done yet: the 🪚 chainsaw (a cut mask over the pointer's path); it works
under the pointer, which is always on the glass.




**Sound → overlay-effect mapping (Mac-owned).** The tablet no longer decides
which sound triggers which visual effect. On every sound press it fires
`GET /sound/pressed/<file>` and on every stop `GET /sound/stopped/<file>` (bare
filenames), and the Mac looks the effect up in `SoundEffectMap.swift` — the
single source of truth (`onPress: [file → effect]`, `onStop: [file →
effect/stop]`) — then dispatches through the existing `onEffect` switch (reusing
all BT visual-compensation/sync logic). **Changing a mapping or adding a new
effect needs only a Mac rebuild — no tablet redeploy.** The siren
(`02_siren.mp3`) is the one exception: it drives the alarm overlay
(`/alarm/start`,`/alarm/stop`) and stays special-cased on the tablet. Effects
are CALayers on the overlay's `hostLayer`, animated via `CAKeyframeAnimation`
on `contents` from bundled gif frames (`Bundle.module`).

**Lifecycle rule (2026-07): every overlay effect MUST self-terminate at its
sound's length — network stop messages are an optimization, never the only
teardown.** A client's `/sound/stopped` → `onStop` chain (and even the
pre-press `/effect/stop-all`) is best-effort: on a flaky venue network the
tablet falls back to a slow relay transport and those GETs get lost — and since
the 2026-09 split each of them is also one more process hop that can go missing.
That used to leave looping overlays (star-wars, brother, gangnam, drum-roll) on the desktop
forever. Every `show*` therefore schedules its own authoritative stop —
`trackEffect(duration:)` for one-shots, or an explicit
`asyncAfter(<the mp3's real duration> + 0.3s grace)` for loopers, reading the paired
mp3's length via `AVURLAsset` — **in the silent (`playSound: false`) tablet
path too**, since that's the path real presses take. Self-stop timers are
**identity-guarded** (`activeEffects[key] === layer`, the love-hands pattern)
so an old run's timer can never kill a newer run of the same effect. The one
deliberate exception is the siren's alarm overlay (an unbounded toggle — its
sound loops until explicitly stopped). When adding a new effect, follow this
rule from the start.
- **🩸 Blood drip** (sfx #40 `40_joker.mp3` → `blood-drip`): `blood-drip.gif`
  (white bg made transparent via ImageMagick `-coalesce -fuzz 20% -transparent`,
  full-canvas frames) shown as a blood band pinned to the **top of the screen**
  at full width (aspect-preserved, transparent backdrop over the live screen),
  drips/droplets falling; the ~1.6s loop plays **~1.5× slower**, repeating for
  the joker track (~9.0s) with a 0.25s fade-in and 0.6s fade-out tail. The layer
  is stretched to **1.8 × 0.7 = 1.26 screen heights** (2026-09-09): 1.8 was the
  stretch that pushed the lowest droplets off the bottom edge, and ×0.7 pulls the
  curtain back up so it reads as a band hanging from the top rather than a
  full-screen wash. The layer's anchor is its **top edge** (`anchorPoint.y = 1`),
  so the shrink comes off the bottom and the band stays glued to the top of the
  screen — the same anchor the 1.5 s vertical-scale reveal grows down from.
- **🌍 Universal minions** (tile #14 `14_universal.mp3` → `universal-minions`,
  `showUniversalMinions`): the tile's own clip is the Universal fanfare WITHOUT
  the animated logo — the animation arrives as a **matted frame sequence**
  (`~/.victor-effects/assets/universal-minions/f_001..169.png`, BirefNet alpha
  matte of **the minions row alone** — a 784×210 strip cut from the 1080p
  intro at 23.976 fps, trimmed flush under the feet, half the side margins
  kept, and the last 4 frames blanked (the source fades to pure black and
  BirefNet mattes a black frame as ~98% opaque — a dark slab flashed at the end); the old 720p 16:9 set is kept beside it as
  `universal-minions-720p/`) the Mac plays itself, pinned **flush to the
  bottom-left corner at ~67% of the screen's width** (the old 50% × 1.2 × 1.2 for the minions, × 784/840 for the trim) for the sequence's ~7.05 s.
  The frame count — hence the length — is **read from disk**, so a re-matte
  is an asset swap, not a code change. The cue sits
  **24.0 s INTO the combined clip** (where frame 1 was taken, by audio
  cross-correlation of the 1080p clip against the combined track) (`universal-minions.mp3` in `assetsDir` —
  the tile's fanfare followed by the clip's own tail, which the tablet's copy
  does not contain), so like the radar and the microwave the effect **owns the
  audio**: `playTabletSound("universal-minions.mp3")` plays the whole clip and
  stamps the visual's clock in the same call. The frames decode on a
  background queue during the 24 s lead-in and install as a discrete
  `contents` keyframe animation **exactly on the cue** (identity-guarded, so a
  re-press mid-decode discards the result; a late install catches up
  mid-sequence). The layer carries only a 0.15 s entrance fade — the matte's
  own tail frames already contain the dissolve. Bluetooth compensation shifts
  the whole timeline the microwave way. Missing frames degrade to audio-only;
  a missing clip returns 0 → 404 → the tablet falls back to its own copy.
  **Trigger:** driven from the **routed `/sound/play/14_universal.mp3`** path
  (`onSoundPlay` special-cases it → `showUniversalMinions(playSound:true)`),
  so the press plays the combined clip AND the animation with no double audio;
  `14_universal.mp3` is therefore intentionally **absent from
  `SoundEffectMap`** (the press path would otherwise double-trigger it).
  **The layer's model opacity is 0**, so the entrance fade is `.both` and
  kept on the layer — removed on completion it dropped the minions back to
  invisible after 0.15 s (they "flashed"). `/test/universal-minions/preview`
  (= `/effect/universal-minions/preview`) starts the clip **1 s before the
  cue** (`skip:` shifts audio and visual clock together) for checking the
  animation without the 24 s fanfare.
  `/test/universal-minions` and `/effect/universal-minions` both fire it
  **with sound** — like the microwave, a soundless run would just sit there
  for 24 s and then show a silent cartoon.
- **🛰️ Sonar** (sfx #23 `23_radar.mp3` → `sonar`, `showSonar`): a full-screen
  black wash fades in (0→45% over 1s; darker **70% disc** inside the radar
  circle), then a phosphor-green radar **drawn entirely as CALayers** (no gif):
  muted-grey concentric rings + radial spokes; a **conic-gradient sweep arc**
  (bright +x leading edge, fading 100%→0% behind it, masked to the circle) that
  rotates **clockwise**. The sweep carries **ultrasound-style "reception noise"**
  (flickering green/black speckle frames generated in `makeSonarNoiseFrames`,
  masked to the wedge), and a fainter copy of the same noise covers the circle
  interior (background static; outside the circle is just the dark wash). A
  **💩 blip** (3× emoji, green glow) sits at the front's detection angle, hidden
  until found. It is drawn **over the sweep**, not under it — the green front and
  its reception noise used to wash across the find at the exact instant the find
  happens, which is the one moment it must be unmistakable; the wedge passing
  *behind* it now reads as the thing that revealed it. Each detection also
  **zooms it in**: it lands at **2×** and settles to its own size over **1 s**,
  cubic-ease-out so the motion is spent in the first third (it arrives, it
  doesn't creep). The zoom is sampled on the **same keyframe grid and the same
  `detT[di]`** as the opacity flash, so it starts on the exact frame the 💩
  becomes visible; between detections the scale is parked back at 2× ready for
  the next one, and that 1×→2× reset is placed **after** the fade has fully
  finished (`coverT + fadeT`) so it always happens at zero opacity and can never
  be seen. The rotation is **keyframed** (not constant): ~0.5s beep-free
  lead-in, then the front sweeps over the 💩 on **three radar beeps** in the clip
  (clip times 0.104/2.211/3.879s; one full turn between detections). The Mac
  **owns the audio** here — `showSonar(playSound:true)` plays `23_radar.mp3`
  delayed (`soundStartRel` + 0.1s) so the beeps land on the three detections; the
  effect ends (fading out **while still rotating**) the moment the 3rd detection's
  1s fade finishes, so the front never sweeps the 💩 a 4th time unshown. Pure
  formatting/timing is derived up-front from `beepClip`/`detT`/`animEnd`.
  **Trigger:** the effect is driven from the **routed `/sound/play/23_radar.mp3`**
  path (`onSoundPlay` special-cases it → `showSonar(playSound:true)` instead of
  `playTabletSound`), so when the tablet routes its soundboard audio to the Mac,
  the radar press plays the synced SFX **and** the visual with no double audio and
  **no tablet change**. `23_radar.mp3` is therefore intentionally **absent from
  `SoundEffectMap`** (the press path would otherwise double-trigger it). `/test/sonar`
  and `/effect/sonar` call `showSonar` directly for headless testing.
- **💸 Money** (tile #53, repurposed from rain): the Android tile #53 now shows
  a plain **💸 emoji on white** but keeps its asset id `53_rain.mp3` (so the
  routing protocol/manifest are unchanged). `onSoundPlay` **special-cases
  `53_rain.mp3`** (like the radar): it fires `showMoneyRise()` and plays the
  **#57 checkmark "ching"** (`57_checkmark.mp3`) instead of the original rain,
  returning the checkmark's duration. `showMoneyRise` swarms ~16 money emojis
  (`💸💵💰🤑`) **up from the bottom edge to off the top**, swaying + tumbling
  while fading out — **one round per press ("ching")**. It is a fire-and-forget,
  **non-tracked** burst (each emoji layer self-removes), so pressing the tile
  repeatedly **stacks overlapping rounds**. `53_rain.mp3` is intentionally
  **absent from `SoundEffectMap`** so a press = a single ching + single round (no
  double-trigger). `/test/money` and `/effect/money` call `showMoneyRise` directly.
- **🔫 Counter-Strike** (sfx #73 `73_counter_strike.mp3` → `counter-strike`,
  `showCounterStrike`): the two CT operators (a transparent PNG,
  `Resources/counter-strike.png`, **pre-trimmed to its opaque content** so there is
  no transparent margin lifting them off the edge) stand in the **bottom-left
  quarter** of the retina — fitted aspect-preserved inside half-width × half-height,
  anchored at the bottom-left corner, **glued to the bottom screen edge** — snapping
  up into place over 0.18 s. It lives exactly as long as the clip (**duration read
  from the mp3** via `AVURLAsset`, ~1.36 s, falling back to that measured value) and
  fades out over its last 0.3 s. Driven from the **press path** (`SoundEffectMap`),
  so the routed `/sound/play/73_counter_strike.mp3` supplies the audio and the
  visual never double-triggers. `/test/counter-strike` and `/effect/counter-strike`
  fire it silently.
- **👅 Wazzup** (sfx #69 `69_scream_ghost.mp3` → `wazzup`, `showWazzup`,
  geometry in `WazzupCorner`): tile 69 is the Scary Movie "wazzuuup" bit, so the
  overlay is the mask that says it — the **tongue-out Ghostface**, cut out of a
  stock four-mask sheet and **mirrored horizontally** so it leans *into* the
  desktop, standing flush in the **bottom-left corner**. The box it is fitted
  into is **a fifth of the screen's area**, i.e. √0.2 ≈ 0.447 of each side
  (`boxSideFraction`) — *area*, not side: 20 % per side is a sticker nobody reads
  from the back of a room. Aspect-fit inside that box, so the portrait cut-out
  binds on **height** and the slack is spent away from the corner —
  **measured 383 × 497 pt on the 1728 × 1117 retina**, flush to both edges (the
  whole box would be 773 × 500), i.e. about a tenth of the screen actually
  inked. Deliberately a **still** — no entrance, no drift;
  the clip is the joke and anything moving down there pulls the room's eyes off
  the slide the clip just interrupted. It lives exactly as long as the track
  (**duration read from the mp3** via `AVURLAsset`, 5.56 s, falling back to that
  measured value) and fades over its last 0.35 s so it leaves *with* the sound
  instead of blinking out. Driven from the **press path** (`SoundEffectMap`), so
  the routed `/sound/play/69_scream_ghost.mp3` supplies the audio and the visual
  never double-triggers; nothing loops, so there is no `onStop` entry and
  `trackEffect` is the guaranteed exit. **The artwork is not in this repo**: like
  `brother_full.gif` and `scared_cat.gif` it is an `assetsDir` file
  (`wazzup.png`), and when it is missing the effect logs one line
  (`showWazzup: no wazzup.png in …`) and does nothing — the clip still plays.
  `/effect/wazzup` fires it silently.
- **❄️ Snow** (tile #46 `46_michael_buble.mp3` → `snow` / `snow/stop`, `showSnow`):
  **tile #46 IS the Christmas tile** — Michael Bublé's *"It's Beginning to Look a Lot
  Like Christmas"*, snow already falling in its artwork — so pressing it now snows on
  the desktop for the length of the clip (~10.5 s, read off the mp3 via `AVURLAsset`).
  The flakes are **drawn, not emoji** (`snowflakePath`: six spokes, two branch pairs
  each — the least detail that still reads as a snowflake and not an asterisk), an
  **ice-blue stroke with a deeper blue glow** (`snowflakeColor` / `snowflakeHaloColor`,
  2026-09-23). It was white-on-white-glow until then, which disappeared over a white
  slide — most of what is ever on screen. **One number — depth
  0…1 — drives size, fall speed, brightness and sway width together**, so a flake can
  never read as a contradiction (big but distant, tiny but racing); near flakes are
  **60 px**, bright and cross in ~3.5 s, far ones **15 px**, faint and take ~6.5 s —
  three times the size they started at (×2, then ×1.5 on 2026-09-23), because at 5–20 px they read as specks on a
  projected screen from the back of a room, which is the only place this is ever
  watched from, and correspondingly faster, because a flake that big drifting at the
  old speed reads as floating rather than falling. Each falls
  along a keyframed sine sway plus a net sideways drift, tumbling slowly (only
  `transform.rotation.z` is animated — the size is baked into the path, so nothing
  fights over `transform`), then **lands on the bottom edge and melts** over 1.4 s:
  the descent is the first `landed` fraction of the timeline and the repeated final
  point is the hold. **Every flake enters through the top edge** — none is ever
  dropped in mid-screen, which reads as flakes materialising out of nowhere rather
  than as snow falling. So the opening cascade is stacked *above* the screen instead:
  `snowSeedCount` = 26 flakes released at staggered heights over the top edge (at most
  **0.55** screens up, not 0.9 — a slow flake starting a whole screen higher spends
  four seconds merely arriving), at the same constant fall speed (starting higher
  means entering *later*, never falling faster), which fills the sky within ~2 s while
  each flake still makes the whole journey down. Then 16 flakes/s **for the whole
  clip** — new flakes keep entering the top edge until its last moment (Victor,
  2026-09-09: *"să tot cadă fulgi noi, să nu se oprească din cădere"*).

  That reverses a trade this code made twice before, and the history is the point.
  Emission used to stop a fixed interval before the end — a **derived** constant,
  `snowFallSecondsFar` × ⅔ = 6.5 × ⅔ ≈ **4.3 s**, exactly how long
  the slowest flake needs to reach the lower third of the screen — to keep the
  guarantee that *no flake is ever melted before it has fallen two thirds of the way
  down*, on the grounds that a flake dissolving in mid-air reads as a rendering glitch.
  (Before that it was a flat 1.5 s, which only stopped a flake entering *as* everything
  melted.) The guarantee was real, but its price was the last 4 s of a 10.5 s song: no
  flake entering at the top, the sky visibly emptying downward, **one wave of snow
  instead of snowfall** — and that is the failure the room actually sees. The stragglers
  now go out with the container fade (`snowFadeSeconds`, 1 s) wherever they happen to
  be, which reads as the effect ending rather than as a flake dissolving. Both
  constants are gone.
  **The snowfall lasts exactly as long as the song**: the melt starts on the clip's
  last moment (an identity-guarded self-stop at `sfxDuration`, which is also the
  lifecycle rule's authoritative teardown) and the desktop is clear a second later.
  The tablet's `/sound/stopped` → `snow/stop` melts it early through the same 1 s
  fade, so stopping the sound stops the snow; pending spawns are cancelled by `clearSnow`,
  which `stopAllActiveEffects` calls explicitly (they live outside `activeEffects`,
  like the spiral hearts'). `/test/snow`, `/test/snow/stop` and `/effect/snow`
  fire it silently.
- **⛈️ Storm** (tile #20 `20_storm.mp3` → `storm` / `storm/stop`, `showStorm`,
  `RainStorm.swift`): **four clouds slide in from the two sides onto the top edge, the
  desktop goes dark under them, and it rains for the length of the clip** (18.9 s, read
  off the mp3 via `AVURLAsset`) — with lightning on the thunder rolls inside it. Victor's
  ask, 2026-09-19, and it took the one square the board had left: #20 used to be the
  `N/A` row holding #19's second trombone take (`docs/sound-routing.md`).

  **The clouds are photographs** (`Resources/clouds/cloud-0…6.png`), cut out of two
  public-domain skies; that folder's `CREDITS.md` says which. They replaced a set of drawn
  ones — a seeded pile of lobes under a gradient and a blur — that nobody in a room would
  have called *wrong*, and that stopped being defensible the moment a real cumulus stood
  next to it. The drawing survives as `RainStorm.drawnCloud`, still tested, and is what a
  missing PNG gets: a worse cloud is a fair price for a missing file, no storm is not.

  **Finding the photographs was most of the work**, and the reason is the useful part. The
  matte is keyed off the **sky**, not off the cloud: a cumulus is neutral (R≈G≈B) and sky
  is not, so alpha comes from each pixel's distance from a sky colour measured in the
  crop's own four corners — which is why a crop has to be generous enough that all four
  corners *are* sky. That only works on a saturated, even blue right up to the cloud's
  edge, and almost every cloud photograph is hazy near its subject: pale blue against
  white cloud is no key at all, and the first attempt (on a picture that *looked* ideal)
  came back as an opaque rectangle. A scored sweep of ~50 public-domain candidates —
  ranking them by sky saturation, by how many pixels landed in the ambiguous middle of the
  matte, and by coverage — produced exactly **two** usable skies. Hence two cumulus forms
  across seven sprites, mirrored and horizontally stretched, arranged so no two neighbours
  share a form and a mirror never sits beside its original; at band size, half-cropped by
  the screen edge and overlapping, a stretch reads as a different cloud far better than
  another crop of the same one.

  **The base of each sprite is faded, not cut.** Trimming a cut-out to its cloud and then
  seating it on the bottom of its box gave all seven the same ruler-straight underside, on
  one line across the screen — Victor, 2026-09-19: *"norii par taiati in partea lor
  inferioara"*. A cumulus base **is** flat, but it is flat and soft: it goes to rain haze,
  it does not stop. So the last 16 % of each cloud's own vertical extent is ramped to
  transparent and the sprite is seated with a tenth of the box left empty underneath.
  `cloudWidthFraction` went from 0.28 to 0.34 in the same pass and for a related reason: a
  drawn cloud was a solid slab of alpha that butted cleanly against its neighbour, while a
  cut-out feathers to nothing at its own edges, and two of those meeting leave a notch of
  bright desktop unless they overlap much harder.

  **The band is a ceiling, not seven blobs in a row.** Each cloud is 34 % of the screen
  wide and they rest every 16 % of it, so consecutive ones overlap by half their width and
  the outermost two hang off the screen edges — a cloud that stops neatly inside the frame
  reads as a sticker, one cut by the edge reads as sky that continues past it. Every cloud
  also **overhangs the top edge** (`cloudOverhang`, 20–34 % of its own height) and sits at
  its own depth (`cloudDip`), so the band's base is ragged rather than ruled. A test walks
  the spans and fails on any gap: a hole in the ceiling is a strip of bright desktop with
  rain falling in front of it and nothing above it. A second one holds the band's depth
  between 12 % and 28 % of the screen.

  **Seven, not four** (Victor, 2026-09-19: *"be more, smaller, and a bit higher"*). The
  first cut was four clouds at 44 % each, and it was wrong twice: a ceiling a third of the
  way down the desktop ate the demo underneath it, and at that size one drawn cloud's
  seven lobes read as individual bubbles rather than as billows. More clouds also buy more
  *edges* along the band's base, which is where an overcast sky actually looks ragged. The
  band's depth is now a test — between 12 % and 28 % of the screen — because every later
  change to a cloud's width or aspect moves it, and it moved back down to 29 % the moment
  the photographs arrived with a taller sprite.

  **The entrance uses three edges, not two** (Victor, 2026-09-19: *"norii sa vina si de sus
  si din laterale"*). Seven clouds all sliding in horizontally read as a curtain being
  drawn; the ceiling has to close from the sides **and** from above. The outer four come in
  over the left and right edges, the inner three **drop straight down out of the top** —
  which is also their shorter journey, since from a side they would have had to cross most
  of the screen to reach the middle. `cloudEntries` interleaves them so a falling cloud
  always has a sliding one beside it, and a test holds that: three in a row dropping
  together is a different wrong thing from a curtain, but it is still one thing happening
  several times. Each starts *fully* outside on its own edge (trailing edge exactly on it,
  not a corner still poking in), and each travels in **one axis only** — a cloud arriving
  diagonally would be the only thing on screen moving in two directions at once, which is
  the sort of thing a refactor of the start frames introduces silently, so it too is a
  test. The animation is 2.3 s on `position.x` or `position.y` with a `.backwards` fill — the same convention the wazzup mask and the claude-peek slide use,
  because CALayer does not animate `frame` cleanly, and `.backwards` is what parks a
  delayed cloud off-screen instead of showing it at its destination until its turn. The
  delays interleave the two sides (0 / 0.08 / 0.14 / 0.22 / 0.34 / 0.46 / 0.52 s): clouds
  arriving together read as one image cut in half.

  **And then they never quite settle.** A cloud that parks is a picture; a cloud that keeps
  breathing is weather. Once its slide lands, each one drifts for the rest of the clip — a
  sideways sway of 1.3–2.4 % of the screen width with a little rise and fall under it,
  `autoreverses`, forever. It is **additive, on `position` rather than `position.x`, and
  begins only after the slide has finished**: the two would otherwise both be driving the
  same property, and an additive delta on top of a resting model value is the one form that
  cannot fight the animation that put the cloud there. Every cloud has its own period
  (6.7–12.1 s) and no pair is a small multiple of another — seven clouds breathing in step
  is one object wobbling, which is more obviously artificial than not moving at all — and
  neighbours sway in *opposite* directions, so their overlap churns instead of opening and
  closing as one seam. All three properties are tests.

  **The gloom** is a black layer ramping to **0.62** over 2.4 s. Not black — what is being
  darkened is a live demo and the room still has to be able to read it, the same trade
  `TvStatic.defaultAlpha` makes. The ramp is deliberately **over before the first roll of
  thunder** (2.70 s): a screen still visibly darkening when the lightning goes off reads
  as the flash dimming the desktop, which is backwards.

  **The rain falls between two POINTS, and that is the whole lesson.** The first cut was a
  `CAEmitterLayer`, which expresses direction as `emissionLongitude` — an angle whose zero
  and whose sign are a *convention* rather than a coordinate. On this layer it came out
  sideways: a dense band of vertical streaks sliding **left** under the cloud base, never
  reaching the floor, which is exactly what it looked like in the room. `RainStorm.Drop`
  now carries a `start` and an `end`, which cannot be misread, cannot flip with a layer's
  geometry, and can be asserted in a test that never opens a window — `testADropActually
  FallsToTheFloor` and `testTheDropLeansLeftAndOnlyALittle` are that bug written down.

  Drops are born on the **lowest** cloud base (`rainLineY`) so none is ever born in clear
  sky above a cloud that is still covering it, and spent just past the bottom edge, so
  neither end of a streak is ever seen appearing or stopping. One number — `depth` 0…1 —
  carries length (18→64 pt), width, speed (900→2000 pt/s) and brightness together, the
  same trick the snow uses, so a drop can never read as a contradiction. Each leans **6 %
  of its own fall to the left** (about 3.4°, Victor: *"perhaps slightly diagonally to left
  a bit"*) and the streak is **rotated onto its own path** — a vertical sprite travelling
  at an angle reads as a drop sliding sideways, which was the other half of what the
  emitter got wrong. The entry span reaches past the upwind edge by as much as the lean
  will carry a drop across, or the far side of the screen would be visibly drier.

  330 drops/s are released by one repeating timer at 30 Hz, not by 6 000 pre-scheduled
  work items; the tick rate is fixed and the *count* per tick is what ramps (1.5 s lead-in,
  2.6 s ramp), with the fractional part spent as a probability so a light ramp does not
  round to zero and start the rain abruptly at half strength. The fall is timed **linear**:
  over two thirds of a second the acceleration of real rain is invisible, while an ease of
  any kind is not — it reads as the drop slowing down near the floor. The timer is
  identity-guarded against `activeEffects["storm"]` and invalidated by `clearStorm`, or it
  would keep dropping rain into a detached layer for as long as the app runs.

  **The lightning** fires on `thunderOnsets` — 2.70 / 5.45 / 9.40 / 14.45 s, measured off
  the clip with a 50 ms RMS envelope, keeping the four loudest rolls and dropping two that
  sat inside another's tail. One strike is a **stutter, not a fade**
  (`[0, 0.55, 0.08, 0.38, 0.05, 0]` over 0.55 s): real lightning is two or three strokes a
  few tens of ms apart, and a single smooth ramp looks like someone turning a lamp on. It
  begins and ends at fully transparent, which is what keeps an interrupted strike from
  leaving the desktop under a white sheet with nothing running to take it off; and the
  onsets are spaced further apart than a strike lasts, because two keyframe animations on
  one layer do not blend — the later one simply wins and the earlier one stops mid-stroke.

  This is the one in-clip-cue effect driven from the **press** path rather than from
  `playSound`, and that is deliberate. Every roll in this recording swells over ~300 ms,
  so a flash inside a swell still reads as the flash that caused it — unlike the FBI
  knock's 22 ms bang or the heartbeat's onsets, which need the visual to own the audio. In
  exchange the tile still storms when the tablet plays the clip through its own speaker
  and the Mac never sees a `/sound/play` at all, which is exactly what the seven play-path
  tiles give up.

  Everything hangs in **one container** (gloom, clouds, flash, rain, in that order — the
  gloom is what the clouds and the rain are seen *against*, and the drops go on top
  because only drops in front of the gloom read from the back of a room), so the end is a
  single 1.4 s fade of the lot rather than the clouds sliding back out, which would cost
  another 2.3 s after the sound has stopped. The self-stop at the clip's length is the
  lifecycle rule's authoritative teardown and is identity-guarded; `clearStorm` cancels it
  and `stopAllActiveEffects` calls `clearStorm` explicitly, because a pending self-stop
  would otherwise fire into a detached container and clear the `"storm"` key out from
  under whatever the next press put there. `/test/storm`, `/test/storm/stop` and
  `/effect/storm` fire it silently.

  The clip itself is **public domain**: *Rain and thunder* by David Öhlin (2006),
  Wikimedia Commons, normalised to −14.6 LUFS / −1.2 dBTP like the rest of the board.
- **🌑 Death Star** (sfx #55 `55_star_wars.mp3` → `star-wars` / `star-wars/stop`,
  `showStarWars`): a Death Star climbs the diagonal out of the bottom-left corner and
  **stops low and left of centre** (`starWarsRestPoint` = 0.272 W, 0.347 H — its
  centre, a spot Victor drew on the screen himself), 0.69 of the screen height
  across, in 6.5 s of the 10 s clip; the last 3.5 s it simply hangs there.
  - **The artwork is the Death Star II, mirrored** (2026-09-18, the second art
    change that day). `124-1240061_death-star-2-…png`, 460 × 440 and the only
    copy of this render with a real alpha channel: the unfinished sphere, its
    superlaser dish on one side, the ribbed construction lattice eating the
    other. The source has the dish up-**left** — pointing back down the diagonal
    the thing has just climbed. **Flipped on OX it leads with the dish** and
    drags its scaffolding behind it, which is the only orientation that reads as
    arriving rather than leaving.
  - **The recipe is one flip and one integer crop. Nothing is resampled.** The
    circle is *measured*, not assumed: a least-squares fit to the smooth left
    limb (max residual 1.0 px) gives centre 235.0, 222.5 and r 191.4, and no
    opaque pixel anywhere stands more than 0.9 px outside it. The flipped image
    is cropped to a 429 × 429 box centred on that circle, so the sphere fills
    **0.8924** of the artwork's height: `starWarsSphereFraction` (0.893) and
    every size derived from it are untouched, the sphere is still centred in its
    canvas the way `layer.position` assumes, and **no code changed**. The box is
    integer on purpose — the source's transparent background is *white*
    (255,255,255,0), so any resampling would bleed white into the limb, the
    fringe this effect has already been burned by once.
  - **The alpha is kept, not redrawn — this art is meant to have holes.** The
    previous asset threw its alpha away and painted an exact circle, because a
    whole sphere that is subtly translucent reads on cream slides as a ghost.
    Here the gaps ARE the picture: 15.9% of the sphere's trailing half is fully
    transparent (the construction lattice) against 0.0% of its leading half, and
    a circular mask would fill that lattice with the source's white background.
    What was checked instead is the thing that actually bit us — the limb
    averages rgb 23/31/34 over 1139 samples and 0.4% of it is near-white, so
    there is no cut-out halo to inherit.
  - **429 px where the last one was 966**, so the sphere is magnified ~4× on the
    retina instead of ~1.8×. That is the price of the alpha channel: the 860 ×
    906 version of the same render downloaded beside it is *fully opaque*, with
    the transparency checkerboard baked in as pixels.
  - **Two shapes failed before it and both lessons still bind.** The first
    `death-star.png` was a *crop*, cut off flat along its left and bottom edges,
    so the only place those cuts were invisible was welded into the bottom-left
    corner; pulled 10% inboard it showed two straight slices. Its missing limb
    was then **rebuilt** by radial extrapolation, which bought back the
    silhouette but not the picture — the fabricated limb was a pale smeared
    crescent that read as the sphere being half transparent, the exact complaint
    it was meant to fix. The third was a whole render
    (`wallpapers.com/images/hd/death-star-artwork-png-nvm-xpb738481cx20df5.png`),
    squared from 4.5% oblate and cut to an exact circle. Hence the two rules
    above: **measure the circle, invent no pixels.**
  - **Candidates are rejected on their drop shadow, not their looks.** Most Death
    Star cut-outs on stock sites carry an opaque shadow blob fused to the
    silhouette; a circular mask makes it fully opaque and it lands on screen as a
    grey smudge welded to the limb. A candidate whose alpha≥128 bbox is an ellipse
    *and* whose filled area matches that ellipse is shadow-free — that test, not the
    thumbnail, picked the previous render out of ~50.
  - The result ships **in the app bundle**, and only there — it
    used to have a downloads-folder fallback, where one tidy-up would have
    silently killed the effect. (The four effects that still read an external
    file — love-hands, brother, gangnam, fail — go through
    `EffectsConfig.assetURL(_:)` and degrade to doing nothing.)
  - **Sizes are stated as the SPHERE, never as the picture** (`starWarsSphereHeight`
    0.69, `starWarsSphereFraction` 0.893 = how much of the artwork's height the sphere
    fills). The old code sized the *image* to 0.40 H, but the image was a crop, so the
    sphere was really 0.462 H — which is why "half again bigger" is 0.69 and not 0.60.
    Re-cut the art and `starWarsSphereFraction` is the only number to change.
  - **It starts tangent to the corner**, i.e. exactly one radius outside it along the
    line to the rest point, so the first frame already has a sliver on screen. The old
    start was a hand-tuned bbox offset that still spent ~0.3 s on an empty screen
    (and, before that tuning, ~3 s — the image's top-right corner is transparent).
  - **Speed**: the path is now ~2.5× longer than the corner-park it replaced, and it is
    covered in 6.5 s instead of 8, so the thing moves **three times** as fast as it did.
    Twice was the ask; at exactly twice, the longer journey would need 9.8 s and no
    longer fit under the clip.
- **⏲️ Microwave** (tile #61, repurposed from "dinner"): a **kitchen timer ticks and
  the microwave's door swings open on the BING**. `61_dinner.mp3` is now a few
  seconds of ticking followed by a bell (the ticking was lifted +12 dB against the
  bell so it survives a room PA; the bell keeps its full dynamic punch), and
  `showMicrowave` puts a translucent (85%) cartoon microwave in the middle of the
  desktop, fitted aspect-preserved inside **80% of the screen**. **The entire point
  is one sync**, so the cue is *measured off the file*, not guessed:
  `EmojiAnimator.microwaveBingOnset` = **2.695 s**, the beginning of the rising
  front toward the peak (peak at 2.700 s) — re-cutting the clip means re-measuring
  that number. The 16 gif frames are **NOT a loop** (frame 0 = closed door, frame
  15 = fully open), so the layer holds frame 0 through the ticking and only then
  runs the swing at the gif's native 25 fps (0.64 s), holding the open door through
  the bell's decay before fading out with it. That fixed **in-clip** offset is why
  the effect **owns its own audio** on the routed `/sound/play` path (the radar's
  pattern) and is deliberately **absent from `SoundEffectMap`**: a separate press
  round-trip cannot be trusted to land on the same millisecond, and mapping both
  would open a second door with no bell behind it. On Bluetooth output the **whole
  visual timeline shifts by the same A2DP compensation** the audio does
  (`clock0 = CACurrentMediaTime() + btComp`), so the door never flies open ahead of
  the sound reaching the speaker. The art (`Resources/microwave.gif`) is cropped to
  its content **symmetrically about the source frame's centre** — minimal, but the
  closed microwave still sits dead-centre and the door keeps room to swing out to
  the left. The tablet thumbnail is the gif's **own first frame** (door shut), so
  the tile shows the "before" of the animation it fires. `/test/microwave` and
  `/effect/microwave` both fire it **with sound** — the one of these that is not
  silent, since a soundless microwave would just sit there for 2.7 s and then
  open for no reason.
- **🕳️ Iris close** (tile #31, repurposed from Tarzan): a cinematic "iris out"
  blackout. The Android tile #31 is redrawn as a **black circle
  with a white centre and four inward-pointing arrows** (vector `sfx_31_iris.xml`);
  its own mp3 is a **silent clip** but keeps the asset id `31_tarzan.mp3` (protocol/
  manifest stable). It **stays in `SoundEffectMap`** (`31_tarzan.mp3` → `iris`):
  the **press path** drives the visual, so it isn't double-triggered. **Paired
  sound:** the iris was originally soundless, but to keep **every** tablet
  thumbnail audible on the Mac, `onSoundPlay` now special-cases `31_tarzan.mp3` to
  play the **dramatic gong** (`50_gong.mp3`, ~8.6s ≈ the iris length) — like
  radar/money, the routed play path owns the sound while the press path owns the
  visual. `showIrisClose` itself stays silent (the CALayer effect plays no audio).
  `showIrisClose` overlays a **radial
  `CAGradientLayer`** (square, side = screen diagonal, so the gradient is a true
  circle and location 1.0 lands on the corners) — transparent centre, opaque
  black edge, with a soft transition band. Animating the gradient `locations`
  shrinks the clear hole from the screen-circumscribing circle (nothing hidden)
  to nothing over **5s** (`.easeIn`) — black creeps in **from the corners** and
  swallows the screen. It then **dwells ~1s on full black and auto-fades back out
  over ~1s** to reveal the screen (no second press needed). **Pressing the tile
  again** before that auto-reveal cancels early with a quick (~0.35s) fade
  (`cancelIris`). The effect is deliberately **kept out of `activeEffects`** so
  `stopAllActiveEffects()` (which the tablet fires before *every* press) leaves it
  alone — that's what lets the second press reach `showIrisClose` and toggle
  instead of being wiped + restarted. `/test/iris` and `/effect/iris` call
  `showIrisClose` directly.

- **💀 Game over → 📺 CRT shutdown** (tile #59 `59_game_over.mp3` → `game-over` /
  `game-over/stop`, `showGameOver` + `showCrtShutdown`/`CrtShutdown.swift`): the
  picture first — **TV white noise** (`TvStatic.swift`) with the GAME OVER art
  centred at 70% of the screen width on top of it, held for **exactly the clip's
  length** (read off `59_game_over.mp3`, ~1.6 s; 2.0 s if the file is missing,
  deliberately short so an absent sound cannot leave a long dead screen). The
  backdrop **used to be a flat 70% black wash**, which only dimmed the desktop
  and said nothing; the tile is a set that has lost its signal, so it now shows
  what such a set shows. The noise is **translucent** (`TvStatic.defaultAlpha`,
  **0.40** — it was 0.55, dropped because the demo underneath has to stay
  followable while the gag plays), **swells in over 1 s**
  (`TvStatic.fadeInDuration`, `.easeInEaseOut` on `opacity`) rather than slamming
  on, so the signal *degrades* into noise instead of the screen cutting to it —
  the grain is already boiling underneath from frame one, what rises is only the
  veil, and it is at full strength well before the tube starts closing — and is
  **animated at 16 fps** — 6 bitmaps rendered ONCE at a **quarter** of the screen's resolution
  (binary black/white, not random greys, which average into a flat wash once
  translucent), cached per screen size, and cycled by a `CAKeyframeAnimation` on
  `contents` with `calculationMode = .discrete`. Nothing is generated while it is
  on screen. `magnificationFilter = .nearest` on the blow-up is what keeps the
  pixels square: interpolated, the grain is grey mush rather than speckle.
  The tablet's `/sound/stopped` → `game-over/stop` is the polite end and is
  **not** the authoritative one (`stopGameOver` clears it one close-length later,
  if it arrives at all) — `trackEffect` is.
  **Then the desktop switches off like an old cathode-ray television.** Two black
  rectangles come in from the top and the bottom edge over **0.7 s** (`.easeIn`),
  leaving the middle transparent while they close, until only a **10 pt white
  line** is left across the screen; it **holds 0.15 s**, then collapses from both
  ends towards the centre over **0.4 s** (`.easeIn`), leaving a white dot that
  flashes out over 0.18 s. 0.2 s of black, then the whole thing **fades away over
  0.45 s** and the desktop is back — **2.08 s** end to end
  (`CrtShutdown.totalDuration`, which is what `trackEffect` is given, so it
  self-terminates like everything else).
  The mechanics are the **iris's, reused**: plain `CALayer`s on `hostLayer`, one
  `CABasicAnimation` per phase on a single `CACurrentMediaTime()` clock via
  `beginTime`, `fillMode`/`isRemovedOnCompletion = false` so a finished phase
  holds its end state while the next runs, and the same gentle opacity fade
  `cancelIris` uses to give the screen back. Only the shape differs: a rectangle
  closing from two edges instead of a circle closing from the corners. Each
  shutter is a **full-screen-sized** black layer parked off-screen that slides
  exactly half a screen, so the two meet on the middle with no seam to align; the
  white line is drawn **on top** of them (not in a gap) and collapses via
  `transform.scale.x` → 0, which pulls both ends in at once.
  **It closes OVER the game-over screen, and changes nothing about it.** The CRT
  container is added to `hostLayer` *after* the game-over container, so it is
  strictly above it, and the game-over layer is **kept alive through the whole
  close** (`trackEffect(duration: clip + CrtShutdown.closeDuration)`,
  `stopGameOver` delayed by the same 0.7 s): the static keeps boiling and the
  picture stays put underneath until the black has met in the middle. Dropping it
  when the shutters started — which is what the first cut of this did — flashed
  the bare desktop through the gap they had not covered yet, the opposite of a set
  switching off. Nothing brightens or is repainted: the only white is the line,
  and that arrives after the black is complete.
  **Arming, and what cancels it.** The close is scheduled from `showGameOver` for
  the deadline at which the clip ends. It cannot check `activeEffects` to see
  whether the run is still alive (its own cleanup is on the same clock), so it
  carries an epoch,
  `_crtArmEpoch`, bumped both by `showGameOver` and by `stopAllActiveEffects`.
  A `/effect/stop-all` during the picture — what a preempting tile press and a
  non-restartable re-tap both send — therefore cancels the pending close, and a
  stop-all *during* the close clears it through the normal `activeEffects` loop.
  `game-over/stop` deliberately does **not** disarm it: that message arrives
  precisely because the sound ended, which is the moment the tube is meant to
  close. Unlike the iris the effect is **inside `activeEffects`** (it is not a
  toggle — nothing needs to survive stop-all), so `GET /state` lists it as
  `crt-shutdown` while it runs. `/test/crt-shutdown` and `/effect/crt-shutdown`
  fire the closing alone.

- **🙅 Wasn't me** (tile #76 `76_sfx_118.mp3` → `wasnt-me`, `showWasntMe`): a 3D hand
  wagging its index finger "no-no", parked in the **bottom-left (SW) quarter** of the desktop
  for exactly as long as the clip runs, then fading out on its own over the last 0.8 s. The
  art is a 24-frame transparent GIF looping in under a second, so unlike the one-shot overlays
  (cavalry, counter-strike) the frames **repeat forever and the sound decides when it is
  over** — the gesture is a denial held for as long as the denial is being sung, not a thing
  that happens once. Length is read off the mp3 (6.55 s) rather than hardcoded, so a re-cut
  clip stays in sync. It is **centred in the quadrant, not glued to the corner** the way the
  Counter-Strike operators are: those stand on the screen edge, this is a floating hand, and a
  hand jammed into the corner reads as a cropping accident rather than a gesture. Fitted
  aspect-preserved inside **80 %** of the quarter — that margin is what keeps it off both
  screen edges. Head and tail are **one keyframe opacity track**, not two animations, so the
  fade-out can never begin before the fade-in has finished on a short clip.

- **🔫 Minigun → Counter-Strike AK-47** (sfx #22 `22_minigun.mp3` → `bullet-holes`,
  `showBulletHoles`). **A session, not a burst, since 2026-09-23.** Victor: the gun should
  stand still when it appears and fire — noise and bullets — *only while the mouse button
  is held*, taking the clicks away from the app underneath.
  - **The gun** is the CS 1.6 AK-47 view-model (`Resources/ak47.png`, hand + rifle, the
    light-grey background flood-filled out and trimmed; its right and bottom edges are flat
    cuts, which is where the screen edges are in the game). It rises out of the bottom edge
    in 0.3 s, **at rest**: no flash, no noise, no holes. It replaced `minigun.gif`, which
    was drawn mid-burst in every one of its 64 frames and so had no rest pose to show.
    Width **20 %** of the screen (born 40 %, the in-game share; halved the same day because
    it hid the slide it was shooting at); the muzzle (`minigunSpriteMuzzle`, the front sight post) is
    the anchor, at `0.35 W + mouseX × 0.5` — a centred cursor puts it at 0.60 W, right of
    centre like the game. It never rotates.
  - **Moving without firing walks it**: horizontal mouse travel advances a bob phase and
    tops up a bob energy that drains when the mouse stops (`minigunBobOffset`, a
    figure-of-eight, 9 × 11 pt at full energy), so the gun sways like a view-model when the
    player walks and settles to rest when the mouse does.
  - **Holding the left button fires**: 10 rounds/s (an AK's ~600 rpm), each one a bullet
    hole near the crosshair, a drawn muzzle flash (jagged star, re-rolled rotation and size
    every shot, 60 ms) and a recoil kick (back-down 10 × 14 pt, 90 ms). The noise is the
    tablet clip on the animator's **own `AVAudioPlayer`**, started on the press with no
    Bluetooth delay and looped over its uninterrupted first 2.35 s (`minigunFireLoopEnd` —
    the clip has a lull at ~2.4 s and a spin-down tail), faded out in 60 ms on release.
  - **Precision: half the area.** Rounds land within `minigunSpreadRadius` = 140 / √2 ≈
    **99 pt** of the crosshair (area goes with r², so half the area is √2 on the radius),
    density peaking at the centre (r ∝ u). Holes sit below the gun, capped at 250.
  - **The clicks are taken**, by an effect-owned `CGEventTap` on the main run loop (same
    shape as the bomb's): left down/drag/up and Esc. `minigunMouseDecision` is the rule —
    only a press that *started* while the gun was up is swallowed, down to its release — its
    **drags are retyped as plain `mouseMoved` and passed on**, not dropped: dropping them froze
    the pointer (and so the aim) while the trigger was held, and a move is the one thing the
    app underneath can receive without seeing half a click; a
    press already in progress keeps its drag and its up, or the app underneath would be left
    holding a button that never comes up. **Esc puts the gun away.**
  - **Self-termination**: the 60 fps tick that drives the crosshair, the gun and the rounds
    also ends the session `minigunIdleLifetime` (**10 s**) after the last activity (the gun
    coming up, or the trigger's release), with a **90 s** hard cap and a scheduled backstop
    past it. A re-press puts it away, as does stop-all (`stopMinigunSession`, which drops
    the tick, the crosshair, the hidden cursor, the tap and the noise — everything outside
    the container). The natural end lowers the gun and resorbs the holes over 0.6 s.
  - **The tablet's `/sound/play/22_minigun.mp3` plays nothing** (`EffectsEngine.playSound`
    answers `minigunIdleLifetime` as `durationMs`): the noise belongs to the trigger. The
    press path (`/sound/pressed/…` → `bullet-holes`) still raises the gun.
  - Log lines `🔫 AK-47 up`, `🔫 trigger pulled` / `released`, `🔫 AK-47 put away`.

- **🪚 Chainsaw cursor** (tile #18 `18_chainsaw.mp3` → `chainsaw`, `showChainsawCursor`):
  **the mouse pointer IS a running chainsaw until Escape** — the real cursor is hidden and a
  16-frame sprite loops on it, chasing `NSEvent.mouseLocation` at 60 fps. **A session, not a
  clip, since 2026-09-23** (Victor: *"Drujba trebuie să dispară doar la Escape; să sune totul
  în buclă, iar când apăs cu mouse-ul, ea trebuie să taie doar atunci, nu permanent"*): it
  idles on the pointer and **bites only while the left button is held**.
  It is the third member of the hidden-cursor family
  (💘 spiral-hearts' beating heart, 🔫 minigun's reticle) and follows their rules: it lives
  **outside `activeEffects`** because it owns a follow timer *and* a hidden system cursor,
  so `stopAllActiveEffects` tears it down **explicitly** — a generic sweep would drop the
  layer and leave the desktop with **no visible pointer at all**. The hide is armed through
  `armBackgroundCursorHiding()` (the private `SetsCursorInBackground` flag) so it also
  applies while Victor is in someone else's app, and the unhide is balanced by a single
  `_chainsawHidCursor` flag so a spurious stop can't force the cursor back mid-run.
  - **The clicks are taken** by the saw's own `CGEventTap` (left down/drag/up + Esc), on the
    AK-47's rule, `minigunMouseDecision`, reused as is: only a press that *started* while the
    saw was up is swallowed down to its release, its drags are retyped as plain `mouseMoved`
    so the saw keeps following the hand, and a press already in progress keeps its drag and
    up. Down → `startChainsawCut` (kerf restarts at the pointer, never joined to the last
    cut — the saw was in the air in between; sparks on; throttle open). Up → sparks off,
    throttle closes. The kerf and the fallen pieces **stay** until the saw is put away.
  - **The engine noise is the saw's own** (`ChainsawSound`), and the tablet's
    `/sound/play/18_chainsaw.mp3` plays **nothing** (`EffectsEngine.playSound` answers the old
    6.09 s as `durationMs`, so the tile still lights like before). Both noises are cut out of
    the clip itself, read off its RMS in 0.1 s windows: pull-start **0–1.7 s** (played once),
    idle **1.7–2.7 s** (steady −30 dB), full throttle **3.1–5.8 s** (steady −16 dB, peaks
    −2.5 dB). Two `AVAudioPlayerNode`s loop their stretch for the whole session and the button
    only moves their volumes (equal-power, **60 ms** attack, **300 ms** release — a saw winds
    down, it does not switch off), so the scream starts with the finger. The rev runs through
    an `AVAudioUnitVarispeed` at **1.08** (+1.3 semitones): with −2.5 dB peaks there is no
    headroom for "louder" by gain, so the extra bite comes from pitch — it is already 14 dB
    over the idle. Loops are PCM buffers with their seam **crossfaded into the tail**
    (120 ms, blending into the audio just before the loop's start), not an `AVAudioPlayer`
    rewind like the AK's: a rewind is a jump in the waveform, fine for a two-second burst and
    a click every second for a saw that idles for minutes. Blending into the tail (not the
    head) is also what makes the intro → idle hand-over seamless. Teardown fades the mixer out.
  - **Art**: `Resources/chainsaw-frames.png`, a **4×4 sprite sheet**, not a gif. The smoke
    puff and the antialiased blade need real **8-bit alpha**, and gif carries 1-bit — a gif
    of this fringes white against a dark desktop. The 16 equal cells are sliced once with
    `cropping(to:)` into a **lazy static** (`chainsawFrames`): a press must be instant
    because the cursor is already moving, so the ~1.7 MP sheet is never re-decoded per
    press. The sheet is quantised to 255 colours (1.8 MB → 329 KB, visually identical at
    450 pt) — palette PNG keeps per-entry alpha, so the soft edges survive.
  - **Anchor = the biting point**: the layer's `anchorPoint` is **mid-bar, on the lower
    row of teeth** (`chainsawCutAnchor`, x ≈ 0.600, y ≈ 0.815 from the top — sampled off
    the bar's bottom edge across the calm frames, which jitter between 0.77 and 0.90). That
    point rides the pointer, so the kerf comes out from **under the teeth** with the whole
    machine held above the cut, the way a saw is actually used. Two earlier anchors were
    wrong for instructive reasons: the **blade tip** read beautifully as a pointer but put
    the cut ~180 pt from what the hand was aiming at, and you cannot saw around a window
    with the groove appearing a hand's width away; the **sprite centre** fixed the aim but
    split the screen open through the middle of the engine block, so nothing on screen said
    which part of 450 pt of drawing was doing the cutting.
  - **Sparks** (`beginChainsawSparks`, `CAEmitterLayer` at `zPosition` 9600 — *over* the saw,
    because they fly toward the room): the answer to that last problem. Two cells, emission
    longitude **0 and π** with a narrow **±20° fan**, 110/s each, life ~0.55 s, velocity 420
    ± 260, `yAcceleration` **−900** (the host layer is y-up, so gravity is negative),
    `renderMode = .additive` over a soft white radial dot tinted orange with `greenRange` /
    `blueRange` spread, so the shower has hot and cool sparks in it. The narrow fan is what
    makes it read as material thrown sideways out of a groove rather than as an explosion at
    the cursor. It follows the **button, not the motion** (since 2026-09-23;
    before that it burned permanently): on for as long as the blade is in, moving or not —
    a blade held still against material still throws chips — and off while the saw is in
    the air, where a shower would point at a kerf nobody is making. On
    teardown `birthRate` drops to 0 first, so sparks already in the air finish their arc
    instead of being cut off mid-flight, then the emitter fades with the saw and the damage.
  - **Timing**: 16 frames at **15 fps** (1.07 s rev cycle). It started at 24 fps and read as
    *twitching* — the source frames jitter in position as well as in shape, and at that speed
    the eye tracks the jumps instead of the saw; slowing it turns the same jitter back into
    the heavy vibration a chainsaw at rest actually has. Width **450 pt**, height
    aspect-derived; `zPosition` 9500 so it rides above every other effect (it is the
    pointer). Fade-in is **0.12 s** — the cursor is a thing you are already looking at, and
    a slow fade there reads as lag. The fade-out is 0.25 s and the real cursor comes back
    only **after** it finishes, so the two are never on screen together.
  - **Lifecycle**: **Escape** (consumed by the tap), `stopAllActiveEffects`, the 🛑 icon
    (`isAnythingRunning` asks `animator.isChainsawRunning` by name — a saw that runs until
    Escape is exactly what someone reaches for the icon to kill), `/effect/chainsaw/stop`, and
    a **180 s** cap (`chainsawMaxLifetime`, generation-guarded) as the self-termination
    guarantee for the day the tap is missing (no Accessibility: no cutting and no Esc — the
    log says so). **No `onStop` entry any more**: the tablet reports every clip's completion
    as `/sound/stopped`, and the saw must outlive the tile. `/test/chainsaw`,
    `/test/chainsaw/stop` and `/effect/chainsaw` drive it, now with the engine noise.

- **🔥 Fireball & fires** (tile #11 `11_fire.mp3` → `fire` / `fire/stop`, `showFireCursor`):
  the pointer becomes a **burning sphere of fire**, and every fire on screen is one he put
  down with it: a click lays a fire where the ball was, the wheel sizes **that** fire on the
  spot, the next click starts another, and Escape puts
  the ball out and leaves them burning.
  The real pointer is hidden for the run (fourth member of the hidden-cursor family, bound
  by the same rule: **outside `activeEffects`**, torn down explicitly by
  `stopAllActiveEffects`, hide armed through `armBackgroundCursorHiding()` and balanced by
  `_fireHidCursor`). It replaced the tile's old "Lady in Red" clip (tile art and asset
  renamed; the original mp3 is in `backup.zip`).
  - **Art for the fires he lights**: `Resources/fire-frames.png`, an **8×5 sprite sheet** of
    40 cells, keyed out of a black-background gif with **alpha = luminance × 2** (clamped).
    The ×2 is not a brightness trick: straight luminance-as-alpha leaves the orange edges and
    every spark half-transparent, which over a slide reads as a washed-out stain instead of
    fire *on top of* it. Same sheet-not-gif reasoning as the chainsaw — gif's 1-bit alpha
    would fringe the glow black on every desktop. Sliced once into a lazy static
    (`fireFrames`). Each fire runs the 40 frames at **30 fps** (1.33 s loop) — the source
    clip's own rate, kept rather than halved to the chainsaw's 15, because these are on
    screen for a **36 s** sound and fire at 15 fps reads as a strobing loop within seconds —
    and each gets its own random phase into the loop, or a row of them flickers in lockstep
    and announces "sprite sheet" louder than any of them announces "fire".
  - **The fireball pointer** (2026-09-22, Victor: *"doar vorbim despre înlocuirea
    cursorului"*). It replaced the **drawn match** of 2026-09-18/19, and the match is worth
    remembering, because it was an answer to a real problem: between 09-08 and 09-19 a bare
    flame burned on the pointer, which read as a *decal* over the slide, and the gesture the
    effect invites — clicking to set something alight — had nothing doing the lighting. The
    match gave the flame a cause, and 09-19 then took the flame off its head so the planted
    fire stopped being a *copy* of something already on screen. A fireball keeps both of
    those wins and costs the stick: it is not a flame *on* the pointer, it **is** the
    pointer, and "why click?" still has an answer — to put some of it down.
    - **One ball, not three.** It shipped that afternoon as a rotation of three sheets and
      lost two of them within the hour (*"bila a doua … sfera care arde ca un soare … las-o
      doar pe ea, de departe"*). The rotation was answering a question nobody had asked — a
      tile pressed twice in an hour does not need to surprise anybody the second time — and
      the other two were a spiky burst and a flat cartoon, neither of which is what a fire
      *starts* from. Both sheets are **deleted** rather than left unused: 5 MB of png in a
      public repo that nothing reads. `tools/make-fireball-sheets.py` and commit `cc41ea4`
      are where they live now.
    - **Art**: `Resources/fireball-plasma.png`, a **6×6 sheet** of 32 cells at **16.7 fps** —
      a dense sphere of dark rock under glowing veins. A sheet and not the gif it came from,
      for `fire-frames.png`'s reason. It carries **its own fps** rather than the flame's 30:
      a sprite played at somebody else's rate either strobes or crawls.
      - The converter is `tools/make-fireball-sheets.py`, and the awkward bit is documented
        there. The sphere's interior is **genuinely black** (rock between veins) and a
        luminance key cannot tell it from the black around the ball — left alone the sphere
        becomes a stencil and the slide shows through every crack. Flood-filling the
        silhouette is the obvious fix and it **does not work**: the rim is filaments, not a
        contour, and the fill leaks through. So the ball is treated as the disc it is — a
        measured radial profile puts the body's edge at 0.78 of the half-width, so everything
        inside 0.75 is forced opaque and 0.75 → 0.83 feathers back to the keyed value.
      - The grid is **typed into `fireball`, not read off the png**, so
        `testTheFireballGridHoldsItsFrames` is what catches a drift: too few cells and the
        crop runs past the bottom edge (a hole in the loop), a spare row is empty cells the
        png is carrying for nothing. `testTheFireballSheetIsInTheBundleAndCutsCleanly` is the
        other half — it opens the png out of `Bundle.module`, so a sheet that never reached
        `Resources/` fails the build instead of turning the tile into a dead press on stage.
    - **Its CENTRE is the layer's `anchorPoint`.** A ball has no tip, and the middle is where
      the eye puts the pointer, so that is the pixel under the mouse and the pixel a click
      lights a fire on. (The match's anchor was its *head*, for the same reason stated about
      a different shape.)
    - **75 pt wide** (`fireballCursorWidth`), halved from 150 the day it shipped
      (*"micșorează-o la 50%"*) — a bit over a quarter of the flame's `fireBaseWidth` of 280.
      That ratio is the point: this is the *pointer*, and the fire it lights is the thing
      that should be big. It does not move with the wheel, for the reason the match's size
      did not either: the wheel belongs to the fire on the ground, and a pointer that grew
      with it would have him sizing two things with one gesture.
    - **It is drawn UNDER the fires it starts** — `fireballZ` **9 350** against their 9 400
      (2026-09-22, *"să fie randate sub incendiul pe care le lansează"*). It was 9 450, above
      them, for the match's reason: a pointer passes in front of things. A ball of fire is
      not a pointer-shaped arrow, though — drawn over a blaze twice its size it reads as
      *floating on top of* the fire rather than as the thing that started it, and at 75 pt it
      simply disappears into the flame it is sitting on. Underneath, the fire swallows it as
      it grows, which is both the right story and the right silhouette.
    - **After each fire is laid the ball shrinks out of the way** (2026-09-22, *"după fiecare
      așezare a incendiului, bila de foc dispare pentru două secunde, după care reapare …
      mărind impactul focului care l-a născut"*, then *"în loc să dispară, bila să se
      micșoreze de 10x, și apoi resize up"*). On the instant of the click it drops to
      **`fireballShrinkFactor` (0.1)** of its size with no animation, holds there for
      **`fireballShrunkAfterPlant` (3 s)**, and grows back over **`fireballReturnGrow`
      (0.5 s)**, eased out.
      - **It shrinks rather than vanishes**, and the first cut did vanish. Zero opacity gave
        up something the effect cannot spare: the real cursor is hidden for the whole run, so
        a ball at zero leaves the screen with **no pointer at all** — during a drag that meant
        sweeping a line of fires blind. At a tenth it is a 7 pt spark: out of the fire's way
        by any measure the eye uses, and still exactly where his hand is.
      - *Retimed from 2 s / 0.7 s once he had watched it: the quiet is what the new fire gets
        to itself, so it wants to be longer, and the return wants to be quicker, because
        bringing the ball back slowly spends some of that quiet again.*
      - **It shipped not working, and the bug is worth keeping written down.** The entry
        fade was `fillMode = .forwards` + `isRemovedOnCompletion = false`, copied from the
        match, where it was harmless because nothing ever hid the match. A finished animation
        that goes on filling forwards keeps **overriding the model layer**, so the blackout
        set `opacity = 0` and the ball stayed visibly on screen — the hide looks completely
        correct where it is written, and the cause is forty lines away in a line that reads
        like boilerplate. Both of the ball's own animations are **functions** now
        (`fireballEntryFade`, `fireballGrowBack`) purely so
        `testTheBallsAnimationsBothRemoveThemselves` can hold them — the grow-back is the
        same trap one property over, and left filling forwards it would pin the ball at full
        size and make every shrink after the first silently do nothing.
      - **The clock restarts on every plant** (`_fireballHideToken`), which is what makes a
        drag behave: a sweep lays a fire every 50 pt, so only the last one's return survives
        and the ball is away for the whole gesture, coming back once at the end. A plain
        two-second timer per fire would bring it back mid-sweep and take it away again,
        strobing. The trade is real and deliberate: **during a sweep there is no pointer on
        screen at all** — the line of fires appearing under the hand is what tells him where
        he is.
    - **`opacity` fades in over 0.12 s** at the start of a run — the cursor is a thing you are
      already looking at, and a slow fade there reads as lag; out over 0.25 s, with the real
      cursor restored only **after** the fade, so the two are never on screen together.
    - The ball burns on **its own clip's clock** (a repeating discrete `contents` keyframe),
      not on the 60 Hz follow timer. The timer's job is *where* the pointer is; driving the
      sprite from it would tie the flame's rate to how often we can afford to poll the mouse.
  - **A click strikes a fire** (`plantFireAtCursor`). It stands at the ball's pixel, rooted
    there by `fireRootAnchor` `(0.5, 0.10)` — the flame's **root**, near the bottom edge and
    centred, so it grows *upward out of* the spot rather than swallowing it. `zPosition`
    9 400, over the ball and every other effect. `fireMaxPlanted` (60) is the ceiling — out
    of reach for single clicks, reachable by a long drag — and past it the oldest fire goes
    out, which reads as having burnt itself out rather than as a limit.
    - **It catches rather than appears** (2026-09-22, *"focul, când apare, să crească la
      dimensiunea la care este targetat să fie pe parcursul a jumătate de secundă, cum se
      aprinde incendiul"*). `fireCatchDuration` **0.5 s**, eased out, from
      `fireCatchFromScale` **0.15** of the target box — not from zero, because a fire growing
      out of nothing is a dot expanding, while one that starts as a spark and takes hold is
      what the eye reads as catching. Half a second is short enough that the click still
      feels answered at once.
    - It animates **`bounds`, not `transform`**, for the wheel's reason: the anchor is the
      root, so growing the box makes the flame climb *up out of* the spot instead of
      ballooning around its own middle. The model value is the full size from the first
      instant, so anything reading the box mid-climb sees where it is going, not where it is.
    - **The wheel drops a running climb** (`removeAnimation(forKey: "catch")`). A fire
      scrolled during its half second has two answers for its box; the hand on it right now
      wins, or the animation finishing would snap the flame back to the size he just
      scrolled away from.
  - **Dragging draws a line of fire** (2026-09-19, `plantFireIfDragged`). With the button
    held down the ball keeps laying fires as it sweeps, one every **`fireDragSpacing`
    (50 pt)** of travel: the gesture of dragging a match along a fuse — the one thing about
    the old pointer the new one still quotes — instead of one click per flame when he wants
    an edge of the screen alight. The spacing is the whole trick: a drag reports 60+ events a
    second, so without it a single sweep would stack flames on the same pixel and exhaust
    `fireMaxPlanted` before the wrist stopped moving. It is measured from the last fire
    **planted**, never from the last event, so a slow drag spaces them exactly like a fast
    one: speed changes *when* the next fire appears, never how far apart they stand. The tap
    consumes `leftMouseDragged` for the same reason it consumes the down and the up — the
    pair (and everything between) goes or stays together, or the app underneath gets half a
    gesture.
  - **The wheel sizes the fire he just struck, in place** (2026-09-19, Victor: *"then I can
    zoom with the wheel to increase the size of that fire"*). Until then the wheel sized the
    pointer and a click planted at that size, which is backwards: he only knows how big a
    fire should be once he can see it standing on the thing it is burning. So the target is
    **`_firePlanted.last`** — the newest one — and the next click hands the wheel on to the
    fire it starts. One notch is a **multiply** by 1.10, so a step feels the same at a candle
    and at a bonfire. The clamp is 0.30 × at the bottom and **the screen** at the top:
    `fireMaxScale` is `hostLayer.bounds.width / fireBaseWidth`, i.e. a fire can grow until it
    is exactly as wide as the display it burns on. A fixed multiple (3.50 × was the old one)
    made "as big as it goes" a different fraction of a 13" retina than of a projector, and on
    stage that ceiling is the size Victor actually reaches for. `NSScreen.main` is the
    fallback while the overlay has no bounds yet.
    - The resize edits **`bounds`, not `transform`**, which keeps the anchor pinned, so the
      fire swells upward out of the spot it was struck on instead of ballooning around its
      own middle.
    - Trackpad pixels are accumulated into 12-pt notches so a two-finger flick doesn't jump
      from candle to inferno.
    - Scroll is consumed while sizing (no scrolling the app underneath) **except** with ⌘
      held — that belongs to `EventTapManager`'s terminal font zoom, and silently eating it
      for 36 s would look like the zoom shortcut had broken — **and except before the first
      fire is struck**: with nothing planted the wheel has no target, and freezing his slides
      for a gesture that does nothing visible is a cost the effect shouldn't charge.
  - **The size carries over.** Every notch writes `fireRememberedScale` (a **static**, RAM
    only) and `_fireScale`, which is what the *next* fire is struck at — within the run and
    across presses, clamped to the current `fireMaxScale` in case the last run was on a wider
    screen that has since been unplugged. Sizing a fire is a deliberate few seconds of
    scrolling in front of a room; snapping back to default on the next click made that
    gesture disposable. Not persisted to disk on purpose — a restart starts neutral rather
    than from whatever one demo needed.
  - **Escape puts the POINTER out; the fires he lit stay** (2026-09-18, Victor: *"if I click
    Escape, the match and the fire disappear, and only the fire that I've laid on the screen
    remain behind"* — said of the match the fireball replaced). The first Escape runs
    `blowOutFireball`: the ball and the hidden cursor go, the planted fires go on burning
    **and so does the clip**, and the tap stays alive **passing clicks and scrolls through**
    (`_firePointerLayer == nil` is the whole test — no second flag to keep in step). A
    **second** Escape clears them, and takes the sound with them. With nothing planted, the
    first Escape is the full stop it always was.
    - **The first Escape leaves the SOUND too** (2026-09-22: *"la primul escape sa ramana
      focurile + SUNET"*). It used to cut the clip on the reasoning that Escape means
      *enough* — but it does not, when there are fires standing, and a burning screen in
      silence is a screenshot. That press hands him back his mouse and leaves the scene
      exactly as it was; only the press that clears the fires is a full stop, and only it
      calls `stopTabletSound` + `stopAllPlayers`.
    - **What still puts the planted fires out on their own**: the clip's own length, whose
      timer is deliberately *not* cancelled by `blowOutFireball` (it does not touch
      `_fireGeneration`), plus the tablet's stop and `stopAllActiveEffects`. The
      self-termination rule holds — nothing here can be left burning by a lost message.
    - This is the first effect with a *user* exit, and it needs one: 36 s is far too long to
      sit through if the tile lands at the wrong moment. Escape is taken by a **`CGEventTap`,
      not an `NSEvent` global monitor** — a monitor can only observe, and an Escape that also
      closed the user's dialog would make the effect cost something. The keypress is
      **consumed**, and it stops the routed clip too (`stopTabletSound` + `stopAllPlayers`);
      a press the tablet chose to play on its **own** speaker is not ours to stop. The click
      pair is consumed together (`leftMouseDown` *and* `leftMouseUp`): delivering the up
      alone would hand the app underneath half a click — a button that highlights and never
      fires, a text view that loses its selection.
  - **Lifecycle**: three ways out — the length of `11_fire.mp3` (`AVURLAsset`, 35.88 s
    fallback, generation-guarded), Escape, or the tablet's `onStop` → `fire/stop`. The
    clip's length stays the authoritative one for the usual reason: a lost `/sound/stopped`
    would otherwise strand the desktop with no cursor. `/test/fire`, `/test/fire/stop` and
    `/effect/fire` fire it silently.

- **💘 Spiral hearts** (tile #42 `42_saxophone.mp3` → `spiral-hearts` / `spiral-hearts/stop`,
  `showSpiralHearts`): **the cursor becomes a pulsing red heart** for the length of the clip
  (the real pointer is hidden — it is the first member of the hidden-cursor family the
  chainsaw and the minigun crosshair later joined, and like them it lives *outside*
  `activeEffects` so `stopAllActiveEffects` tears it down explicitly), and hearts peel off it
  at **6/s** and spiral up and off the top of the screen. Each riser gets its own net
  sideways drift, a sine wobble laid over the rise, a rotation wobble and a 3.2…4.5 s life.
  Every pending spawn is a cancellable `DispatchWorkItem`, so an explicit stop silences the
  emission instead of letting hearts keep appearing for the rest of the clip's length.
  Not to be confused with **💓 Heartbeat** (tile #13), which is a lens on a screen capture
  and shares nothing with this.
  - **A riser is a CLONE of the pulsing heart (2026-09-11).** It is born at the cursor
    heart's glyph size, at **the exact scale the pulse happens to be at on that frame**
    (read off `presentation()` — the model layer knows nothing about where an in-flight
    animation has got to), at its position, and **fully opaque**. It used to be a random
    44…80 pt glyph that popped 0.6 → 1.5 while fading up from transparent over the first
    0.08 s, which read as hearts *appearing near* the cursor rather than peeling off it. The
    size variety survived by accident: 86.4 pt across the 0.8…1.35 beat spans the same range
    the random one did. The fade **out** at the top of the rise is untouched — a heart still
    has to leave.
  - **The pulsing heart is 0.8× its old size** (`heartCursorFontSize`, 108 × 0.8). The pulse
    is a `transform.scale` animation, so shrinking the glyph leaves the rhythm (0.45 s,
    autoreversed) and the amplitude *ratio* (0.8 ↔ 1.35) exactly as they were. The constant
    is `static` precisely because the risers are clones of it: one number, not two that drift.

- **💕 Love hands** (tile #41 `41_love_hearts.mp3` → `love-hands` / `love-hands/stop`,
  `showLoveHands`): two hands (`love_hand_left.png` / `love_hand_right.png` from
  `EffectsConfig.assetsDir`, square halves at aspect 0.5) slide in from the left and right
  edges over **2.7 s**, eased out, meet at the horizontal centre a fifth of a screen height
  below the middle, and spawn a heart burst out of the meeting point. They then linger until
  the clip is nearly over and **fade** out with it (never an instant cut), identity-guarded
  so an old run's timer cannot kill a newer one — this is the effect the "love-hands pattern"
  in the lifecycle rule above is named after. The hands live in a container that is **added
  to the layer tree and owns both of them**, so every teardown path takes them down together;
  they used to be siblings under `host` with an empty off-tree wrapper tracked in their
  place, and a stop cleared the tracker while leaving the hands on the desktop.
  - **Size and opacity (2026-09-11):** `handHeight` is **1.04 × the screen height** — the
    0.40 it started at, +30 % to 0.52, then **doubled**. They are deliberately taller than
    the screen now: at that size they read as two hands reaching *into* the frame rather than
    two cut-outs sliding across it, and the bottom of the wrists is cropped by the bottom
    edge instead of floating. Everything else is derived from `handHeight` (width, the meeting
    positions, the off-screen start points), so the **motion is unchanged** — same 2.7 s
    converge, same ease, same meeting point.
    The hands are **80 % opaque**, set on the two hand layers and *not* on the container: the
    heart burst is a child of the same container, and it is the hands that should let the
    desktop through, not the hearts. `fadeOutLoveHands` animates the container to 0 on top of
    that, so 0.8 is simply the ceiling the fade starts from.

- **🌈 Rainbow + 🦄 unicorns** (tile #37 `37_rainbow.mp3` → `rainbow` /
  `rainbow/stop`, `showRainbow`): seven translucent bands drawn as a **quarter**-arc —
  the circle's centre is pushed onto the right screen edge, so only the left quarter of
  it is on screen, tucked into the bottom-right corner — smeared in over 2.5 s with a
  `strokeEnd` wiper. The window is **read off the mp3** (13.9 s), not the old 5 s
  default, because the tablet-routed path plays the same clip and used to fade the arc
  ~9 s before the music ended; `stopRainbow()` then fades the container to 0 over 0.8 s.
  Since 2026-08-26 **unicorns hop across it** (`spawnRainbowUnicorns`): seven 🦄 text
  layers, alternating directions, each entering from one edge and bouncing to the other
  along a six-hop quad-curve path (control point at 2× the hop height, so the apex lands
  at 1×), `.paced` so the speed is even along the arcs rather than per-hop. Left→right
  runners are **mirrored** (`CATransform3DMakeScale(-1, 1, 1)`) — the Apple 🦄 glyph
  faces left, and a unicorn running backwards is the first thing the room notices. Each
  fades out at 60 % of its own crossing, i.e. **while the arc is still unrolling**, and
  the departures are spread across the whole window so one or two are in flight at any
  moment instead of a herd leaving together. They are **children of the rainbow
  container**, so they need no tracking of their own: the one identity-guarded
  `activeEffects["rainbow"]` entry tears the whole scene down.

  **Every hoof-fall is on the beat** (2026-09-09). The clip's beat was measured the way
  the FBI knock's onsets were — mono 8 kHz, log-envelope flux in 10 ms windows, then the
  (period, phase) grid that best fits the onsets: **0.484 s + k × 0.7130 s**, i.e.
  **84.2 BPM**, matching the audible attacks to within ~20 ms across all 13.8 s
  (`rainbowFirstBeat` / `rainbowBeatPeriod`; **re-cutting the clip means re-measuring
  them**). Three things together buy the sync, and dropping any one loses it: **one hop
  per beat** (the crossing is `6 × 0.713` ≈ 4.28 s, close to the 4.7 s it used to take,
  so the pacing barely changed); **congruent hops under `.paced`**, which times the path
  by arc length and therefore gives each identical arc exactly a beat — this is why the
  per-unicorn ±15 % travel jitter had to go, it made every unicorn a different wrong
  tempo; and **departures snapped to the grid** (`rainbowBeatAligned`), because a
  unicorn lands every whole beat *after its own start*, so a start off the grid puts all
  six landings off by the same constant. All seven hang off one `clock0`, stamped in
  `showRainbow` next to the line that starts the sound.

- **💓 Heartbeat + 🐶 dog / 🐱 cat** (tile #13 `13_heartbeat.mp3`, `showHeartbeat`): the built-in
  Retina is captured and redrawn full-screen, then **bulged under the cursor** in a
  lub-dub keyframe, twice per cycle, with the lens **glued to the live mouse at 20 Hz**
  and the capture underneath it **retaken 4×/s** — the screen beats wherever the cursor
  is now, over a picture that is at most 250 ms old. See **the live refresh** below;
  until 2026-09-19 both were frozen at press time.
  Until 2026-08-27 the beat was a whole-screen `transform.scale` 1.0 → 1.30 → 1.0
  pivoted on the pointer, and that put the *largest* displacement where nobody is
  looking: a corner 1500 pt from the pivot swept ~450 pt per thump, so the periphery
  lurched while the thing under the cursor barely moved — dizzying rather than alive.
  It is now a **`CIBumpDistortion` in `imgLayer.filters`** (`HeartbeatBump`): a convex
  lens whose **diameter is three fifths of the screen height** (`diameterFraction` = 0.6,
  so r ≈ 335 pt on the Retina — a 670 pt disc). The size has been asked for four
  ways and the *units* moved each time, which is the part worth remembering: it began as
  "those 10% of the screen under the mouse", an **area** (πr² = fraction·W·H, ~248 pt);
  on 2026-08-27 Victor asked for it **twice as big — the size, not the amplitude**, and
  the size of a disc is how wide it reads, so the radius doubled and the area quadrupled
  to 40% / ~496 pt; on 2026-09-06 he pinned it outright as **half the screen height**;
  on 2026-09-09 he asked for **20% larger — again the size, not the amplitude**, so the
  diameter went 0.5 → 0.6 of the height (the area, which nobody was asked about, grows
  44%). The height anchor is strictly better and is why the area formula is gone: a share of
  the *area* is a share of W·H, so the same lens grew and shrank with the aspect ratio
  of whatever display it landed on, where a share of the height reads identically on the
  retina, the projector and the wide external. `HeartbeatDogFollow` reads `radius(in:)` for what the dog must
  stand clear of, so the two sizes cannot drift apart. `inputScale`
  is unchanged at 0 → 0.5 → 0 across all three resizings — it is relative to the radius,
  so a lens of another size bulges by the same factor over that distance, bigger or
  smaller but never punchier — driven by a keyframe animation on the
  `filters.bump.inputScale` key path — which is why the filter is installed with a
  `name`. Outside its radius the filter is the **identity**, so the periphery is not
  merely moved less, it is not moved at all; what is left of the old zoom is a 2%
  `breatheScale` pivoted at the *centre* (~17 pt of corner travel, versus 270), on the
  same `beginTime` so the two halves cannot drift apart. Measured on screen, not
  assumed: CoreAnimation resolves filter coordinates in **layer points and compensates
  for `contentsScale`**, so the same numbers land identically on a 1x and a 2x display.
  Past `inputScale` ≈ 0.7 the middle of the lens stretches into a fisheye smear. **Driven from the
  routed `/sound/play` path** (`onSoundPlay`), like the radar and the microwave, and
  therefore **out of `SoundEffectMap`** so the press cannot fire it a second time. That
  is what makes it land: the visual used to come off the press while a *separate* HTTP
  request started the audio, and the pulse clock then started from whenever the async
  `screencapture` happened to return — so every zoom sat a few hundred variable ms
  behind its thump. Sound and visual now share one origin, `clock0`, stamped the moment
  the clip is handed to `playTabletSound` (plus `btComp`, which is warm-up silence that
  really does delay the audio). The second half of the fix is **which part of the zoom
  lands on the beat**: the eye reads the *peak* as the hit, so a cycle begins `rise`
  seconds BEFORE its onset and tops out exactly on it — starting the rise on the onset,
  as it did, puts the peak half a pulse late and reads as lag even off a perfect clock.
  `heartbeat_beats.json` holds the **rising edges measured off the clip itself** (20 ms
  RMS envelope, `[lub, dub, lub, dub …]`, 9 pairs), and each pair is now played at its
  own onset instead of on an imposed uniform period. Each cycle's callback is armed
  `heartbeatArmLead` (60 ms) early and only hands CoreAnimation an animation whose
  `beginTime` is already the exact instant, so main-thread jitter never reaches the
  screen; deadlines are absolute and independent, so a beat whose moment has already
  passed is **skipped rather than fired late** — one missing thump is invisible, a whole
  timeline shifted behind the audio is the ugly part. A press **preempts** a running
  heartbeat (`cancelIfRunning`) rather than being swallowed: being swallowed would
  answer the tablet with "no sound" and send it back to local playback, and restarting
  is what `playTabletSound` does to the audio anyway. Since 2026-08-26 a **chihuahua rides on top of it** (`heartbeat-dog.png`,
  `makeHeartbeatDogLayer`), sized to **two thirds** of the aspect-fit of **half the
  screen** (`heartbeatDogScale` — filling that half outright made the dog the subject and
  the beating screen its backdrop, which is the wrong way round). That function decides
  the dog's *size* only; where it stands is settled entirely by the placement below,
  before the first frame is drawn. The asset is the source photo with its background
  flood-filled from the corners to **real alpha** (not a coloured box), so the pulsing
  capture shows through around the fur. **Which photo matters more than the fuzz value**:
  the first attempt cut the dog out of a white studio shot, and a chihuahua's pale ear
  fades into white so gradually that no single threshold separates the two — 10 % chewed
  notches out of the ear, and dropping to 2 % (which spared it) left behind the very
  background it was there to remove. The shot actually shipped sits on flat lavender
  (`#A3ABCF`), nowhere near cream fur, so **8 % is clean at the edges *and* nowhere near
  the ear**. It is **not mirrored**: this photo already faces the way the effect needs
  (muzzle pointing right, i.e. into the screen from the left half) — the flop the
  white-background version needed was a property of that framing, not a rule.
  The dog is a **sibling of the capture layer, not a child**: the pulse animation is
  added to the capture alone, so the screen bulges while the dog beside it stays undistorted.
  Both live inside a **container**, and it is the container that goes into
  `activeEffects` — one tracked unit, so `stopAllActiveEffects()` and `trackEffect`'s
  auto-cleanup tear the pair down together instead of leaving a dog behind. The
  container is also what the debounce and every re-entrancy guard compare against
  (`activeEffects["heartbeat"] === container`), including inside `scheduleHeartbeatPulses`,
  which still animates the capture layer but validates the container. The dog carries **no sound of its
  own** — the whole effect is scored by the one clip the same call started.

  **🐶 It keeps the beat company** (`watchHeartbeatDog` + the pure, unit-tested
  `HeartbeatDogFollow`). **This rule inverted on 2026-09-06 and the file was renamed**
  — until then it was `HeartbeatDogFlee` and the dog *bolted* to the half of the screen
  the cursor was not in. That joke stopped working once the projector is generally
  zoomed in around the beat: the far half is precisely the part of the screen the room
  cannot see, so the dog was reliably off-frame. Now it is glued to the beat, parked
  right up against the pulsing lens, facing the pointer, and it **moves along whenever
  the pointer does** — vertically too, which is the genuinely new half.

  **It stands 30 % inside the clearance** (`HeartbeatDogFollow.closeness` = 0.70, Victor,
  2026-09-10). Everything below still computes the strict "ear exactly on the circle"
  placement; `closeness` then multiplies that one distance (`want` = radius + margin), so
  the sideways gap and the sink-below-the-beat credit shrink together and the placement
  stays one consistent, if smaller, circle. The ear now **overlaps** the lens, which was
  the previous rule's one inviolable no: it is affordable because the lens is a
  *distortion*, not a drawn disc — its outer ring barely moves a pixel, so an ear a few
  tens of points inside the radius covers nothing the room was watching, while the strict
  placement read as a dog standing politely aside from the beat instead of leaning into
  it. Two knock-on effects: the emergency sidestep below is now unreachable even against
  the 435 pt stress lens (the seam case that used to spend past the budget no longer
  does), and the shortfall test in `facePoint` gained a hair of slack — the placement aims
  at exactly `want`, so an exact hit lands on that boundary and rounding alone used to
  decide whether the dog sank a whole ear for nothing.

  **The face, not the box, is what gets parked.** The placement is written around one
  point measured off the asset — `faceFracX` 0.60 / `faceFracYFromTop` 0.15 — and the
  clearance around another, `headSideFracX` 0.86, the ear tip, which is the outermost
  part of the head and therefore what actually has to sit on the circle (the muzzle
  stops around 0.72). Both come off the alpha channel at a 60/255 threshold, not
  eyeballed. The chest lower down is wider still (0.99) but sits ~400 pt below the face,
  where the lens circle has already curved away by more than the extra width — checked,
  it clears.

  **Height is decided before the horizontal, and it is pinned at the bottom.** The face
  rides at the cursor's own height, but the **bottom edge of the photo is never lifted
  off the floor of the screen** — it may go below, never above (Victor, 2026-09-06,
  `bottomAnchoredFaceY`). The photo is cropped at the chest, so a gap underneath turns a
  dog leaning into frame into a sticker floating in mid-air, which is the whole thing the
  bottom-aligned framing exists to avoid. So a beat low on the screen leaves most of the
  dog below the frame, and a beat high on it does not lift the dog at all.

  That last case is not the dog going passive, though — it is what lets it get *closer*.
  The clearance constraint is a circle, and standing below the beat already pays part of
  it, so the horizontal only has to make up the difference: pinned to the floor under a
  beat near the top of the screen, the dog slides in until it is almost directly
  underneath, looking up at it, instead of holding station off to one side. Only the drop
  **below the cursor** counts — while the ears are still above it the near edge runs
  through the cursor's own height and the horizontal gap has to carry the whole radius.
  (Getting that wrong is the one bug this had: crediting the sink as a delta on top of a
  `below` that was clamped at zero silently lost exactly one ear's worth of drop, and the
  stress sweep caught it.)

  **The ordinary placement is the sidestep**, on a budget: the dog's *back* may hang off
  the outer edge of the screen by up to `maxBackOverflow` = 25 % of the box, because a
  cropped rump is a cheaper failure than a face dragged away from the beat. If the frame
  eats even that, two fallbacks in order — **sink** further below the beat (free, the
  bottom edge is open; it stops only at `faceFloorFraction`, where the face itself would
  go out of sight), then **step sideways past the budget**, with the face staying inside
  the frame as the only hard stop. Covering the beat *wholesale* is still the failure
  worth paying to avoid — the dog is a **sibling** of the capture layer, so it never
  pulses, and a dog parked over the middle would just hide the one part of the screen the
  projector is zoomed into. Since the lens shrank to half the screen height, and more so
  since `closeness`, neither fallback is reached on the retina and the dog stays well
  inside its budget everywhere; the tests keep them honest by re-running the whole cursor
  sweep against the old 435 pt lens as a stress case.

  Mechanics worth knowing before touching it: the overlay panel is **click-through and
  receives no mouse events at all**, so the cursor is *polled* (`NSEvent.mouseLocation`,
  20 Hz) for exactly as long as the effect lives, and the timer cancels itself the moment
  this is no longer the active heartbeat, so a stop-all never leaves it running. Every
  move is a 160 ms eased slide of both x and y onto the computed placement.

  **The side is decided once and then kept** (Victor, 2026-09-09). The first poll asks
  `shouldBeOnRight` the way it always did — the half of the screen the cursor is in
  picks the roomier side, and the 4 % dead band decides a cursor sitting on the seam
  (`wasOnRight` is false there, so dead centre puts the dog on the left) — and that
  answer stands for the rest of the run. Re-deciding it on every poll is what used to
  send the dog **leaping over the beat** whenever the pointer crossed the midline, and
  on the projector that read as a glitch, not as a joke. The leap went with it:
  `HeartbeatDogFollow.apex` / `hopDuration`, the mirror at the apex and the cursor
  freeze that stopped a mid-flight re-aim are all gone, and `minStep` is the only
  motion rule left. What remains is the follow — the dog stays on the same side of the
  pointer and trots after it wherever it goes.

  **🐱 Every other run it is a cat instead** (Victor, 2026-09-11). `HeartbeatCompanion`
  alternates the beat's companion run to run — run 1 the dog, run 2 the cat, run 3 the
  dog — in memory only: the toggle is a `static var`, not a `UserDefaults` key, because a
  restart beginning again at the dog is the correct cold start, not a bug. It is **the one
  place the choice is made**; `showHeartbeat` asks once and wires up whichever it is told.

  The cat began (2026-09-11) as the dog's opposite: it **has no long neck**, so it did not
  follow anything — parked in the far bottom corner for the whole beat. That lasted until
  2026-09-14, when Victor asked for it to **translate the way the dog does** and to keep a
  **similar distance to the beat**. The file is now `HeartbeatCatFollow` and the cat polls
  the mouse on the dog's own timer (`watchHeartbeatCat`, 50 ms, 0.16 s eased slide,
  `HeartbeatDogFollow.minStep`). What is left of "no long neck": the cat never rides up to
  the cursor's height, it stays flat on the floor and only walks sideways. It is a
  **sibling** of the capture layer (so the lub-dub never bulges it, the dog's reason) and a
  sublayer of the tracked `heartbeat` container, which means the container's own self-stop
  is its self-stop too — and the timer stops itself as soon as that container is no longer
  the active heartbeat.

  - **Which side** — `onRight` gives the cat the half the mouse is *not* in, so it leans
    in from the roomy side rather than standing on the pointer. Read off the same `anchor`
    the first lens centre uses, i.e. the cursor as it was before the capture, so the cat is
    already in place before its first frame. On the beat's right the layer is **mirrored
    about its own centre** (`facing`). Decided **once** and then kept — `makeLayer` hands
    the side to the watcher rather than letting it ask again, because the mirror is baked
    into the layer: a mid-effect switch would be a cat flipping *and* teleporting across
    the beat in one frame, the dog's 2026-09-09 glitch exactly.
  - **How far from the beat** — the cat's near **top corner** stands on the dog's own
    circle: `nearGap` = `(lens radius + clearMargin) × closeness` = `(r + 18) × 0.7`, read
    off `HeartbeatDogFollow` rather than copied, so "a similar distance" stays similar
    instead of drifting. Under the lens radius on purpose — the corner leans *into* the
    ring, where a `CIBumpDistortion` barely moves a pixel. And the dog's trade comes with
    it: **standing below the beat already pays part of the clearance**, so a beat high on
    the screen lets the cat walk in almost directly underneath it, while a beat down near
    the floor pushes it out to the full gap. Where the two part company is the failure
    case — the dog may hang its rump off the screen rather than give up the distance, the
    cat may not: **the frame wins**, and a beat close to the cat's own edge simply parks it
    flush in the corner it used to live in.
  - **How big** — aspect-fit inside **half the width by half the height (a quarter of the
    screen's area)**, then taken down by `scale` = **1.05**. The unscaled fit put a cat
    690 pt wide in the corner and it read as the subject rather than as company for the
    beat — `heartbeatDogScale`'s lesson, learned again one corner over. It spent a few
    minutes at **1.4** on 2026-09-14 ("de două ori mai mare") and came straight back ("și
    să fie totuși 2x mai mică"): at 1.4 the cat is 1098 pt wide on the built-in panel and
    cannot both stay on screen and stay off the lens. **The follow is what the size was
    really buying** — a cat that walks over to the beat does not need to be huge to be near
    it. **1.5× on 2026-09-19** ("make the cat one point five X larger") took 0.7 → **1.05**,
    deliberately stopping half way to the 1.4 that was rejected — and what makes the extra
    size affordable is the live refresh below: the screen under the cat keeps moving now, so
    a bigger silhouette no longer covers a frozen picture. The asset's 1.40 aspect is
    squarer than the box on any wide screen, so **height** is what binds: on the 1728 × 1117
    built-in panel the cat measures **824 × 587** (logged on every run with its starting x),
    and on the 1512 × 982 the heartbeat tests use as their fixture, ≈ 724 × 516.
  - **How low** — sunk by `sinkFraction` = **9 % of its own height** below the floor of
    the screen, and never anything else: the beat's height moves the cat sideways, never
    up. The GIF's tail sweeps the bottom of its own frame, and a cat sitting exactly on the
    edge reads as a sticker laid on the desktop; letting the tail run off the edge puts it
    *in* the room. **The clipping is the effect**, not a placement to clamp back up — the
    opposite of the dog's hard "bottom edge never lifted off the floor" rule, which exists
    because the dog's photo is cropped at the chest.

  The chosen side and the resulting frame are logged on every run, so a screenshot is
  never needed to tell which side it took or how far in it tucked.

  **The asset is `scared_cat.gif` in `EffectsConfig.assetsDir`** — a downloaded GIF, so it
  is *not in this repo*, same rule as `brother_full.gif`. Drop it there or the cat's turn
  quietly becomes the dog's, with one `info` line naming the directory. It is stored
  **pre-cropped**: the download was a 500 × 500 canvas whose subject occupies only
  486 × 346, and the empty margin is not free — aspect-fitting the untrimmed canvas would
  shrink the cat by a third and float it above the corner it is supposed to sit in. The
  crop is the union alpha bounding box over all 30 frames (`magick … -coalesce -crop
  486x346+5+96 +repage -dispose Background -layers OptimizeTransparency`), done once
  offline rather than at load time. Frames are decoded once and cached by file
  modification date, so replacing the GIF is picked up without a rebuild.

  **The live refresh** (`watchHeartbeatScreen`, 2026-09-19). Until then the effect froze
  two things at press time and it showed: the lens was re-centred once per lub-dub pair,
  at the moment that pair was *armed*, and the screenshot under it was taken once and
  never again. Moving the mouse mid-beat therefore left the bulge sitting where the
  pointer had been ("even if I move my mouse, the bump stays on the same place"),
  magnifying a picture of a screen that had since moved on. One timer now fixes both, on
  **two deliberately different clocks**:

  - **The lens, every 50 ms** (`heartbeatDogPollInterval`, the companions' own poll).
    Moving a `CIBumpDistortion`'s centre is a filter parameter, not a redraw of anything,
    so there is no reason to make the magnifier lag the hand. Set with actions disabled —
    the bump *is* the pointer's mark on the screen, and a lens easing in behind the mouse
    reads as lag rather than as weight. Safe mid-swell: `inputCenter` and the animated
    `inputScale` are different key paths on the same filter.
  - **The picture, every 250 ms** (`heartbeatRecaptureInterval`) — the 4 fps that was
    asked for. Not a frame rate anybody watches; it is the rate at which the content
    stops being stale, and a full-screen capture is the expensive half. One capture is in
    flight at a time and a tick that finds the previous one still running skips its turn
    rather than queueing behind it.

  **A refresh capture has to exclude our own overlay**, and that is the whole reason it is
  not `captureBuiltInDisplay()` on a timer. By then the overlay is showing the *previous*
  capture, so a plain screenshot would photograph the effect's own output — a bumped
  screen inside a bumped screen, one level deeper every 250 ms. `screencapture(1)`, which
  the **first** capture still uses (at that instant the overlay is empty, so there is
  nothing to leave out), cannot exclude a window. `CGWindowListCreateImage` could, via
  `.optionOnScreenBelowWindow`, and was the obvious answer right up until **macOS 15
  obsoleted it** — it is a compile error now, not a warning. What replaced it is
  **ScreenCaptureKit**: `SCContentFilter(display:excludingWindows:)` over the
  `OverlayPanel`'s window id, cached for the process because that filter is *live* —
  built once, it keeps excluding our panel while still picking up every window that opens
  afterwards. `captureScreenExcludingOverlay` answers **nil rather than a fallback
  screenshot** on macOS 13, without Screen Recording permission, or when our panel is
  missing from the window list: "cannot exclude the overlay" has to mean "do not
  capture", and the caller keeping the frame it has is exactly the pre-2026-09-19
  behaviour. Every failure mode degrades to "the screenshot is frozen again".

  **The pointer is hidden for the whole beat** ("the mouse should not be visible during
  this animation"). It is a consequence of the follow, not just taste: an arrow parked on
  top of the bulge it is itself causing looks like the arrow is what got magnified. The
  hide uses the same `SetsCursorInBackground` arm as 😱 fear (our overlay is never the
  frontmost app, so `CGDisplayHideCursor` alone would do nothing), and
  `cfg.showsCursor = false` keeps one out of the captures too. Because
  `NSCursor.hide()/unhide()` are **counted**, a double release would cancel somebody
  else's hide — so the hide is a `HeartbeatCursorHide` box that can be opened once, by
  whichever of the three teardowns gets there first: the follow timer noticing the effect
  is over, the capture completion finding itself preempted, or an absolute backstop at
  `totalDuration + 1 s` for the run where the capture never returns and no timer is ever
  armed.

- **🔍 Magnifier** (tile #6 `06_copyright_cartoon.mp3` → `magnifier`,
  `showMagnifier`, geometry and artwork in `MagnifierGlass.swift`): the tile is the
  **Pink Panther** theme and its artwork is Inspector Clouseau stooped over a
  magnifying glass, so the desktop gets the glass. It rides the pointer for the
  length of the clip (~37.8 s, measured off the mp3; `magnifierFallbackDuration`
  when the audio is not on this machine) and magnifies **only what is inside its
  lens** — everything outside the rim is the untouched desktop, not a less-zoomed
  one. That is the whole difference from the 💓 heartbeat, whose
  `CIBumpDistortion` bulges the screen itself; this lens is a flat **2×…6×**
  (`MagnifierGlass.zoom`, which is also `minZoom` — the wheel, below), the same
  factor everywhere inside the glass, the way looking through a real one works.
  **Size: the lens is two thirds of the screen height** — 745 pt on the retina,
  so the glass shows a ~372 pt square of desktop, a good handful of lines of
  code. It was born a third (Victor, 2026-09-22: *"cam la o treime din înălțimea
  ecranului"*) and **doubled the same day** (*"trebuie să fie de două ori mai
  mare"*): from the back of the room a third of the height is a prop you notice,
  not a lens you can read through. Doubled as the **diameter**, not the area —
  "twice as big" about something on a screen is how wide it looks, and doubling
  the area would have grown it by 1.41, visibly short of the ask. The **zoom
  stayed at 2×** on purpose: a bigger lens was asked for, not a closer one, and
  raising both would have shown the same few pixels twice as coarsely.
  A fraction of the **height** and not of the area, for `HeartbeatBump`'s reason:
  a share of `W · H` grows and shrinks with the aspect ratio of whatever display
  it lands on. Every other number in the prop is a fraction of that one diameter,
  so resizing the lens moved the rim, the collar, the handle and the glare
  together — the doubling is one constant, `MagnifierGlass.diameterFraction`.
  At this size the drawn canvas (~1300 pt square, since the handle leaves at 45°)
  is taller than the screen, so with the pointer low and to the right the handle
  runs off the edge. That is the prop behaving like a prop and nothing clips it:
  the container is unmasked, only the window bounds cut it off.
  **The glass is drawn, not photographed** — a `CGImage` built at the overlay
  screen's backing scale: chrome rim with a black cartoon outline inside and out,
  a metal collar, a tapered wooden handle hanging down-right at 45° (the way the
  inspector holds it on the tile), and one diagonal glare streak at 16 % white.
  Two things about the drawing are load-bearing. The middle is **transparent** —
  it is the hole the magnified desktop shows through, so anything filled in there
  hides the effect behind its own prop (`testTheMiddleOfTheLensIsTransparent`) —
  and the handle is drawn **clipped out of the glass disc**: it is tucked a few
  points under the rim so no seam shows, which puts its square shoulder across
  the inner circle, where it read as a dark sliver floating inside the lens.
  **Three layers:** a round clip layer (`cornerRadius` = the glass radius,
  `masksToBounds`) holding the screenshot scaled 2× and slid until the pointer's
  spot sits dead centre (`MagnifierGlass.shotFrame` — the one piece of arithmetic
  that is easy to get backwards, so it is pinned by a test at four corners of the
  screen); the drawn glass above it, hung off its own lens centre via
  `anchorPoint` (`lensAnchor`), so **one position drives both** and the entrance
  scales about the glass rather than about the far end of the handle; and a
  container so one `stop-all` takes the pair away.
  **Two clocks, the heartbeat's pair and for its reasons.** The glass is put back
  on the pointer at **20 Hz** — the overlay is click-through and receives no
  mouse events at all, so `NSEvent.mouseLocation` is polled — instantly, with
  `setDisableActions`, because a magnifier easing in behind the hand reads as lag.
  The picture *under* it is retaken at **4 fps** through
  `captureScreenExcludingOverlay`, which must exclude our own panel or the lens
  photographs its own output, one level deeper every 250 ms. Captures never
  overlap and a nil answer leaves the current frame alone, so every failure
  degrades to "the view is frozen", never to an empty lens. The **first** capture
  is the plain `screencapture(1)` one, taken while the overlay is still empty —
  and the container is only added to the host layer once it comes back, so the
  glass never appears over a hole. It is tracked before that, as the debounce
  placeholder a re-press preempts.
  **A click puts it away, the wheel zooms inside it** (2026-09-22). Both
  gestures are *taken away* from the app underneath by one `CGEventTap`
  (`startMagnifierInputCapture`) — the same bargain as the 🔥 fire's tap and for
  the same reason: the overlay panel is click-through, so without a tap the
  click that was meant to dismiss the prop presses a button behind the lens, and
  the notch that was meant to zoom scrolls Victor's editor out from under the
  very thing he is pointing at. A global `NSEvent` monitor can only watch that
  happen; a tap can consume. The click's `up` is swallowed with its `down` —
  delivering the up alone hands the app below half a click.
  The click puts away **the glass and the music together** (Victor, 2026-09-23 —
  it used to leave the Pink Panther playing, and a theme with no inspector on
  screen is a joke without its prop). `SoundManager.stopWherever` with the
  magnifier's own file, so it fades whichever player holds it — the tablet's
  routed one or this Mac's pool — and never an unrelated tile.
  **The wheel's floor is the glass the room already knows** (Victor: *"zoomul
  merge însă între limite (minim cât e acum)"*) — `minZoom == zoom`, so scrolling
  down can only bring the lens back to how it dropped onto the pointer, never to
  a pane of plain glass that magnifies nothing. The ceiling is **6×**: a 124 pt
  square of desktop, three or four lines of code, and still crisp because the
  capture comes off a retina at 2 device pixels per point, so 6 point-times is
  only 3 native-times. One notch is a **factor** (`zoomStep` 1.15, the whole
  range about eight notches apart), not an addend — a dial that adds a constant
  feels coarse at the bottom of its range and sluggish at the top. The trackpad's
  continuous pixels are accumulated into notch-sized steps so a two-finger flick
  doesn't cross the range in one gesture. ⌘-scroll is passed through untouched:
  `EventTapManager` turns it into terminal font zoom, and eating that for 38 s
  would look like the shortcut had broken.
  The wheel **only writes the number**; the 20 Hz follow tick is what paints it,
  out of the same `shotFrame` call that keeps the lens on the pointer. One writer
  for `shot.frame` — a second path that also set the frame would have to
  re-derive the pointer, and the two would disagree for a frame on every notch.
  The tap is armed *with* the effect, before the first capture (a click during
  those couple of hundred ms means "not this one" just as much as a click a
  second later does), and disarmed by **whichever teardown gets there first**:
  `stopMagnifier`, the follow timer noticing the glass is gone (within one tick,
  and not when a re-press has already armed a tap of its own), or the capture
  completion finding itself preempted with nothing to replace it. A flag the tap
  thread reads (`_magnifierIsLive`) is the belt for the event already in flight —
  `activeEffects` is a dictionary mutated on main and has no business being read
  from a tap callback.
  It **self-terminates at the clip's length** (lifecycle rule) with a 0.4 s
  lift-off timed from the press, not from the capture; `/effect/magnifier/stop`
  (the tablet's `/sound/stopped`) is the polite exit and fades the same way.
- **🚪 FBI knock** (tile #64 `64_fbi.mp3`, `showFbiKnock`): the built-in Retina is
  captured and redrawn full-screen, then **shoved 7% larger on each of the three door
  bangs** before the FBI starts shouting; the capture holds for the rest of the clip and
  fades out with it. The whole effect is that sync, and until 2026-09-09 it had none:

  - **The onsets were stale.** The knock times were hardcoded at 0.406 / 0.615 / 0.813 s.
    Re-measured off the clip (22 kHz, low-band envelope in 10 ms windows) the bangs attack
    at **0.022 / 0.227 / 0.430** — the *same three bangs at the same 0.205 s spacing, plus
    a constant 0.383 s*. That constant is the leading silence the clip was re-cut without;
    the numbers never followed it, so every lurch landed a third of a second late.
    `fbiKnockOnsets` now says so in one place: **re-cutting the clip means re-measuring it.**
  - **Sound and visual had no common clock.** It was a press→`SoundEffectMap` visual while
    a *separate* HTTP request started the audio, and the knock clock started from whenever
    the async `screencapture` returned. Same disease the heartbeat, the microwave and the
    radar were each cured of, and the same cure: **driven from the routed `/sound/play`
    path** (`onSoundPlay`) and therefore **out of `SoundEffectMap`**, so one call owns both
    halves and they hang off one `clock0` (plus `btComp`, the Bluetooth warm-up silence
    that really does delay the audio).
  - **The audio waits for the capture** — the one thing this effect does that the heartbeat
    does not. The first bang is **22 ms** into the clip, sooner than any capture can return,
    so starting the sound at press time would spend that bang on an empty overlay no matter
    how good the clock was. `showFbiKnock` therefore tracks a contents-less (invisible)
    layer immediately — so a second tap is debounced and a stop-all still reaches it — and
    plays the clip in the capture's completion. It answers the tablet with the clip length
    up front; the tracked life adds `fbiCaptureAllowance` (0.9 s) to cover the slide.
  - **The peak lands on the bang**, not the start of the rise (the heartbeat's lesson), and
    all three bangs are **one keyframe animation with an absolute `beginTime`** rather than
    three `asyncAfter` + `CATransaction` pairs — which put main-thread jitter straight on
    screen. Rise is eased-out and clamped per knock so it can never start before the clip
    does (the first one snaps in 22 ms); fall is eased-in over 130 ms.

  The overlay's life also stopped overrunning the audio: it was pinned at 3.3 s against a
  1.95 s clip, so the desktop sat frozen under a silent screenshot for 1.35 s. It now
  reads the clip's real length and fades out on its last 0.3 s.

- **🚪 Dark door** (tile #25 `25_dark_door.mp3` → `dark-door`, `showDarkDoor`): the built-in
  Retina is captured and then **punched IN on each of the seven knocks**, each punch holding
  its new level until the next one takes it further — 1.09× compounding seven times to
  **1.83×** — then holding under the door's decay and fading out on the clip's last 0.3 s.
  This is the difference from the FBI knock next door, which *shoves* the screen 7 % and
  lets it straight back on every bang: here the knocks **accumulate**, so the desktop is
  walked in on rather than rattled, which is what "zoom it in FBI-style" actually means.
  Each punch overshoots its new level by 3 % and settles onto it over 85 ms — without the
  overshoot seven compounding steps read as one smooth ramp instead of seven separate hits —
  and, as everywhere else here, **the peak lands on the knock**, not the start of the rise.
  - **Until 2026-09-11 this tile did nothing at all.** `25_dark_door.mp3` was mentioned
    **nowhere** in the app: not in `SoundEffectMap`, not in `onSoundPlay`, not in the effect
    switch. The tile played its clip over an untouched desktop, which is exactly what it
    looked like.
  - **The onsets were measured, not guessed**, the same way the FBI knock's were: decode to
    mono 22 kHz, one-pole 500 Hz low-pass (a knock is a low thump; the door's rattle sits
    above it), RMS envelope in **2 ms** windows, then walk *back* from each peak to where the
    envelope first exceeds **8 % of that peak** — that edge is the attack. Run against
    `64_fbi.mp3` the same procedure reproduces its committed 0.022 / 0.227 to the
    millisecond, which is the only reason these are trusted. They are
    **0.024 / 0.224 / 0.416 / 0.596 / 0.784 / 0.964 / 1.160** — metronomic, 0.18…0.20 s
    apart, in a 1.477 s clip that is silent past ~1.35 s. `darkDoorKnockOnsets` carries the
    method in its doc comment: **re-cutting the clip means re-measuring it.**
  - **It owns its audio and the audio waits for the capture** — the FBI knock's bargain, for
    the FBI knock's reason: the first knock is **24 ms** in, sooner than any `screencapture`
    can return, so starting the sound at press time would spend it on an empty overlay. It is
    therefore driven from the routed **`/sound/play`** path and deliberately **absent from
    `SoundEffectMap`** (the press path would double-trigger it). A contents-less layer is
    tracked up front so a second tap debounces and a `stop-all` still reaches it;
    `darkDoorCaptureAllowance` (0.9 s) covers the slide.
  - **It needs Screen Recording.** Without the grant `screencapture` returns the wallpaper or
    nothing, the punch-ins have nothing to punch, and the clip plays over a live desktop —
    indistinguishable from the old do-nothing behaviour. The failure is logged rather than
    silent (`🚪 dark door: screen capture failed…`), because that is the one thing about this
    effect nobody can tell by looking.

- **🎼 Beethoven's Fifth** (tile #51 `51_beethoven.mp3`, `showBeethoven`): the Retina is
  captured and then **lunges at the room three times on the three eighth notes**, each
  lunge bigger than the last and each giving a little of it back before the next, then
  unwinds to its own size on the long note they fall onto — and the whole shape repeats
  on the clip's second phrase. That is the ask literally (Victor, 2026-09-09: *de 3 ori
  din ce în ce mai mare și dând puțin de înapoi de fiecare dată … și se revine*), and
  the music is what it is written against:

  - **The phrases are measured, not counted off a score** (`beethovenPhrases`): mono
    16 kHz, log-envelope flux in 5 ms windows gives **0.305 / 0.410 / 0.520 → 0.650** and
    **3.240 / 3.375 / 3.495 → 3.610**. The eighths are ~0.11 s apart, *faster than the
    concert tempo*, because this is a sound effect and not the symphony — which is
    exactly why counting them off the score would have missed. **Re-cutting the clip
    means re-measuring them.**
  - **The peaks escalate, the retreat is proportional.** `beethovenZoomPeaks` = 1.06 /
    1.13 / 1.22 (1.22 pushes the edges ~190 pt off a 1728 pt-wide frame — a lunge, well
    past the FBI knock's 1.07 shove, because here the zoom *is* the joke). The pull-back
    is `beethovenPullBack` = 45 % **of what that note just gained**, not a fixed scale: a
    fixed one would be a twitch under the first note and a collapse under the third.
  - **The gap is 0.11 s and everything has to fit in it.** 0.06 s of rise leaves 0.05 s
    of retreat; the **peak lands ON the onset** (the heartbeat's lesson), so the rise
    starts `beethovenRise` before it. The third note keeps its peak into the long note
    and unwinds over `beethovenRelease` = 0.45 s — slow next to the punches, because the
    three hits are the motif and this is the fermata under them.
  - **One keyframe animation for all six hits**, on an absolute `beginTime`. Six
    `asyncAfter` callbacks 0.11 s apart would put main-thread jitter straight on screen.
    `at()` skips any keyframe that would go backwards in time, so re-tuning the
    constants can't quietly produce an animation CoreAnimation refuses to run.
  - **Driven from the routed `/sound/play` path** (`onSoundPlay`), out of
    `SoundEffectMap`, and **the audio waits for the capture** — the FBI knock's bargain,
    for the FBI knock's reason: the first hit is 0.305 s in, close enough to a
    `screencapture` round trip that starting the sound first would spend it on an empty
    overlay. The capture then simply sits at scale 1 for the clip's last two seconds,
    which costs nothing: at scale 1 it is pixel-identical to the desktop under it.

- **☢️ Nuke bombardment — the clip, read frame by frame.** Everything below hangs off one
  measurement of `03_explosion.mp3` (3.28 s), so it is worth stating once. The clip is a
  falling-bomb **whistle** followed by the **blast**. The whistle is a clean descending
  tone — 2.80 kHz at 0.50 s down to 2.13 kHz at 1.50 s, narrowband (spectral peak/mean
  30–50×) — and it **stops dead at 1.52 s**, where the sub-400 Hz energy jumps ~20× in
  two 25 ms frames. That step is the explosion; its loudest *sample* is much later, ~2.20 s.
  Two constants come straight off that reading:
  - `explosionBlastOnset` **1.52 s** — where a fireball's first frame belongs.
  - `explosionWhistleForeground` **0.75 s** — the biggest single step in the whistle's
    envelope (1–6 kHz RMS 2.2 → 3.3, +50 %), i.e. the “here it comes”.

  Until 2026-09-02 the full-screen nuke landed on the **peak** (2.10 s in the old code),
  which is why Victor reported it as out of sync: by the time the crescendo peaks the ear
  has been hearing the explosion for two thirds of a second and the picture is visibly
  late. **The eye matches onsets**, so the fireball now starts at `explosionBlastOnset`.

- **☢️ The bomb that falls into it** (`spawnFallingBomb`, `bombFallSpeed`,
  `falling-bomb.png`): a bomb sprite drops from off-screen and its **nose** arrives on the
  impact point at the instant the fireball starts.
  - **One speed for the whole raid.** `bombFallSpeed` is *derived*, never tuned: the big
    bomb has to cross the top edge on `explosionWhistleForeground` and land on
    `explosionBlastOnset`, and those two instants plus the screen fix the speed for every
    bomb in the run. The asymmetry Victor asked for falls out for free — at one fixed
    speed a target high on the screen has less screen to fall through, so **its bomb
    enters later** than one aimed near the dock.
  - **No clipping, no visibility scheduling.** A bomb is simply spawned `speed × fall`
    points above its target, which for anything but a target on the bottom edge is off the
    top of the screen, and the overlay window does not draw what is above it. One linear
    `position.y` animation, run by the window server, is the whole fall.
  - **The nose is the anchor.** The png is trimmed to its opaque box (116×255) and the
    layer's `anchorPoint` is its tip — bottom edge, 52.2 % across, slightly right of
    centre and worth honouring — so `position` *is* the point being bombed and the fall is
    a straight line between two impact points rather than two centres.
  - **Size is a fraction of its own blast** (`fallingBombHeightPerBlast`, 0.11), so “big
    bomb for the full-screen explosion, proportionally smaller for the aimed ones” is one
    number and the two can never drift apart — **except** the full-screen one, which
    `fullScreenBombShrink` (0.5) holds deliberately *below* proportional. Strict
    proportionality is the wrong law at that end: the full-screen blast is ≈2.67× wider
    than an aimed one, so a bomb scaled straight off it fills a quarter of the screen
    height for the whole fall and reads as an object being *lowered* rather than one
    arriving from very far away. `fallingBombHeight(forBlast:fullScreen:)` is the single
    place either size is computed.
  - `bombBlastFrame` / `bombBlastImpactPoint` exist so the bomb aims at the very pixel the
    fireball will cover. Deriving that point from a second copy of the arithmetic is
    exactly how the two drift.

- **☢️ Aiming is opt-in, and the screen announces the deadline.** `bombAutoDropDelay` is
  `explosionWhistleForeground`, i.e. **the instant the big bomb clears the top edge**:
  once you can see it falling it is too late to aim, and no one has to be told the rule.
  A press left alone therefore always ends in the full-screen nuke, which also means every
  run owns at least one bomb and ends the same way, through `finishBomb`, rather than
  through an idle timer.
  Since 2026-09-09 the deadline is **enforced, not just announced**: `dropFullScreenBomb`
  raises `_bombBigDropped` and `plantBombAtCursor` bails on it, so once the big bomb is in
  the air no more little ones can be planted under it. Clicks are still *consumed* by the
  tap — the app underneath must never get them — they simply stop making targets. Before
  this, clicking during the fall added aimed strikes that landed after the nuke, tacked
  onto the end of a raid that had visibly already peaked.

- **☢️ The pointer stays the pointer.** The run no longer hides the cursor or rides a grey
  crosshair on it (the old startBombTargeting / revealBombReticle / restoreBombCursor trio is
  gone). A **click makes the target**, red and armed from its first frame
  (`makeBombReticleLayer(armed: true)`), and the arrow goes on moving over it. The old
  hand-the-crosshair-over dance existed to make the click seamless; with nothing under the
  mouse to hand over there is no seam to hide.

- **☢️ Every target stands until its own bomb lands** (2026-09-14, undoing the
  one-crosshair rule of 2026-09-09 — `retirePlantedReticles` is gone, and with it the call
  at the top of `plantBombAtCursor`). For five days a click took down every crosshair still
  burning and planted the one that replaced it, on the reading that a rhythm of clicks
  papered the desktop with red rings the eye could no longer sort. The reading was wrong
  about what the rings are for: **the pile IS the raid.** A chain of clicks is someone
  marking four places and then watching four bombs come down on them in turn, and a mark
  that vanishes the instant the next one is made marks nothing — the room loses which
  points are still coming, and the one ring that mattered, the one under the bomb visibly
  falling, is the first to go. It also cost the pop-and-fade, the single frame that ties a
  blast to the ring it grew under (it was skipped whenever a target had been retired).
  Each reticle now burns its own 1.10 s fuse, grows and turns for the length of it, and is
  popped by its own strike (`strikeFadeReticle`). The `reticle.superlayer != nil` check
  stays for the one case left: `stopBombSession` tore the layer down while the strike was
  still pending.

- **☢️ One boom per bomb** (sfx #03 `03_explosion.mp3` → `explosion`,
  `showExplosionGif` / `plantBombAtCursor`): every click plants a target that grows and
  turns for a `explosionStrikeDelay` (1.10 s) fuse while its own bomb whistles down onto
  it, so a rhythm of clicks comes back as a rhythm of explosions. Until 2026-08-30 it came back as a rhythm of
  *silent* explosions: the audio was **one clip at the head of the run** — the tablet's, on
  the routed path — and bombs two, three and four landed with nothing under them.
  Each plant now lays **its own boom** (`playBombBoom`), and the three numbers that keep a
  stack of them from turning into noise are all derived, not tuned by ear:
  - **Sync.** The clip's blast starts at `explosionBlastOnset` (1.52 s) and a fireball is
    `explosionStrikeDelay` after its click, so the copy is **seeked to the difference**
    (`bombBoomLead`, 0.42 s) and its blast arrives with the bomb rather than a beat behind
    it. A third job falls out for free: the copy's first 1.10 s are the *tail of the
    whistle*, so every aimed bomb whistles down for exactly as long as it is falling.
  - **The head clip belongs to the nuke, and the first click takes it away** (2026-09-17,
    Victor: *"când pun o singură bombă cu mouse-ul click … parcă se aude sunetul de două ori
    picând"*). The clip started at the press is the **full-screen bomb's** sound — its blast
    at `explosionBlastOnset` is what `bombAutoDropDelay` and the big bomb's fall are derived
    from, and nothing else is timed to it. A click cancels that bomb (`_bombPlantedAny`), so
    from that instant the head clip is scoring something that will never fall: its blast
    arrives with **nothing under it**, a beat away from the aimed bomb's own, and one bomb
    comes back as two explosions.
    So the first plant *hands the clip over*: `playBombBoom(takingOverFromHeadClip:)` cuts
    the head clip (`SoundManager.stopWherever`, a 0.12 s fade) and plays this bomb's copy at
    **full level with no swell** — it is not layering under anything any more, it IS the
    sound of the raid. The whistle stays continuous across the cut: the head clip is at most
    `bombAutoDropDelay` (0.75 s) in, the copy resumes at `bombBoomLead` (0.42 s), both well
    inside the same descending whistle.
    **Why not duck it by arithmetic**, as it was until now? `bombBoomLead` is also how late
    a target can be planted and still explode on the head blast, so a bomb clicked inside the
    first 0.42 s was simply given no copy — true, but it only covers clicks that early, while
    aiming stays open to 0.75 s. Every click in the 0.33 s between them produced the double.
    The gap is not a tuning accident either: one number is the instant the big bomb clears
    the top edge, the other is a property of the clip, and nothing keeps them equal —
    `testHeadClipCannotScoreEveryBombTheAimingWindowAllows` is that argument as an assertion.
    The handover does not depend on either.
    `stopWherever` exists because the animation cannot know **which player** holds the head
    clip: on the routed path the tablet started it (`showExplosionGif(playSound: false)`),
    on a local trigger this Mac did. It silences the named file in both pools, and touches
    the tablet player only when it is really playing that file — it holds whatever tile was
    pressed last.
  - **Loudness.** A copy swells from silence over the whole fuse (`fadeIn:` on
    `playOverlapping`) instead of banging in at full level, at `bombBoomVolume` (0.75)
    thinned by **1/√n** over the bombs still in the air, floored at `bombBoomVolumeFloor`
    (0.35). The equal-power law is the point: two booms a beat apart land at roughly the
    loudness of one, not twice it — the room hears more explosions, not more volume.

  The copies are **not Bluetooth-compensated** (`bluetoothCompensated: false`), for the
  same reason as the 🔥 whip crack but arrived at differently: the head clip has been
  sounding since the press, so the A2DP link is warm, and adding the start delay would push
  the blast late off the fireball it exists to land on.


- **🔁 Sketch arrow** (sfx #71 `71_one_more_time.mp3` → `sketch-arrow`,
  `SketchArrow.swift`): tile #71's own artwork — a ring open at the top with a
  big open chevron at its head — **drawn live** across the middle of the desktop
  in cyan, as if somebody were sketching it with a marker, then held for the clip
  and dissolved.
  **Procedural, not a picture.** The glyph is `CAShapeLayer`s whose `strokeEnd`
  runs 0 → 1; a PNG could be shown but not *drawn*, and would have to be re-cut
  for every display size. The geometry was measured off the tile's jpg (threshold
  the black, fit the annulus: centre-line radius R, stroke 0.247 R) and is stored
  **normalised to R = 1** — which is why one set of numbers covers every screen.
  The ring runs from the free tail at **47°** (≈ 1:30) the long way round through
  the bottom to **113°** (≈ 11:00): a **clockwise 294° sweep** with the gap at the
  top, and the head therefore points up and to the right along that tangent. The
  arrowhead is two long barbs meeting at ≈ 91° on a point just outside the ring
  (r ≈ 1.10) — an open chevron, the way the artwork draws it, not a filled
  triangle.
  **The sketch is three passes**, each over the same ideal geometry with its own
  smooth wobble (`Wobble`: three sine waves on a seeded phase, weighted 6:3:1 so
  the line has one lazy swing with smaller ones riding it, and **scaled by each
  stroke's own length** — the noise runs on t ∈ 0…1, so without that a barb a
  sixth of the ring's length got the ring's whole swing count crammed into a
  sixth of the distance and rendered as a string of sausages), its own width
  (1.00 / 0.58 / 0.36 of the stroke), alpha (0.92 / 0.55 / 0.40) and speed
  (1.00 / 0.90 / 1.10) — a felt-tip goes over a line twice and never lands on it
  twice. Each pass sweeps the ring (**1.35 s**, eased at both ends: a hand does
  not start or stop a 294° curve at speed), then flicks the two barbs **from the
  apex outwards** (0.32 s each, 0.18 s apart), the second starting 0.12 s before
  the ring lands so the head reads as the same gesture rather than a second
  drawing. Pen-up is at **`drawDuration` ≈ 2.04 s** — the *last* pass's, not the
  first's.
  **Then it boils.** Every stroke cycles between three wobble variants at 8 fps
  (a discrete `path` keyframe animation), the trick hand-drawn animation uses to
  keep an inked line alive; without it a 13 s hold is thirteen seconds of a frozen
  decal. The boil begins only at pen-up — a line still being drawn must not
  squirm. The wobble is seeded and pure, so the variants are a *fixed* set and
  the line breathes instead of shimmering.
  **Size and placement.** The glyph's own box (ring + the barb flung out left +
  the point) is **0.75 of the screen height**, centred as a box — centring the
  *ring* would hang the drawing right of the middle, because the long barb sticks
  out on the left. The box is **derived from the geometry, not typed**: it was
  four hand-measured numbers until a screenshot of the real overlay was measured
  against the screen and came back 0.756 of the height with the ink 5 pt above
  centre, the box being 0.017 R short at the top.
  Vertically it then drops by **half the menu bar's height** (`visibleDrop`).
  Dead centre of the *panel* is not the middle of the screen you can *see*: on
  that same screenshot a frame-centred glyph left **94 pt of desktop above it and
  141 below**, which is what "it sits too high" was. Only the menu bar counts —
  `visibleFrame` also moves with the Dock, and a drawing that jumped whenever the
  Dock unhid would be a worse bug than being 20 pt off while it is up.
  The whole container runs at **0.5 opacity**: it is an overlay on a desktop
  somebody is still working on, and at full strength a glyph this size stops
  being an annotation over the screen and becomes a screen of its own. The
  per-pass alphas are untouched underneath, so the three passes keep their
  relationship; the closing fade starts from that same 0.5, or the dissolve would
  open with the drawing jumping to full strength.

  **Lifetime.** It lives `SketchArrow.totalDuration` = **13.56 s**, the clip's
  length (`afinfo`), with the 0.8 s dissolve *inside* that window, so the layer
  `trackEffect` removes is already invisible when it goes — the self-termination
  rule with nothing owed to any client. Silent on this side: the clip plays down
  the ordinary routed `/sound/play` path, which is why #71 needs no special case
  in `playSound` and no `onStop` entry. `stop-all` clears it like any other
  tracked effect; re-firing redraws it (it is not a toggle).

## ☕ The coffee cups — the chimney, the pot, the explosions

Rewritten 2026-09-24 from Victor's dictated spec, after three earlier shapes
(a hold-to-charge pop, a lane that bent every cup over to the cursor, a
"storm" that swept them to the middle of the screen). Four rules, in the
order he gave them:

1. **The trajectory is the chimney, and nothing steers it.** A ☕ spawns at the
   bottom-left (x≈100±56, the same spawn as every reaction) and rises
   **straight up** like smoke, swaying gently side to side (`CoffeeFlight.chimney`,
   pure + tested: ±26–40 px, 1.5–2.5 swings over the climb, the sway ramping in
   over the first quarter so it leaves its spawn point cleanly), and **fades as
   it nears the top edge** (`CoffeeFlight.fadeStartFraction`, 68% of the way).
   Constant speed (190 pt/s, clamped 3.5–7 s) — slow on purpose, the pot needs
   time to reach a cup. **The mouse has no pull on it**: no attraction, no
   repulsion, no lane to the cursor — it can only *hold* a cup (rule 2). A test pins that the path never leaves
   ±amplitude of the spawn column and never comes back down.
2. **Intercept = pour, not explode.** `CoffeePourMonitor` ticks
   `EmojiAnimator.tickCoffeePour(cursorGlobalPoint:)` at **60 Hz** (`Timer` in
   `.common` mode, so a menu does not freeze it). While the cursor is inside a
   cup's box (presentation frame + 34 px slop) the real pointer is hidden and a
   **🫖** stands in for it, **252 pt** (84 → 168 → 252, all on 2026-09-24: at
   pointer size it read as a cursor, not a pot, and doubled was still a size
   short). **The cursor point IS the spout's tip** (`CoffeePot`, pure +
   tested): the tip is *measured* once from the glyph itself — the leftmost
   opaque pixel of the same `CATextLayer`, which sits in the UPPER left of the
   box (≈ −98, +37 from the centre) — and made the layer's `anchorPoint`, so the
   pot pivots around the cursor and no lean can pull the tip off the stream.
   (Until 2026-09-25 it was a hand-set offset of (+90, +54) that assumed the
   tip was lower-left; after the tilt the stream left the pot ~30 pt below and
   right of its tip, and every resize moved the error.) **The pot bends toward
   the cup**: while pouring it leans (counter-clockwise — the spout is on the
   left) until the spout points at the nearest touched cup's centre
   (`CoffeePot.aimTilt`, clamped 0.35–1.25 rad: a cup straight below, under
   the belly or behind the pot gets the full lean, never a pot on its lid),
   eased at 9/s so it swings rather than twitches; it arrives and straightens
   back to 0.2 rad in the grace after the hand slides off. A `CAEmitterLayer`
   of brown drops is born at the tip and **shot out along the spout** as it
   points that tick (`emissionLongitude` = spout angle + lean, 90 pt/s),
   then falls under gravity. The touched cup **freezes where it was caught and fills**
   (`freezeCoffeeCup`: the carrier's flight is stripped and its presentation
   position/scale pinned as model values, solid again even if it had started
   fading): 1.2 s of pouring takes `fill` 0→1, the glyph swells to **1.7×**
   under a warm brown glow and bounces once when full — and **keeps growing at
   the same rate for as long as the pot stays on it**, up to **4×**
   (`coffeeGlyphScale`, driven by `poured` seconds; the payoff fires once, at
   full). Only when the pot slides off does it **rise on from that spot** on a
   fresh chimney (`thawCoffeeCup` → `launchCoffeeRise`). The hit box grows with
   the glyph, so a swollen cup is caught by all of it. History, all 2026-09-24:
   first it kept rising while it filled; then it froze but left the pot the
   moment it was full; Victor wanted it to **freeze on contact and just keep
   growing where it is**. The pot stays out 0.35 s
   after the hand leaves the last cup (no flicker across a cluster), then the
   arrow comes back. A full cup is the **payoff**: one `coffee-popped` webhook
   (below) — the gesture changed from "hold until it pops" to "pour until it is
   full"; the minute it buys did not.
3. **Escalation = explosions, unlocked by a salvo.** `CoffeeStormGauge` (pure,
   tested) counts arrivals in `spawnEmoji`: **more than 3 inside one second**
   ARMS the mode. From then on a cup the pot touches does not fill — the glyph
   **grows to 3× (on top of its fill) while shaking harder and harder for 1.3 s,
   then bursts** (`beginCoffeeExplosion` → `burstCoffee`): `pixelDissolve` at
   violence 3.0–4.5 (denser salvo → harder) on the 22×22 grid, fragments thrown
   across the screen. Each burst is also a payoff (the trainer touched it).
   **How the mode ends** — the spec left it open, this is the decision, also in
   the code comment on `coffeeStorm`: the gauge keeps it armed for **10 s** past
   the last second that was over the threshold (a room taps in salvos; a mode
   that switched off between two salvos would explode one cup and fill the next),
   **and** it ends early the moment **no cup is left on screen**, so a straggler
   arriving after the salvo has been dealt with is offered, not detonated. Both
   are a deadline or a fact on screen, never a flag to remember to clear;
   `stop-all` resets it at once.
4. **Contact freezes, whatever follows.** A cup is two layers (`CoffeeCup`).
   The **carrier** rides the chimney (position, the 1→1.3 growth, the fade);
   the **glyph** inside it is the only thing the pour and the explosion touch
   (fill scale, shake, blow-up). The pot's one effect on the carrier is to
   freeze it — for an armed cup too since 2026-09-24 (it used to explode on
   its path): it shakes and bursts **right where it was caught**. Freezing
   also strips the `"fade"` animation, so a cup caught near the top stays
   visible until it bursts.
5. **A burst clears the screen** (2026-09-25). Once a cup has burst and paid
   its −1, every other ☕ still rising fades out together in 0.4 s
   (`clearCoffeesAfterBurst`, `coffeeClearSeconds`) instead of drifting on as
   targets. Cups already shaking toward their own burst are left alone — each
   still owes its own −1. The screen is then empty, so the gauge disarms on the
   next tick (point 3) and the next ☕ arrives calm. `/effect/coffee/pop` clears
   the same way.

Which emoji counts is configuration, not a literal: `chargeEmoji` (default
`["☕"]`). A stop-all clears the cups, disarms the mode and takes the pot off
the cursor — the pot lives outside `activeEffects` and hides the real pointer,
so leaving it behind would strand the desktop with a teapot for a cursor.

`tickCoffeePour` returns **where each payoff happened**, in global
coordinates (fills on the spot; bursts collected from the explosion's
completion block and handed over on the next tick), and `CoffeePourMonitor`
turns each point into one fire-and-forget
`GET <eventWebhook>?type=coffee-popped&x=&y=` (`EventWebhook.coffeePopped`).
The payoff — in Victor's rig, pulling a break timer closer — lives in another
process on purpose: the pour must never wait on a network call, and the
webhook is the smallest thing that carries the gesture across. The event kept
its old name so the addons side did not have to move. With no `eventWebhook`
configured the ☕ still fills and still bursts; nothing else happens.

`/effect/coffee` spawns three (not a salvo: they fill); `/effect/coffee/storm`
is 8 in one second (a salvo: touch one and it bursts); `/effect/coffee/pop`
(`popCoffeeForTest`) bursts one mid-screen and fires the event, the headless
proof of the whole chain.

## ⏸️ Suspending everything for a few seconds

`GET /effect/suspend` · `/effect/suspend/<seconds>` · `/effect/resume`
(`EffectsSuspension`, pure + tested; gate in `EffectsEngine.runEffect` and
`spawnEmoji`).

Walkie Talkie drags a crop box out of the screen with the **wheel held down**,
and whatever is floating over the desktop at that moment lands in the picture.
That crop is the one capture in the rig that takes *seconds* rather than a
millisecond — Victor frames it while still talking — so "it will be gone by the
time the shutter fires" is not true for it: the room keeps tapping ☕ while he
frames. It therefore suspends on the press and resumes on the release
(2026-09-22).

A suspend both **clears what is on screen** (it calls `stopAll`) and **drops
what arrives next**; a suspend with a storm still raging would be half the job.

**It is a deadline, never a flag.** The process that suspends is a different
app: it can be killed, redeployed or crash between the suspend and the resume,
and a boolean would leave this app silently deaf for the rest of the day with
nothing on screen to say why. The hold expires by itself, `resume` is only an
optimisation that ends it sooner, and `maxSeconds` (60) caps what any caller may
ask for. A second suspend **extends but never shortens**, so two overlapping
crops cannot have the first one's resume cut the second one short.

`suspend`, `suspend/<n>`, `resume` and `stop-all` are the four words that are
always heard — a hold that could not be lifted or extended is the exact trap the
deadline exists to avoid, and "clear the screen" can never be what a cleared
screen refuses. Everything else is dropped with a log line naming it.

Victor Addons proxies `/effect/*` verbatim, so the caller talks to **55123** like
every other client and never needs to know this app's port.
