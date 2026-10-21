# 🔥 The Whip

A physics whip that follows the cursor and, when you crack it, interrupts the
coding agent in the focused terminal. A native Swift port of
[OpenWhip](https://github.com/GitFrog1111/OpenWhip) (`overlay.html` +
`main.js`), attributed in the file headers.

Three files, one overlay:

| file | what it is |
|---|---|
| `WhipPhysics.swift` | the simulation: 28 Verlet segments, gravity, constraint iterations, the flick detector. Pure — no AppKit, no time source of its own |
| `WhipOverlay.swift` | `WhipController` + `WhipPanel` + `WhipView`: the window, the per-frame draw, the cursor poll, the crack sounds |
| `WhipMacro.swift` | what a *click* sends into whatever app has focus |

**Under ⌥-scroll zoom the rope keeps its size** (2026-10-16): the panel is
re-mapped every frame onto the slice on the glass, shrunk by the zoom, with the
view's bounds kept at the whole screen (`ZoomedPanel`), and the pointer is
converted with that same slice — so the physics still runs in whole-screen
points, which are now glass points. At rest nothing changes.

**Under ⌥⇧ zoom (`ShareZoom`, addons) the panel must stay at `maximumWindow`**,
above that zoom's `.screenSaver` window. Until 2026-10-19 it was really at
`.floating` (3): `isFloatingPanel = true`, set after the level, resets it — so
the rope disappeared the instant the zoom's first frame arrived. The panel no
longer sets `isFloatingPanel`; `WhipPanelLevelTests` checks the level.

## Turning it on

**⌃W** shows the *selected* mode, globally, **swallowed** — the key does not
reach the app underneath — and **⌃W again puts it away**. **⌃⇧W picks the next
mode**: 🔥 whip → 🙏 pray → 🫰 snap → 🔥 whip …, shown at once so the switch is
seen (2026-10-21, Victor: *"Control Shift W should change the way of the whip.
Control W should toggle it on or off, and it should remember the selection"*;
for one day before that, ⌃W alone cycled and only Esc got out). The selection is
`PointerModeStore.selected` in `UserDefaults`, so it survives the restarts of a
course day, and it is simply **whatever was shown last** — by ⌃⇧W, a menu row
or `/effect/<name>` — so ⌃W always brings back the mode last seen
(`EffectsEngine.toggleSelectedMode` / `nextMode`). **Esc** still dismisses
whichever is up. These two are the only rules in `EffectsHotkeyTap` that return
`nil`, and the only reason the tap needs **Accessibility** rather than Input
Monitoring.

The consequence is deliberate and worth knowing: **⌃W stops deleting the word
backwards** in terminals and editors for as long as this app runs.

**⌘⌃W is not bound** and never will be. The rule is
`hasCtrl && !hasCmd && !hasOpt` (`EffectsHotkeyTap.decideKey`, ⇧ choosing
between toggle and next), and
the `!hasCmd` clause is there so a dictation app that owns ⌘⌃W for "paste
transcript" keeps it. Both can run at once only because of that one clause.

**The menu-bar icon shows 🛑 while the whip is armed**, and a click on it
dismisses the whip exactly as Esc does (`stopAll()` → `WhipController.hide()`).
An armed whip is a mode — it gates the Return/buttons-6-7 crack and the
click-types-the-macro behaviour and has no deadline of its own — so the status
item stays 🛑 for as long as it is out; that is the emergency-stop surface being
honest about what a click would do, see `docs/overlay-effects.md`.

There is also a **`🔥 Whip` menu row** with ⌃W shown in its hint column. It
is not redundant: on a Mac that has not granted Accessibility the tap is not
installed, and the menu is then the only way in. (The same rationale as a
"mail the clipboard" row in the app this was cut from — a menu row is the
fallback *and* the place the shortcut is taught.)

## Cracking it

Three ways, all landing on the same crack:

1. **A real flick** — sweep the mouse fast enough sideways and the physics
   cracks on its own.
