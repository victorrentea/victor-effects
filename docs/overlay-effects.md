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

**There is no longer a fourth door through the menu.** The 💥 menu used to carry
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

| | nothing running (💥) | something running (🛑) |
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
point: an effect starts, the bar still says 💥 for a third of a second, and a
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
  each — the least detail that still reads as a snowflake and not an asterisk), white
  stroke with a white glow, because ❄️ renders as the system's blue-tinted glyph and
  what is wanted here is white snow over whatever is on screen. **One number — depth
  0…1 — drives size, fall speed, brightness and sway width together**, so a flake can
  never read as a contradiction (big but distant, tiny but racing); near flakes are
  **40 px**, bright and cross in ~3.5 s, far ones **10 px**, faint and take ~6.5 s —
  twice the size they started at, because at 5–20 px they read as specks on a
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
- **🌑 Death Star** (sfx #55 `55_star_wars.mp3` → `star-wars` / `star-wars/stop`,
  `showStarWars`): a Death Star climbs the diagonal out of the bottom-left corner and
  **stops near the middle of the screen** (`starWarsRestPoint` = 0.42 W, 0.44 H — its
  centre), 0.69 of the screen height across, in 6.5 s of the 10 s clip; the last 3.5 s
  it simply hangs there.
  - **The artwork is a whole sphere, and that is the load-bearing change.** The
    original `death-star.png` was a *crop*: cut off flat along its left and bottom
    edges, so the only place on screen where those cuts are invisible is welded into
    the bottom-left corner, with the slices exactly on the screen edges. Pulled even
    10% inboard, the sphere visibly showed two straight cut lines. So the missing
    lower-left limb was **rebuilt**: fit a circle to the silhouette (centre 314,394,
    R 364 in the source's pixels), then fill everything inside it that the crop never
    had by walking radially inward to the nearest real pixel and darkening steeply
    with the distance walked, which lands the fabricated part in the sphere's own
    shadow where nobody reads detail. The white fringe the source kept from being cut
    out of a white background is dropped on the way (it was extrapolating into a white
    crescent down the left limb). The result ships **in the app bundle**, and only there — it
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

- **🔫 Minigun** (sfx #22 `22_minigun.mp3` → `bullet-holes`, `showBulletHoles`): the burst
  that punches bullet holes around the cursor now has a **visible shooter**. A pixel-art
  minigun sprite (`Resources/minigun.gif`, 64 frames, transparent, top empty rows cropped)
  rises out of the **screen's bottom edge** and shifts only west–east at half the mouse travel:
  `bodyX = mouseX × 0.5`. A centred cursor therefore parks the mount at **25% of the screen
  width**, and its complete edge-to-edge travel remains inside the left half. The weapon
  **never rotates**; it keeps the firing angle painted into the GIF while the mount slides
  under the reticle. Position rides the **same 60 fps tick as the reticle**
  (`startMinigunReticle(following:)`), so the gun cannot lag a frame behind the crosshair.
  The reticle remains the shot target while the mouse
  is still: bullet spread stays clustered within 140 px of it for the whole burst, instead of
  reverting to random full-screen hits after one second. Only an off-screen cursor uses the
  unaimed full-screen fallback. The sprite is drawn firing **north-west**, so its child is
  **mirrored on X** to give the starting north-east pose; `minigunSpriteFacesWest = false`
  shows it as drawn if the other orientation is ever wanted. The tracking anchor uses the
  receiver's measured horizontal centre line (`minigunSpriteGunCentreX`), not the geometric
  centre of a frame that is mostly empty sky for the ejected brass.
  Width is 44 % of the screen *for the whole frame*, which puts the gun body itself at ~20 %
  and lets the casings arc up and to the right over the lower-left of the desktop;
  aspect-preserved, drawn
  with **`.nearest` magnification** — bilinear smoothing at that scale turns the barrels into
  grey mush. The 64-frame loop keeps the source gif's own **0.02 s/frame — 1.28 s a turn**:
  the muzzle flash cycles every 8 frames (~6 flashes/s, a believable cyclic rate) while the
  casings need all 64 to finish their arc, so speeding the loop up would fling the brass out
  at a comic speed. It rides **inside the burst's own container**, so `trackEffect` and a
  cancelling re-press take it down with the holes; the tail's "resorb" shrink pass skips it
  **by identity** (`hole !== gun`) so the gun doesn't implode along with the bullet holes.
  Its opacity is **one keyframe track** (the wasn't-me pattern) beginning at **t=0**: the gun
  is the first thing on screen, and it has faded out by the time the last hole is resorbed.
  The **`minigunAimLeadIn` belongs to the gun, not the reticle** — the weapon rises
  out of the bottom edge and hauls itself after the mouse *before* the
  pointer turns into the crosshair and the sound + bullets start, which is the order the
  gesture actually reads in: you see the thing that is about to shoot, then it shoots. The
  reticle layer and its 60 fps tick are still created on the press (the tick is what steers
  the gun during the lead-in, and an early layer keeps every `_minigunReticleLayer === reticle`
  identity guard covering the lead-in, so a cancelling re-press inside it cannot leave a reveal
  scheduled behind it) — only the crosshair's opacity and the **real cursor's hide** are
  deferred to `revealAfter`. Hiding the cursor early would have left the desktop with no
  pointer at all for that silent stretch.
  - **The lead-in is a full second and it is silent (2026-09-11).** It used to be 0.5 s, and
    the noise did not respect it at all: the tablet starts the audio in its **own** HTTP
    request (`/sound/play/22_minigun.mp3`, sent just before `/sound/pressed/…`), so the burst
    was audible while the gun was still climbing. The routed path now special-cases the tile
    in `EffectsEngine.playSound` and hands `playTabletSound` an explicit
    `lead: EmojiAnimator.minigunAimLeadIn` — the one `lead:` override in the app, for the one
    sound whose head start is owned by animation code instead of `sound-timing.json`. The
    lead is added to the returned `durationMs` exactly as a configured one is, so the tile
    stays lit for the whole thing (≈7.4 s now, not 6.4 s) instead of un-highlighting a second
    early. `spawnStart` also went **0.25 → 0**: reticle, first hole and first frame of noise
    now land on the same instant, which is the whole point of the silence before them.
    Three log lines (`🔫 gun up…`, `🔫 reticle revealed`, `🔫 first bullet hole`) make that
    checkable without watching the screen.

- **🪚 Chainsaw cursor** (tile #18 `18_chainsaw.mp3` → `chainsaw` / `chainsaw/stop`,
  `showChainsawCursor`): for the length of the clip **the mouse pointer IS a running
  chainsaw** — the real cursor is hidden and a 16-frame sprite loops on it, chasing
  `NSEvent.mouseLocation` at 60 fps. It is the third member of the hidden-cursor family
  (💘 spiral-hearts' beating heart, 🔫 minigun's reticle) and follows their rules: it lives
  **outside `activeEffects`** because it owns a follow timer *and* a hidden system cursor,
  so `stopAllActiveEffects` tears it down **explicitly** — a generic sweep would drop the
  layer and leave the desktop with **no visible pointer at all**. The hide is armed through
  `armBackgroundCursorHiding()` (the private `SetsCursorInBackground` flag) so it also
  applies while Victor is in someone else's app, and the unhide is balanced by a single
  `_chainsawHidCursor` flag so a spurious stop can't force the cursor back mid-run.
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
    the cursor. It burns **permanently, independent of the mouse** — an idling blade against
    material still throws chips, and a shower that switched off when the hand stopped would
    go dark at exactly the moments Victor is holding the saw still to point at something. On
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
  - **Lifecycle**: length read off `18_chainsaw.mp3` via `AVURLAsset` (~6.09 s, with that
    value as the fallback) and self-stopped at it, **generation-guarded** so an old run's
    timer can't kill a newer one. The lifecycle rule matters more here than anywhere else:
    a lost `/sound/stopped` on a flaky venue network would otherwise leave the desktop with
    no cursor. The tablet's stop still shortens it through `onStop` → `chainsaw/stop`.
    Press path only (`SoundEffectMap`), so the routed `/sound/play/18_chainsaw.mp3` supplies
    the audio and the visual never double-triggers. `/test/chainsaw`, `/test/chainsaw/stop` and
    `/effect/chainsaw` fire it silently.

- **🔥 Fire cursor** (tile #11 `11_fire.mp3` → `fire` / `fire/stop`, `showFireCursor`):
  the chainsaw's trick with a flame — the real pointer is hidden and a 40-frame fire
  sprite burns on it, chasing `NSEvent.mouseLocation` at 60 fps on the built-in screen.
  A first press starts **280 pt wide** (`fireBaseWidth`) — halved to 140 on 2026-09-09
  because the flame stopped reading as a *pointer*, then put back to 280 on 2026-09-10 at
  Victor's request. What makes 280 workable now is the rest of that change: the wheel size
  **survives the run** (`fireRememberedScale`), so shrinking to a torch is a one-time
  gesture instead of a per-press tax, and the wheel ceiling is **the screen width**, so the
  default is no longer near the top of the envelope.
  Fourth member of the hidden-cursor family and bound by the same rule: **outside
  `activeEffects`**, torn down explicitly by `stopAllActiveEffects`, hide armed through
  `armBackgroundCursorHiding()` and balanced by `_fireHidCursor`. It replaced the tile's
  old "Lady in Red" clip (tile art and asset renamed; the original mp3 is in `backup.zip`).
  - **Art**: `Resources/fire-frames.png`, an **8×5 sprite sheet** of 40 cells, keyed out
    of a black-background gif with **alpha = luminance × 2** (clamped). The ×2 is not a
    brightness trick: straight luminance-as-alpha leaves the orange edges and every spark
    half-transparent, which over a slide reads as a washed-out stain instead of fire *on
    top of* it. Same sheet-not-gif reasoning as the chainsaw — gif's 1-bit alpha would
    fringe the glow black on every desktop. Sliced once into a lazy static (`fireFrames`).
  - **Anchor**: `(0.5, 0.10)` — the flame's **root**, near the bottom edge and centred, so
    the fire grows *upward out of* the pointer rather than swallowing it. Deliberately not
    the chainsaw's teeth anchor: a flame anchored on its own bite point puts half the smoke
    plume below the hand,
    and the thing being pointed at is what should be on fire.
  - **Timing**: 40 frames at **30 fps** (1.33 s loop) — the source clip's own rate, kept
    rather than halved to the chainsaw's 15, because this one is on screen for a **36 s**
    sound and fire at 15 fps reads as a strobing loop within seconds. Base width **280 pt**
    (2026-09-10; 140 between 09-09 and 09-10),
    `zPosition` 9500, 0.12 s fade-in / 0.25 s fade-out with the real cursor restored only
    after the fade.
  - **Escape puts it out.** This is the first effect with a *user* exit, and it needs one:
    36 s is far too long to sit through if the tile lands at the wrong moment. Escape is
    taken by a **`CGEventTap`, not an `NSEvent` global monitor** — a monitor can only
    observe, and an Escape that also closed the user's dialog would make the effect cost
    something. The keypress is **consumed**, and it stops the routed clip too
    (`stopTabletSound` + `stopAllPlayers`); a press the tablet chose to play on its **own**
    speaker is not ours to stop.
  - **The wheel sizes it while it burns.** Same tap: one notch is a **multiply** by 1.10,
    so a step feels the same at a candle and at a bonfire. The clamp is 0.30 × at the
    bottom and **the screen** at the top (2026-09-10; it was a flat 3.50 ×): `fireMaxScale`
    is `hostLayer.bounds.width / fireBaseWidth`, i.e. the flame can grow until it is
    exactly as wide as the display it burns on. A fixed multiple made "as big as it goes"
    a different fraction of a 13" retina than of a projector, and on stage that ceiling is
    the size Victor actually reaches for. `NSScreen.main` is the fallback while the overlay
    has no bounds yet.
  - **The size is remembered for the life of the process.** Every wheel notch writes
    `fireRememberedScale` (a **static**, RAM only), and the next `showFireCursor` reopens
    there, clamped to the current `fireMaxScale` in case the last run was on a wider screen
    that has since been unplugged. Sizing the flame is a deliberate few seconds of
    scrolling in front of a room; snapping back to default on the next press made that
    gesture disposable. Not persisted to disk on purpose — a restart starts neutral rather
    than from whatever one demo needed.
    Trackpad pixels are accumulated into 12-pt notches so a two-finger flick doesn't jump
    from candle to inferno. The resize edits **`bounds`, not `transform`**, which keeps the
    anchor pinned so the flame's root stays exactly on the pointer as it grows. Scroll is
    consumed (no scrolling the app underneath while sizing) **except with ⌘ held** — that
    belongs to `EventTapManager`'s terminal font zoom, and silently eating it for 36 s
    would look like the zoom shortcut had broken.
  - **Lifecycle**: three ways out — the length of `11_fire.mp3` (`AVURLAsset`, 35.88 s
    fallback, generation-guarded), Escape, or the tablet's `onStop` → `fire/stop`. The
    clip's length stays the authoritative one for the usual reason: a lost `/sound/stopped`
    would otherwise strand the desktop with no cursor. `/test/fire`, `/test/fire/stop` and
    `/effect/fire` fire it silently.

- **💘 Spiral hearts** (tile #42 `42_saxophone.mp3` → `spiral-hearts` / `spiral-hearts/stop`,
  `showSpiralHearts`): **the cursor becomes a pulsing red heart** for the length of the clip
  (the real pointer is hidden — it is the first member of the hidden-cursor family the
  chainsaw and the minigun reticle later joined, and like them it lives *outside*
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
  lub-dub keyframe, twice per cycle, with the lens **re-centred on the live mouse
  before every beat** — the screen beats wherever the cursor rests.
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
    screen's area)**, then taken down by `scale` = **0.7**. The unscaled fit put a cat
    690 pt wide in the corner and it read as the subject rather than as company for the
    beat — `heartbeatDogScale`'s lesson, learned again one corner over. It spent a few
    minutes at **1.4** on 2026-09-14 ("de două ori mai mare") and came straight back ("și
    să fie totuși 2x mai mică"): at 1.4 the cat is 1098 pt wide on the built-in panel and
    cannot both stay on screen and stay off the lens. **The follow is what the size was
    really buying** — a cat that walks over to the beat does not need to be huge to be near
    it. The asset's 1.40 aspect is squarer than the box on any wide screen, so **height**
    is what binds: on the 1728 × 1117 built-in panel the cat measures **549 × 391** (logged
    on every run with its starting x), and on the 1512 × 982 the heartbeat tests use as
    their fixture, ≈ 483 × 344.
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
  - **Which bomb the head boom already owns.** That same offset is how late a target can be
    planted and still explode on the *head* boom's own blast — so a bomb clicked inside the
    first `bombBoomLead` seconds gets **no copy at all**; it is already scored. This is why
    the first bomb sounds exactly as it did before.
  - **Loudness.** A copy swells from silence over the whole fuse (`fadeIn:` on
    `playOverlapping`) instead of banging in at full level, at `bombBoomVolume` (0.75)
    thinned by **1/√n** over the bombs still in the air, floored at `bombBoomVolumeFloor`
    (0.35). The equal-power law is the point: two booms a beat apart land at roughly the
    loudness of one, not twice it — the room hears more explosions, not more volume.

  The copies are **not Bluetooth-compensated** (`bluetoothCompensated: false`), for the
  same reason as the 🔥 whip crack but arrived at differently: something has been sounding
  for at least `bombBoomLead` seconds by then, so the A2DP link is warm, and adding the
  start delay would push the blast late off the fireball it exists to land on.


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

- **🔴 Big red button** (tile #7 `07_animated_phone.mp3` → `red-button`,
  `showRedButton`, `RedButton.swift`): **the one effect the room does not just
  watch.** A big red arcade button zooms out of the pointer, lights up when the
  pointer is on it, goes down when it is pressed, and shrinks back into the exact
  pixel it came from.
  **The asset is not in this repo.** `red_button.gif` lives in
  `EffectsConfig.assetsDir` (`~/.victor-effects/assets` by default), same rule as
  `wazzup.png`, `brother_full.gif` and `scared_cat.gif` — a stock arcade button,
  background flood-filled to alpha and alpha-trimmed, **468×426, two frames**:
  frame 0 raised, frame 1 pressed in. Missing ⇒ one log line
  (`showRedButton: no red_button.gif in …`) and no overlay; the clip still plays.
  A one-frame replacement is legal — the press then falls back to squash 0.92 +
  brightness −0.15 instead of swapping the frame.
  **Geometry.** Height is **a sixth of the overlay screen's height** (`0.5 / 3` —
  it shipped at half and was cut to a third of that), width by the image's own
  aspect, centred **exactly** on the pointer — and deliberately *not* clamped onto
  the screen. The whole promise is "grows out of P, shrinks back into P"; a button
  nudged inwards to fit would shrink into a pixel nobody clicked, which is a worse
  lie than a button hanging off the edge when the pointer was parked in a corner.
  The size is also what makes the pass-through click below worth having: a button
  covering half the slide was covering whatever the click then landed on.
  Zoom out **0→1 over 0.70 s, ease-out** — twice the old 0.35 s, because a sixth
  of the screen is a small enough movement that a fast arrival is over before the
  room has found it; shrink back **1→0 over 0.30 s, ease-in**, unchanged — the
  entrance is an arrival and wants to be seen, the exit is a dismissal.
  **Hover costs a second window.** The desktop overlay is `ignoresMouseEvents =
  true` so effects can be drawn over a Mac somebody is still working on; flipping
  that for the whole screen would make the desktop deaf. So the artwork is a
  layer on the shared `hostLayer` and the hit target is a **second small panel**
  laid exactly over it (`RedButtonHitPanel`, the mascot's `PeekHitPanel` trick).
  Two differences from the mascot: the cursor is the **pointing hand** rather than
  `PanelCursor`'s pinned arrow (same mechanism — a tracking area's `cursorUpdate`,
  because a borderless non-activating panel does not own the pointer's shape just
  by being on top — opposite answer: the board is a surface, this is a button and
  it has to *look* pressable); and the panel is **only listening while the pointer
  is on an opaque pixel**. `RedButton.isOpaque` alpha-tests an 8-bit mask of the
  first frame, and the controller flips `ignoresMouseEvents` off that, so a click
  in the transparent corners reaches the app underneath. A circle wastes 21 % of
  its bounding box on those corners.
  The hand is re-asserted on **every** mouse-move that lands on an opaque pixel,
  not only on the one that arrived there: the app underneath still owns the
  pointer's shape and restores its own cursor on each move it sees, so a single
  `.set()` at the boundary survives only until the next event — which is why the
  hand used to flicker back to an arrow while the pointer sat on the artwork.
  `ThumbnailGridView`'s `PanelCursor` pins the arrow the same way.
  The hit test uses the **resting** rectangle, never the hovered one: hit-testing
  the grown rect makes the edge bistable (cross in, it grows to meet you, you are
  inside; leave, it shrinks away, you are outside) and the boundary flickers at
  the frame rate. Hover look: **scale 1.06 + brightness +12 %** — both, because
  the scale carries from the back of a room and the brightness carries on a
  mirrored projector that has flattened the contrast.
  **The click goes through to what was underneath.**
  `RedButtonController.onButtonClicked: ((_ origin: CGPoint) -> Void)?` is called
  on **mouse-up on the button**, with `origin` = the **global screen point** the
  button grew out of, and `EmojiAnimator.showRedButton` assigns it to
  `RedButtonController.deliverClickBelow(at:)`: a synthetic left down+up posted at
  P. The prop had to *eat* a real click to know it was pressed — the hit panel
  consumed it — so it hands one back at the same pixel, and a button grown over a
  link, a Play or a Run leaves that button clicked. The press still logs
  `🔴 red button clicked — origin P=(x,y)`, then
  `🔴 red button: click passed through to P=(x,y)`.
  **The post is one runloop turn late, and that is not a detail.** `.click` runs
  before `.shrinkPressed` in the same `perform` loop, so at hook time the hit
  panel is still up and still listening on exactly the pixel the click is aimed
  at — posting there hands the event back to us and presses the button again. The
  `DispatchQueue.main.async` inside `deliverClickBelow` puts it after
  `shrink()`'s `hitPanel.dismiss()`, which sets `ignoresMouseEvents = true`
  immediately. The flip into `CGEvent`'s top-origin space goes through
  `RedButton.flipY(_:screensMaxY:)`, the same pure function the hover tap uses to
  come the other way, so the two cannot disagree about where the top of a
  multi-screen desktop is.
  Anything louder than passing the click on (a crack, a blast, a webhook) is a
  decision about the room, not about this mechanism — it is wired at that one
  call site and touches nothing else.
  **Clicked ⇒ stays pressed. Timed out ⇒ comes back up.** That distinction is the
  reason the lifecycle is a state machine (`RedButton.Phase`/`Event`/`Action`,
  `next(_:_:)`) rather than a handful of booleans, and it is asserted in
  `RedButtonTests` without a screen. A press dragged off the button cancels, like
  every other button on the machine; a `mouseUp` during the shrink fires nothing.
  **Lifetime — the one effect that outlives its clip.** Tile 7's sound is a couple
  of seconds and the button is a prop Victor talks over *and then* presses, so
  "the sound ended" is explicitly not the deadline: there is no `onStop` entry, and
  the tablet's `/sound/stopped` must not take it away. It ends on the click, on
  **Esc**, on `stop-all`, or on its own **20 s** deadline
  (`RedButton.maxLifetime`), after which it shrinks away **un-pressed**. That
  deadline is the self-termination rule for an effect with no clip length to
  inherit one from.
  Esc is taken with a local `CGEventTap` for the fire cursor's reason — a monitor
  can only observe, and an Esc that also closed the user's dialog would make
  dismissing the button cost something. The same tap watches `mouseMoved` (passed
  through untouched) to drive the hover. Like the fire cursor and the
  bombardment, the run holds a tap **and** a real window, so `stopAllActiveEffects`
  tears it down explicitly (`stopRedButton`) instead of relying on the
  `activeEffects` sweep, which would drop the artwork and leave an invisible
  rectangle eating clicks in the middle of the screen.

## ☕ The hold-charge gesture

`EmojiAnimator.tickCoffeeCharge(cursorGlobalPoint:)` is polled at 10 Hz by
`CoffeeChargeMonitor` (`Timer` in `.common` mode, so the charge ring keeps
filling while a menu is open). Resting the cursor on a rising ☕ **catches** it:
the emoji freezes, grows for ~3 s, then shatters into its own pixels. Several
under the same cursor all inflate together. Sliding off before 3 s
**releases** rather than kills it (`releaseCoffeeCharge`) — it snaps back to
the size an untouched flight would be at by now and resumes rising.

Which emoji can be charged is configuration, not a literal: `chargeEmoji`
(default `["☕"]`).

`tickCoffeeCharge` returns **where each one popped**, in global coordinates, and
`CoffeeChargeMonitor` turns each point into one fire-and-forget
`GET <eventWebhook>?type=coffee-popped&x=&y=` (`EventWebhook.coffeePopped`).
The payoff — in Victor's rig, pulling a break timer closer — lives in another
process on purpose: the dissolve must never wait on a network call, and the
webhook is the smallest thing that carries the gesture across. With no
`eventWebhook` configured the ☕ still charges and still pops; nothing else
happens.

`/effect/coffee` spawns three so the gesture can be exercised by hand;
`/effect/coffee/pop` (`popCoffeeForTest`) skips the three-second hold entirely
and fires the same event, which is the headless proof of the whole chain.
