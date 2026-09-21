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

## Turning it on

**⌃W** toggles it, globally, **swallowed** — the key does not reach the app
underneath. That is the only rule in `EffectsHotkeyTap` that returns `nil`, and
the only reason the tap needs **Accessibility** rather than Input Monitoring.

The consequence is deliberate and worth knowing: **⌃W stops deleting the word
backwards** in terminals and editors for as long as this app runs.

**⌘⌃W is not bound** and never will be. The rule is
`hasCtrl && !hasCmd && !hasOpt && !hasShift` (`EffectsHotkeyTap.decideKey`), and
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
soundboard's own level at `crackVolumeFactor` (0.8) — at full level the crack
genuinely startles a room, which is not the joke.

Cracks are **not** Bluetooth-compensated (`bluetoothCompensated: false`): the
overlay holds the A2DP link warm with `BluetoothOutput.startContinuousWarm()`
for exactly this reason, so a crack has zero spin-up lag and adding the
compensation delay would only make it late.

## The mascot bolts

Every crack — flicked, Return'd, thumb-buttoned or `GET /effect/whip/crack` —
sends the ⌘⌃Q mascot **scrambling**, if he happens to be on screen
(`EmojiAnimator.whipClaudePeek`). The whip already scolds the agent in the
terminal; this is the same joke told to the room instead of to the shell, and
the robot standing still through a crack aimed at him was the thing that read as
missing.

**It is a scamper, not a hop.** The first version (2026-09-21, morning) went
straight up and came straight down, once — a man on a pogo stick, not somebody
who has just been stung. Being burnt makes you run *away*, and away is not a
direction you pick in advance: he now takes **four hops in four directions**
(`peekWhipHopShape`) — out to the right, back the other way, over his own
take-off point and past it to the left, then home — and finishes on a last
startled little pop. The route is deliberately lopsided, far right and only a
short way left, because `claudePeekFrame` leaves a screen's worth of room on his
right and only its 4.5% inset on his left.

Four details are load-bearing:

- **He lands back on the same pixel.** Every hop is an offset from where he
  stands, the sequence starts *and* ends at zero, and the animation is removed
  on completion, so the model layer is never written to. Twenty cracks in a row
  leave no drift, and the `PeekHitPanel` laid over the landed frame stays a
  valid click target throughout (it does not chase the scamper, for the same
  reason it does not chase the slide-in).
- **Additive is what buys the second axis.** The old flinch was confined to
  `position.y` because that was the one keypath that could fight neither the
  `wiggle` on `transform.rotation.z` nor the `slide-in` on `position.x` — a
  crack 200 ms after ⌘⌃Q plays all three at once. `isAdditive = true` on
  `position` is *summed onto* whatever else is driving it instead of replacing
  it, so he can run in both directions and still ride the slide-in rather than
  teleporting to his landing spot.
- **The hops are measured in fractions of his own height, both axes.** Off the
  height and not one axis off each, so the two cut-outs (461×363 and 455×362)
  run the same route and the effect never tells the room which costume is on
  duty. Off the icon and not in points because he doubled in size once already
  (2026-09-21, 21% → 42% of the screen height).
- **The five seconds start over** (`schedulePeekExit`), exactly as a costume
  change restarts them — sliding out mid-scramble because the timer was armed
  before the crack would read as a bug. So the whip is also a way to *keep* him
  on screen: crack again and he stays.

The apex is **15% of his own height** and every point is clamped to the room he
actually has on that side (`EmojiAnimator.peekWhipPath`). The clamp is the
safety net, not the author: `claudePeekFrame` hangs his head at 93% of the
height and insets him by 4.5% of the width, the overlay clips at both bezels,
and a flinch that beheads the robot on the projector — or walks him off the left
edge — reads as a broken effect rather than as a joke. 15% × 42% ≈ 6.3% of the
height, just inside the 7% of clearance; the leftmost hop is 14% of his height
against ~16.5% of room on the tightest screen. `PeekWhipJumpTests` asserts both
fits are real and not the clamp doing the work, on three screen sizes and both
cut-outs, plus that the route moves sideways at all, takes off four times and
lands where it started.

The wiring is `WhipController.onCrack`, set in `EffectsEngine.toggleWhip`, so the
overlay stays a rope and a sound and knows nothing about what listens. Inside
it, `cracked()` is the **one funnel** every crack passes through — sound, then
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
