# The Thumbnail Panel — the soundboard on the Mac

Hold the **right ⌘** and the tile grid that lives on the tablet appears on a
screen the room is not looking at. Release it and it is gone. Click a tile and
it plays exactly as a tablet press would, because it is the same code path.

It exists because the tablet is not always in reach, and because a grid of 91
pictures is a faster way to find a sound than a menu of 91 words.

| file | what it is |
|---|---|
| `ThumbnailPanelController.swift` | the feature: `PanelHoldRule`, the hold timer, show/hide, reload |
| `ThumbnailPanel.swift` | the window |
| `ThumbnailPanelPlacement.swift` | **which screen and what frame** — pure, unit-tested |
| `ThumbnailGridView.swift` | the grid: columns, cell size, order |
| `TileView.swift` | one tile + `TileImageCache` |
| `SoundboardPress.swift` | what a press *means* |
| `TilesManifest.swift` | the tile list itself (`docs/http-api.md`) |

## The trigger: right ⌘ held ≥ 180 ms

One rule inside `EffectsHotkeyTap` — the same tap that owns ⌃W, because a tap is
a shared fragile resource and three of them would mean three re-enable paths and
three Accessibility failures to explain.

- `.flagsChanged` with `keyboardEventKeycode == 54`
  (`EffectsHotkeyTap.VK_RIGHT_COMMAND`). **Left ⌘ is 55 and is deliberately not
  matched**, so every left-hand ⌘ shortcut is untouched by this feature.
- Down arms a `holdDelay` (**180 ms**) timer on the main queue; firing it shows
  the panel. Up hides it again.
- A `keyDown` while right ⌘ is held means the user is typing a shortcut, not
  asking for the panel: before the timer fires it **cancels**; after it fires it
  **hides**. The panel does not fight a shortcut — right-⌘C and right-⌘V keep
  working.
- **The rule never swallows anything** (`onRightCommand` /
  `onKeyWhileRightCommand` are notified and the event passes through).

The decision itself is a pure state machine —
`ThumbnailPanelController.PanelHoldRule.apply(_:to:)`, four `Event` cases
(`rightCommandDown`, `holdTimerFired`, `rightCommandUp`, `keyWhileRightCommand`)
turning a `State` (`enabled`, `holdArmed`, `shownByHold`) into `Action`s
(`armHoldTimer`, `cancelHoldTimer`, `show`, `hide`). It is a rule and not a
tangle of booleans inside the tap callback because the interesting cases — a key
pressed at 179 ms, a release that arrives before the timer, a panel already open
from the menu — are exactly the ones that are miserable to reproduce by hand.
`ThumbnailPanelHoldTests` covers them.

The tap needs **Accessibility** because of ⌃W, not because of this — a
listen-only tap would do for the panel alone. Without the grant the tap is not
installed, the menu shows its ⚠️ row, and `AppDelegate` retries every 30 s — the
**`Show tablet panel now`** menu row is the fallback in the meantime.

`GET /state` and `/ping` report `panelMonitor`: whether the tap is actually
running *and* the checkbox is on.

## Which screen

`ThumbnailPanelPlacement.choose(screens:mouse:)` is pure and takes
`PanelScreen` values (name, `visibleFrame`, `isPrimary`, `isOverlay`) rather
than `NSScreen`, because `NSScreen` cannot be constructed and the layouts worth
testing are exactly the ones the machine writing the rule does not have.

- **One screen** → `soloNumerator`/3 (= ⅔) of `visibleFrame` each way,
  bottom-right, 16 pt in (`margin`). It has to share the screen with whatever is
  being shown, so it stays out of the menu bar and out of the top-left of a
  slide. (The fraction is written as a division rather than `0.666…`: on a 1728
  pt screen the decimal floors to 1151 and the division gives 1152, one pixel of
  arithmetic noise a test asserting "two thirds" would trip over.)
- **Several** → **never the overlay screen** (`isOverlay`, i.e.
  `Screens.overlayScreen()` — the built-in retina, the one mirrored to the
  room), and among the rest **prefer a non-primary** one. Tie-break: the screen
  under the mouse, else the largest. Frame = that screen's `visibleFrame` inset
  by 24 pt (`inset`).
- Fallbacks, in order: if every screen is the overlay screen, use them all; if
  the only non-overlay screen *is* the primary, use it.

**Why not the simpler "not the main screen".** At home the built-in retina is
both primary and projected, so the two rules agree. At a venue the external is
made primary while the retina is mirrored to the room — and there the literal
"non-main" rule puts the soundboard on the projector, in front of the audience,
which is the one place it must never be.

## The window

`ThumbnailPanel: NSPanel`, `[.borderless, .nonactivatingPanel]`, never key and
never main, `hidesOnDeactivate = false`, not released when closed. Shown with
`orderFrontRegardless()` and hidden with `orderOut(nil)` — **never**
`makeKeyAndOrderFront`, so showing it does not take focus from whatever is being
demonstrated.