2. **Return / keypad Enter**, while the overlay is up — `decideKey` returns
   `.crack` and **passes the key through**. This matters: the key that cracks
   the whip is usually the same key submitting the prompt, and swallowing it
   would make the gesture useless. A Return synthesised by another tool (a
   thumb-button remap, say) re-enters the tap as a real `keyDown`, so it cracks
   the whip too.
3. **Mouse buttons 6 or 7** (`otherMouseDown`, button numbers 5 and 6) — same
   rule, also passed through (`decideMouse`).

A keyboard/button crack is a **scripted flick**: `forceCrack` queues
`flickProfile` handle positions (~8 frames ≈ 130 ms, out and back) that the
physics consumes one per frame, so the rope moves exactly as a hand would have
moved it. There is no separate "play the sound now" path.

Each crack plays one of `whip_A..E.mp3` at random, **seeked to its measured
snap onset** (`crackOnset`: B at 0.13 s, D at 0.155 s, E at 0.06 s). Without the
seek, two of the five samples bury the snap behind 140–170 ms of wind-up swish
and the crack you hear trails the one you see, at random. Volume rides the
soundboard's own level at `crackVolumeFactor` (0.64) — at full level the crack
genuinely startles a room, which is not the joke.

Cracks are **not** Bluetooth-compensated (`bluetoothCompensated: false`): the
overlay holds the A2DP link warm with `BluetoothOutput.startContinuousWarm()`
for exactly this reason, so a crack has zero spin-up lag and adding the
compensation delay would only make it late.

## It asks nicely — a "please" where it cracks

