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
