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

## The mascot flinches

Every crack — flicked, Return'd, thumb-buttoned or `GET /effect/whip/crack` —
makes the ⌘⌃Q mascot **jump**, if he happens to be on screen
(`EmojiAnimator.whipClaudePeek`). The whip already scolds the agent in the
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