Its level sits **one below** the click-through effects overlay, so an effect
still draws over it on the built-in screen while clicks still reach the panel.
`collectionBehavior` is `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
.ignoresCycle]` — it must appear on whichever Space is in front, without
dragging anything along. Hover highlights come from an `NSTrackingArea`, which
works without key status.

## The grid

`ThumbnailGridView` lays the tiles out in **`tiles.json`'s own array order**,
`columns` wide — never sorted by `n` and never re-ordered, because the number
under a finger on the tablet has to be the number in the same place here. Row 0
is the top row.

Cells are square and sized to fit **both ways**: `cellSide` is the smaller of
what the width and the height allow, floored at 24 pt. The plan reached for a
scroll view when the rows overflow; a panel you hold a key to see is one you
never get to scroll, so shrinking the cell is what keeps every tile reachable in
the one glance the gesture affords.

`TileView` draws each tile out of `CALayer`s rather than in `draw(_:)`,
because the playing border pulses and a press scales — both one animation on a
layer, versus a redraw loop in a drawing method:

- the picture, aspect-fill, corners clipped;
- `#NN` top-left;
- the optional `label` centred across it;
- a `↻` badge when the tile is `restartable`;
- **playing** = a red border whose opacity pulses;
- hover = a light wash, mouse-down = a slight scale-down.

Pictures are decoded by `TileImageCache`: **thumbnails via `ImageIO`**, not full
decodes. The originals run to 2238 px square and there are 91 of them — several
hundred MB of bitmap for tiles about 140 pt across. Loading happens off the main
thread, once per path (`inFlight` collapses duplicate requests), and the result
is kept for the life of the process (`TileImageCache.shared`, cleared by
**`Reload tiles.json`**). A missing image file degrades to a plain tile rather
than an empty grid; a missing manifest shows one line naming the `soundsDir` it
looked in.

The red border **follows the sound, not the click** (`setPlaying(asset:)`): a
tile whose clip ended on its own has to stop pulsing without anyone pressing
anything.

## What a press does

`SoundboardPress` is a **port of the tablet's own press semantics**
(`SfxAdapter.toggle` / `startOnMac` / `completionStopUrl`), not an invention: the
same grid is on a tablet in the room, and a tile that stops the sound there but
restarts it here would be a bug in the middle of a session.

Everything goes through `EffectsRouter.dispatch` **directly on the main thread**
— the same switch the HTTP path runs, minus the socket:

1. Re-pressing the tile that is playing **stops** it — unless it is
   `restartable` (#53 money), which falls through and replays from the top.
2. `stopAll()`: `/alarm/stop` first **if the siren was the playing tile** (its
   overlay is a toggle, so a blanket stop leaves it up), then
   `/effect/stop-all`.
3. `/sound/play/<asset>?vol=<current>` — a non-200 answers `missing-sound` and
   stops there.
4. `/alarm/start` for the siren, else `/sound/pressed/<asset>` — the Mac owns
   the sound→effect map, so the press is reported by bare filename and the map
   decides whether a visual is paired with it.
5. At `durationMs + 100 ms`: clear the border and fire `/alarm/stop` or
   `/sound/stopped/<asset>`.

The order carries a scar the tablet earned first: firing `stop-all` and the
paired effect from two threads lets the stop land *after* the effect and wipe
it. Everything here is sequential for that reason.

Completion timers are **not cancelled, they are outvoted**: every press bumps a
`generation` and a late completion that finds a newer one does nothing — the
same effect as the tablet's `if (playingPosition == position)` guard, without a
cancellable handle to keep in sync.

## Menu and test hooks

Menu rows: **`Show tablet panel on right-⌘ hold`** (the checkbox), **`Show
tablet panel now`** (a toggle, for a mouse-only check), **`Reload tiles.json`**.

The checkbox is stored as `MenuBar.kPanelEnabled` = `ThumbnailPanel.enabled`
(`UserDefaults`, domain `ro.victorrentea.victor-effects`) and
read as `object(forKey:) as? Bool ?? true` — **default on**. `bool(forKey:)`
answers `false` for a key nobody has written, which is exactly how a feature
ships switched off for everyone who never touched it.

| hook | does |
|---|---|
| `GET /test/thumbnail-panel` | show it for `testShowSeconds` (**5 s**) and answer `{ok, screen, primary, overlayScreen, frame:{x,y,w,h}, tiles, seconds}` — the headless way to check the placement rule on the rig you are sitting at, and to tell "the panel is up" from "the panel is up and empty" |
| `GET /test/thumbnail-panel/hide` | hide it early |
| `GET /test/thumbnail-panel/press/<n>` | press tile `n` exactly as a click does → `{ok, n, asset, action, durationMs}`, or `unknown-tile`. The panel need not be visible: the press path is the sound semantics, not the window |

All three answer **503 `{"ok":false,"reason":"no-panel"}`** when no panel is
wired, rather than 404: the route exists, the feature is not attached.