**Every crack throws one polite word off the tip** (2026-10-19, Victor: *"make
my whip throw please statements … whenever where it cracks"*): *please*,
*pretty please*, *I beg you*, *with a cherry on top*, … plus the polite words the
whole EU knows (*por favor 💃*, *per favore 🤌*, *bitte schön 🥨*, *s'il vous
plaît 🥐*, *grazie mille 🍝* — added 2026-10-20) and British manners (*terribly
sorry ☕*, *chop chop, old bean*, *lovely jubbly*) (`WhipPleas.phrases`),
in heavy pink, 41 pt with a **black** outline drawn UNDER the fill, round-joined
(one-pass fill+stroke cut seams through e, a, k, E; 34 pt and white until
2026-10-20), popping to 115% and floating 70 pt up over 1.3 s before it fades.
It appears **ahead of the pointer, the way it was moving** when the rope
snapped (2026-10-20, Victor: *"if it was heading … west, then the kind word
should appear … towards the tip … as it cracked towards the west"*): the
heading is the handle's travel over the last 200 ms (`headingWindowMs`, from
`handleTrail`), and the word lands as far out along it as the tip was from the
pointer (at least `minReach`, 100 pt) plus 60 pt (`throwBeyondTip`)
(`WhipPleas.launchPoint`). The line from the handle through the tip alone, the
first rule, threw it backwards on a flick — the tip trails behind a pointer
swung west until the very end. With no heading (under 15 pt of travel) that
line still decides; a tip curled back onto the handle sends it straight up. Drawn by `WhipView` itself, so it sits on the rope's
panel and keeps its size under ⌥-scroll like the rope does, and clamped inside
the screen so a crack at the bezel does not cut the word in half.

- **Owed, then paid.** `cracked()` (the funnel) only marks a plea owed; `tick`
  throws it on the frame the physics actually snaps — or when a scripted flick
  runs out without one. Either way it is thrown from **the lash** — where the
  tip was on its fastest frame while the plea was owed (`pleaLash`) — because
  by the end of a flick with no snap the tip has swung back to the pointer. A Return/thumb crack goes through the funnel
  *before* its flick, while the tip still hangs at the pointer, so throwing it there put
  the word in the wrong place.
- **A shuffle-bag, not `random()`** (`WhipPleas.Bag`): every word once per round,
  never the same one twice in a row, even across the refill (`WhipPleasTests`).
- Each word dies on its own clock (`lifeMs`, pruned in `tick`), and `hide()`
  takes them down with the view. Not behind ✓ Subtitles — it is part of the
  whip, like the sparks on a hit.
- The *typed* phrases of a click (`WhipMacro.phrases`, "FASTER CLANKER") are a
  different gesture and still scold — the room sees manners, the agent does not.

## The mascot flinches — when the rope hits him

**Only a hit counts** (2026-10-16, Victor: *"să sară … doar dacă îi atinge
biciul, și atunci să apară niște scântei unde îl atinge"*). Until then every
crack anywhere on the screen made the ⌘⌃Q mascot jump. Now the whip reports its
rope every frame (`WhipController.onRope`: the links in global framebuffer
points, converted by AppKit so the ⌥-scroll shrink is included, plus how far
each moved), and `EmojiAnimator.whipLash` makes him jump only if:

- a link **moving at least 18 pt a frame** (~1100 pt/s; a crack's tip runs at
  260) — a rope draped over him or carried slowly across is not a hit;
- **outside the handle third** of the rope — that end is the pointer, and
  pointing at him is not hitting him;
- passes over a **drawn pixel** of him (`PeekAlphaMask`, a 128-px-wide copy of
  the picture's alpha read with a one-cell margin), not his box — the
  transparent corners around Clawd are a miss. Each link is walked every 5 pt
  (`lashSampleStep`) so a leg is not stepped over between two links, and the
  hit test takes him where he is drawn: staged for ⌥-scroll, mid-slide, mid-hop.

**And he gasps** (2026-10-20, Victor: *"both Claude Code and Copilot should
make a scary face or put an O mouth"*): every hop puts a dark **O mouth** on the
face for 0.75 s, popping in and fading out (`PeekOMouth`). Drawn as a sublayer,
not a second picture, so it rides the hop and works with any cut-out; the face
positions were measured off the two PNGs — under Clawd's `> <` eyes, and on
Copilot's face plate under his pill eyes — and are taken on the bare picture,
without the rim or the 🎅 hat. `/test/claude-peek/flinch` hops him (and the O)
without aiming a whip.

One hop per lash (0.35 s cooldown, a lash crosses him over several frames), and
**a few sparks fly where it hit**: a white flash and twelve short yellow streaks
thrown out of the contact point, gone in 0.6 s, `1/zoom` under ⌥-scroll. The log
says `🔥 whip hit claude-peek at x,y`. A Return/thumb crack is a scripted flick
from the pointer, so it hits him only if that flick sweeps through him.

The hop itself is unchanged (`EmojiAnimator.whipClaudePeek`): The whip already scolds the agent in the
terminal; this is the same joke told to the room instead of to the shell, and
the robot standing still through a crack aimed at him was the thing that read as
missing.

**One crack, one hop.** A scramble of four hops was tried on 2026-09-21 and was
too much animation for one sound — *"să sară doar o dată un pic la o lovitură de
bici și apoi să revenim la poziția originală"*. The repetition comes from the
whip, not from the hop: crack again and he jumps again.

**Each crack goes a different way.** `peekWhipHopDirections` is walked in order,
one entry per crack, and consecutive entries throw him to **opposite sides** —
so the second crack always answers the first. All of them go up; the leftward
ones are the small ones, because `claudePeekFrame` insets him by 4.5% of the
screen width (≈0.17 of his own height) while the whole screen is open to his
right. A list rather than `random()`, because a random pick repeats itself often
enough to be noticed and a cycle can be asserted in a test. The cycle restarts
whenever he walks on.

Four details are load-bearing:

- **He lands back where he came in.** The keyframes end at a zero offset and the
  animation is removed on completion, so the model layer is never written to.
  Twenty cracks leave no drift, and the `PeekHitPanel` laid over the landed
  frame stays a valid click target throughout (it does not chase the hop, for
  the same reason it does not chase the slide-in).
- **A crack mid-flight picks him up where he is.** The replacing animation
  starts from the offset the *presentation* layer is showing and rises from
  there (`liveWhipOffset`), instead of snapping him to the ground to start over.
  It reads that offset only while our own hop is what is moving him — during
  `slide-in` the gap between presentation and model is the entrance, not the
  hop, and feeding it in would have the jump fight the walk-on.
- **Additive is what buys the sideways half.** The first flinch was confined to
  `position.y` because that was the one keypath that could fight neither the
  `wiggle` on `transform.rotation.z` nor the `slide-in` on `position.x` — a
  crack 200 ms after ⌘⌃Q plays all three at once. `isAdditive = true` on
  `position` is *summed onto* whatever else is driving it instead of replacing
  it, so he can leave to the side and still ride the slide-in.
- **The five seconds start over** (`schedulePeekExit`), exactly as a costume
  change restarts them — sliding out mid-flinch because the timer was armed
  before the crack would read as a bug. So the whip is also a way to *keep* him
  on screen: crack again and he stays.

The hops are measured in **fractions of his own height**, both axes off the
height, so the two cut-outs (461×363 and 455×362) flinch identically and he has
survived being resized three times (21% → 42% → 41% → ~28.5% of the screen
height, all on 2026-09-21) without the jump needing a second thought. The tallest is 26% of his
height; every point is clamped to the room he actually has on that side
(`EmojiAnimator.peekWhipHop`). The clamp is the safety net, not the author: the
overlay clips at both bezels, and a flinch that beheads the robot on the
projector — or walks him off the left edge — reads as a broken effect rather
than as a joke. Since he hangs from 82% of the height there is 18% of clearance
against the 0.26 × 0.285 ≈ 7.4% he needs (it was 10.7% at 41%, so every trim
of his height only widens the margin). `PeekWhipJumpTests` asserts both fits
are real and not the clamp doing the work, on three screen sizes and both
cut-outs, plus that a crack is one hop, that consecutive cracks go opposite
ways, and that he lands on the pixel he came in on however many times he is hit
mid-air.

The wiring is `WhipController.onRope`, set in `EffectsEngine.toggleWhip`, so the
overlay stays a rope and a sound and knows nothing about what listens.
`onCrack` stays for whoever wants every crack (nobody, since 2026-10-16), and
`cracked()` is still the **one funnel** every crack passes through — sound, then
listeners. `PeekWhipJumpTests.testEveryCrackGoesThroughTheFunnel` parses
`WhipOverlay.swift` to keep a third `playCrack()` call site from quietly
skipping the second half.

## ⚠️ A click types into the front app

`WhipMacro.sendCrackMacro` posts **Ctrl+C**, waits `interruptToTypeDelay`
(0.30 s, OpenWhip's number, so the interrupt lands before a new prompt), then
types one of `WhipMacro.phrases` (`FASTER`, `GO FASTER`, `Faster CLANKER`, …
verbatim from OpenWhip) and presses **Return**.

It goes to **whatever app has keyboard focus**, not to the whip. The panel is
non-activating, so showing the whip never steals focus — which is the point
(the terminal keeps it) and the hazard (so does anything else). Do not crack it
over a document you care about.

Typing is `CGEvent` + `keyboardSetUnicodeString`, not `osascript`: no process
spawn, and layout-independent.

## Dismissing it

Esc (its own `NSEvent` monitors, local and global), a second ⌃W, the menu row
again, or `GET /effect/stop-all` — the whip is an overlay like any other and
"silence everything" takes it down too (`EffectsEngine.stopAll`).

## Routes

| route | does |
|---|---|
| `GET /effect/whip`, `GET /test/whip` | toggle |
| `GET /effect/whip/crack`, `GET /test/whip/crack` | crack (a no-op while hidden) |

`GET /state` reports `whipShowing`.

## Parity with the original

`WhipPhysics` is a **byte-for-byte port of the operation order** inside
`update(now:)` — the same loop bounds, the same sequence of stretch / wall /
base-pose calls inside and outside the constraint-iteration loop. Reordering
them changes the rope's shape, so the order is load-bearing rather than
stylistic.

`tools/whip-parity/` holds the JS reference (`whip-physics.js`, extracted from
OpenWhip's `overlay.html`) and `generate-golden.js`, which runs it for a fixed
input sequence and writes `Tests/VictorEffectsTests/Resources/whip_golden.json`.
`WhipPhysicsTests.testSettleMatchesJSGolden` asserts the Swift simulation lands
on the same node positions. Change a constant in `P` and that test tells you the
rope is no longer OpenWhip's.

## 🙏 Pray — the second mode (⌃⇧W)

**A praying man in the whip's place** (2026-10-19, Victor: *"another feature
called pray instead of whip … exclusive to the whip mode … appearing instead of
the whip. And I click to play some short clip of a religious hymn"*).
`PrayOverlay.swift`; reached by **⌃⇧W** from the whip (the next mode; ⌃W then
brings him back until another is picked), the `🙏 Pray` menu row under `🔥 Whip`, or `GET /effect/pray` (`/effect/pray/sing` is the click, for checking it headless).

- **Exclusive.** Every `EffectsEngine.toggle…` (whip, pray, snap) puts the other
  two away first (`hideModes`) — one mode under the pointer at a time. Esc, the
  ⌃W, the menu row and stop-all take him down; ⌃⇧W moves on to 🫰 snap.
- **His hands follow the pointer**, only them (2026-10-20, Victor: *"instead
  of the man praying just … his two hands"*), eased (`PrayController.follow`,
  0.35 a frame) so they drift after it, centred on it, breathing ±2%. They are
  the figure drawn through a traced outline (`PrayView.handsOutline`, unit
  coordinates of the 265×324 cut-out — a new picture needs a new trace), so the
  man (200 pt tall) is placed by his hands and grows around those very pixels. Same panel
  (`WhipPanel`, `maximumWindow`) and the same `ZoomedPanel` mapping every frame,
  so ⌥-scroll and the ⌥⇧ zoom treat him exactly as they treat the rope.
- **A click plants a man, nothing is typed** (2026-10-20, Victor: *"when I
  click the hands remain there, and the human appears behind those hands … I
  can click multiple times to put multiple people praying"*). His hands stay
  on that spot and the pointer keeps a fresh pair, drawn over everyone, so the
  next click plants another (`PrayChoir`, at most 8 — the oldest makes room).
  Each one lives on his own clock: the rest of the man fades in around the hands (`manFadeInMs`,
  0.8 s), and at `lightDelayMs` (1.5 s) a ray of light drops on him from the
  top of the screen, slanting in from the upper left (`beamTiltDegrees`, 18°
  off the vertical; falls in 1.35 s, `beamFallMs`, three times the first try;
  shimmers; a halo over his head was the
  first try and went on 2026-10-20) and once it lands a golden glow comes up
  behind him, slower still (`glowUpMs`, 2 s). Man, hands, ray and glow fade out
  together over the last second (`fadeOutMs`) of his 9.5 s (`singMs`; 8 s until
  2026-10-20), and he is gone. Rays and glows are all drawn before any man.
  Planted men are kept in view points, so under the zoom they stay on the
  desktop spot they were planted on, like a window would.
- **One Ave Maria for all of them.** The first click starts the hymn at the
  tablet's level × 0.8 — `pray-hymn-tablet.mp3` when `assetsDir` has it, else
  the shipped `pray-hymn-long.mp3` (47 s, `Resources/CREDITS.md`).
  **They are the same Schubert and still not the same song to the room**
  (2026-10-21, Victor: *"it's another melody … find exactly the one the tablet
  snippet was cut from"*): the shipped take is Dorothea Fayne, the tablet's
  `09_ave_maria.mp3` is Barbara Bonney & Geoffrey Parsons (Warner, 1994) from
  16.57 s of the track. Shazam named it, a waveform cross-correlation placed
  it (0.6–0.9 per second), and `pray-hymn-tablet.mp3` is 47 s of that
  recording from that very point, at the tablet clip's loudness. Commercial,
  so a drop-in, in the private copyright ledger; it has its own name because
  the guard fails on a tracked file that shares a name with a ledger entry; a click while it sings does not restart it or add a voice, it
  only pushes its end out to that man's end — and takes back a fade already
  under way (0.3 s back up). It fades to silence over `hymnFadeMs` (1.2 s)
  ending exactly as the last man goes. Its own `AVAudioPlayer` in
  `PrayController`, not `playOverlapping`: a later click has to reach that one
  voice. Hiding him fades it in 0.2 s. Return and buttons 6/7 still mean
  nothing here — they are the whip's.
- **The picture is a drop-in** (`docs/assets-and-licences.md`): a stock
  illustration with its white background flood-filled away; without it he is a
  🙏 glyph. The hymn ships; if it is ever missing the old 9.5 s drop-in
  `pray-hymn.mp3` (the soundboard's Ave Maria, faded) stands in and simply
  ends early under a long choir, and without either the light falls in silence.
- **⌃⇧ held is also addons' emoji-picker hold**, and this tap eats the W before
  addons sees it, so the hold is never marked as a shortcut: a ⌃⇧ kept down past
  the picker's delay still opens it. A quick chord does not.
- **The real arrow is hidden while he — or the whip — is up** (`CursorHide`,
  shared with the heartbeat and the 🔍 glass; 2026-10-20). Each overlay takes
  one hide on show and gives exactly that back on hide, and re-asserts it at
  4 Hz within 100 pt of a screen edge, where the menu bar or the Dock would
  bring the arrow back.
- Counts as running for the 🛑 (`prayIsShowing`), and `GET /state` reports
  `prayShowing`.

## 🫰 Snap — the third mode (⌃⇧W ×2)

**The pointer becomes a hand that snaps its fingers** (2026-10-20, Victor:
*"another way to whip … a snap of the fingers … an animated transparent GIF …
on click it actually snaps"*). `SnapOverlay.swift`; reached by ⌃⇧W pressed while
🙏 pray is up, the `🫰 Snap` menu row, or `GET /effect/snap` (`/effect/snap/click`
is the click).

- **The hand IS the pointer**: glued, not eased like pray's hands, held by the
  point where thumb meets middle finger (`SnapView.hotspot`, unit coordinates
  of the 370×520 cut-out), 170 pt tall. Same `WhipPanel` + `ZoomedPanel`, same
  `CursorHide`.
- **A click snaps**: frame 0 of `finger-snap.png` is the hand at rest; a click
  plays every frame after it once, each for its own delay — a black silhouette
  (50 ms), a white one (60 ms), the finger down on the palm (450 ms) — then it
  rests again. A click mid-snap starts it over. A fan of nine short white lines
  flies off the fingertips (`burstMs`, 320 ms) and one of
  `finger-snap-1..3.mp3` plays at the tablet's level × 0.8, not Bluetooth
  compensated (the overlay keeps the link warm, like the whip). Nothing is typed.
- **The picture is a photo, shipped** (`Resources/CREDITS.md`): Wikimedia
  Commons' CC0 *Finger snapping impact frame.gif* (a real hand on a grey wall,
  with two anime-style impact frames), cut out with rembg/BiRefNet, cropped,
  the wrist faded out, saved as an **APNG** — a GIF has one bit of alpha and
  the cut-out's soft rim went jagged on a dark desktop. `SnapFrames` reads GIF
  and APNG alike, the **unclamped** delays (ImageIO clamps the plain key to
  100 ms, which would slow the 50–60 ms impacts down), so a nicer
  `finger-snap.gif` dropped into `assetsDir` wins without a build, as long as
  its frame 0 is the rest pose. Without either it is a 🫰 that pops.
- Counts as running for the 🛑 (`snapIsShowing`), stop-all takes it down, and
  `GET /state` reports `snapShowing`. `SnapFramesTests` covers the frame
  timing and that the corners are transparent.
