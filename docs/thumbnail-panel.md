# The Thumbnail Panel — the tablet's board on the Mac

Hold the **right ⌘** and the tile grid that lives on the tablet appears on a
screen the room is not looking at. Release it and it is gone. Click a tile and it
plays exactly as a tablet press would, because it is the same code path.

It exists because the tablet is not always in reach, and because a grid of 91
pictures is a faster way to find a sound than a menu of 91 words.

**The tablet has two pages, and so does this.** Add the **right ⇧** to the hold
and the panel shows the 🎬 video snippets instead — the tablet's page 2, in the
same order, with the same `#NN`.

| trigger | page |
|---|---|
| right ⌘ alone, held ≥ 180 ms | **effects** — the 91 soundboard tiles |
| right ⌘ **+ right ⇧**, either order, while ⌘ is down | **videos** — the 🎬 snippets |
| let go of ⇧ (⌘ still down) | back to the soundboard, **in place** |
| let go of ⌘ | hidden |
| ⌃, **⌥** or **left** ⇧ joining, or any key | cancelled / hidden — somebody else's shortcut |

**The second key was right ⌥ for one afternoon** (`782d89c`) and had to move:
right ⌘ + right ⌥ is **Wispr Flow's push-to-talk**, so every dictation raised a
soundboard over the screen. ⌥ is now in the cancelling set with ⌃ — either hand,
no device-bit distinction — which is what keeps the panel out from under a key
somebody is holding to talk. `testWisprPushToTalkNeverOpensThePanel` is that
promise, in both orders.

| file | what it is |
|---|---|
| `ThumbnailPanelController.swift` | the feature: `PanelPage`, `PanelHoldRule`, the hold timer, show/hide/switch, reload |
| `ThumbnailPanel.swift` | the window — and it holds **both** grids |
| `ThumbnailPanelPlacement.swift` | **which screen and what frame** — pure, unit-tested |
| `ThumbnailGridView.swift` | page 1: columns, cell size, order |
| `TileView.swift` | one sound tile + `TileImageCache` |
| `SoundboardPress.swift` | what a press *means* on page 1 |
| `TilesManifest.swift` | the tile list itself (`docs/http-api.md`) |
| `VideoGridView.swift` | page 2: the 16:9 grid, `VideoTileView`, `VideoThumbCache` |
| `AddonsVideos.swift` | page 2's data and press: `AddonsClient`, `VideosManifest`, `VideoPress` |

## The trigger: right ⌘, held ≥ 180 ms

One rule inside `EffectsHotkeyTap` — the same tap that owns ⌃W, because a tap is
a shared fragile resource and three of them would mean three re-enable paths and
three Accessibility failures to explain.

- `.flagsChanged` with `keyboardEventKeycode == 54`
  (`EffectsHotkeyTap.VK_RIGHT_COMMAND`). **Left ⌘ is 55 and is deliberately not
  matched**, so every left-hand ⌘ shortcut is untouched by this feature.
- **Alone, except for the right ⇧**: `EffectsHotkeyTap.decideModifier` arms only
  when ⌃ and ⌥ are absent and any ⇧ that is down is the **right** one, and
  **cancels** if one of the others joins mid-hold. ⌃⌘, ⌘⌥ and left-hand ⌘⇧ are
  shortcut layers other apps own — the panel must not appear underneath somebody
  else's chord. Caps lock and fn are not in the set: caps lock is a latch
  somebody may be sitting on for an hour.
- **Left ⇧ (56) and right ⇧ (60) are a real distinction, and `CGEventFlags`
  cannot make it.** `.maskShift` says only that *a* ⇧ is down. The keycode
  on a `.flagsChanged` names the key that **moved**, which answers the case where
  ⇧ arrives second — but when right ⌘ arrives second the question is which ⇧ is
  still **held**, and the only thing that knows is the device-dependent bits
  (`NX_DEVICEL/RSHIFTKEYMASK` = 0x02 / 0x04, `EffectsHotkeyTap.DEVICE_LEFT_SHIFT` /
  `DEVICE_RIGHT_SHIFT`) riding in the raw flags. A `.maskShift` carrying
  **neither** bit — a synthesised event, a remapped key — is deliberately read as
  the left one: the safe fallback is the behaviour this feature already had
  (⌘⇧ cancels), never a board appearing under somebody's chord.
- **⌥ gets no such reading.** It was worth telling the two ⌥ keys apart only
  while ⌥ *was* the page switch; now that the chord belongs to Wispr Flow, both
  of them cancel and there is one less device bit to be wrong about.
- Down arms a `holdDelay` (**180 ms**) timer on the main queue; firing it shows
  the panel. Up hides it again.
- A `keyDown` while right ⌘ is held means the user is typing a shortcut, not
  asking for the panel: before the timer fires it **cancels**; after it fires it
  **hides**. The panel does not fight a shortcut — right-⌘C and right-⌘V keep
  working.
- **The rule never swallows anything** (`onRightCommand` /
  `onKeyWhileRightCommand` are notified and the event passes through).

The decision itself is a pure state machine —
`ThumbnailPanelController.PanelHoldRule.apply(_:to:)`, six `Event` cases
(`rightCommandDown`, `holdTimerFired`, `rightCommandUp`, `rightShiftDown`,
`rightShiftUp`, `keyWhileRightCommand`) turning a `State` (`enabled`,
`holdArmed`, `shownByHold`, `page`) into `Action`s (`armHoldTimer`,
`cancelHoldTimer`, `show(page)`, `setPage(page)`, `hide`). It is a rule and not a
tangle of booleans inside the tap callback because the interesting cases — a key
pressed at 179 ms, a release that arrives before the timer, a panel already open
from the menu, ⇧ pressed at 90 ms and let go at 400 — are exactly the ones that
are miserable to reproduce by hand. `ThumbnailPanelHoldTests` covers them, and it
has to: the gestures themselves cannot be checked without synthesising input.

Three things the rule is careful about:

- **`show` carries its page.** The action is a complete instruction rather than
  something the caller reads back off the state, so the two can never disagree.
- **The page is a state of the hold, not a mode.** Every end of a hold resets it
  to `effects`, so ⇧ is *held* and never latched — the next gesture always starts
  on the soundboard.
- **Either order is one ordering.** When right ⇧ is already down as right ⌘
  arrives, the **tap** synthesises the `rightShiftDown` edge straight after the
  `rightCommandDown` (it can see the held bits in the flags), so the rule only
  ever has to understand one sequence and the panel appears *already* on page 2
  rather than flickering through page 1.

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

### Hugging the grid

The frame above is the *width* rule. The height is then trimmed to what the
grid actually draws: `ThumbnailGridView.metrics(fitting:count:columns:)` answers
a `hugHeight` (**rows × cell + gaps + padding × 2**) and
`ThumbnailPanelPlacement.hug(_:toContentHeight:anchor:)` shortens the frame to
it.

Cells are square and fit both ways, so with 13 columns the **width** is almost
always what binds — and the leftover height used to be black band above and
below the rows. On the built-in retina the solo frame is 1152 × **719** and the
grid is 7 rows of 81 pt: 1152 × **623**, so 96 pt of nothing were being framed.

- It only ever **shrinks**. A grid taller than its frame is the shrunk-cell case
  and wants every point it was given.
- The `anchor` comes from the placement: **`.bottom`** for the single-screen
  corner layout (the bottom-right corner must not move — only the top comes
  down) and **`.centred`** for the filled-screen layout.
- Hugging is **stable**: re-measuring at the hugged height gives the same cell,
  so a second show does not creep the board smaller. `testHuggingIsStable`.

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

It **slides in from the right edge of its screen** — parked at
`visibleFrame.maxX` at its final size, then `animator().setFrame` to the target
over `slideInDuration` (**0.20 s**, ease-out) while `alphaValue` goes 0 → 1.
Only the *origin* animates: the content view never resizes, so the 91 tiles are
laid out once instead of on every frame. The fade is there because on a
multi-screen desk the parking spot is over the neighbouring screen.

Out is `slideOut(to:)` — **0.12 s**, ease-in, starting from wherever the window
visually is, because releasing the key before the board has landed is the normal
case. A `slideGeneration` counter guards the teardown: a completion that finds a
newer generation has been overtaken by a show and must **not** order the window
out, or a fast release-and-re-hold leaves a panel that is invisible but
`isVisible`. A `+0.25 s` fallback runs the same teardown in case the completion
handler never arrives. `hideNow()` is the un-animated panic path (the feature
switched off).

Its level sits **one below** the click-through effects overlay, so an effect
still draws over it on the built-in screen while clicks still reach the panel.
`collectionBehavior` is `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
.ignoresCycle]` — it must appear on whichever Space is in front, without
dragging anything along. Hover highlights come from an `NSTrackingArea`, which
works without key status.

**The cursor over the panel is an arrow and never changes shape** (`PanelCursor`,
pinned from `ThumbnailGridView`, `TileView` and `PanelContentView`): being the
window on top does not win the pointer's shape, so with no answer from us the
window *underneath* answered — an I-beam over a terminal, a pointing hand over a
browser link, a pointer reacting to a window the user cannot see. The option that
buys it is **`.cursorUpdate`** on the tracking area (plus `.activeAlways`, since
this app is never the active one); all three views carry it because the topmost
tracking area under the pointer is the one AppKit asks. It is set imperatively
with `NSCursor.set()` and **not** through `addCursorRect`/`resetCursorRects`,
because cursor *rects* are dispatched to the key window only and this panel never
becomes key — the rect would never fire once. That is the same scar
`BreakTimerOverlay` carries in the other app. It is re-asserted on `mouseMoved`
as well as on enter, because a panel that appears *under* a stationary mouse (the
normal case for a hold gesture) delivers moves without an enter. `releaseCursor()`
still hands ownership back in three places — `mouseExited`, `finishSlideOut` and
`hideNow` — since an imperative `set()` bypasses AppKit's own restoration and a
window ordering out owes the view no `mouseExited`. `PanelCursor` logs only the
*corrections* (it found something other than an arrow and overrode it), never the
confirmations, or one hover would fill the log. `ThumbnailPanelCursorTests` is the
guard: it parses these three files with their comments stripped, so deleting
`.cursorUpdate` from one options array fails the build instead of silently going
back to borrowing the cursor.

## The grid (page 1)

`ThumbnailGridView` lays the tiles out in **`tiles.json`'s own array order**,
`columns` wide — never sorted by `n` and never re-ordered, because the number
under a finger on the tablet has to be the number in the same place here. Row 0
is the top row.

Cells are square and sized to fit **both ways**: `cellSide` is the smaller of
what the width and the height allow, floored at 24 pt. The plan reached for a
scroll view when the rows overflow; a panel you hold a key to see is one you
never get to scroll, so shrinking the cell is what keeps every tile reachable in
the one glance the gesture affords. That arithmetic lives in the pure
`ThumbnailGridView.metrics(fitting:count:columns:)`, because the panel has to
ask it *before* there is a window to measure — see **Hugging the grid** above.

`TileView` draws each tile out of `CALayer`s rather than in `draw(_:)`,
because the playing border pulses and the hover mark fades — both one animation
on a layer, versus a redraw loop in a drawing method:

- the picture, aspect-fill, corners clipped;
- `#NN` top-left;
- the optional `label` centred across it;
- a `↻` badge when the tile is `restartable`;
- **⭐ top-right when the tile also animates the desktop** — the tablet's badge,
  reproduced: the solid `★` glyph (not the emoji, which arrives as a colour
  sprite with its own metrics), amber `#FFC400` so it is the only non-white,
  non-green mark on a tile, a black shadow so it survives a bright thumbnail,
  right-aligned against a 5 % margin and set at 22 % of the tile — `starSizeRatio`
  / `starMarginRatio`, the tablet's own `w * 0.22f` and `width * 0.05f`. The
  corner was the last free one (`#NN` top-left, `↻` bottom-left, the usage dots
  bottom-right on the tablet). **The set is `EffectsCatalog.effectName(forAsset:)`
  answering in process** — the same call `GET /tiles` stamps the tablet's rows
  with, so the two boards cannot star different tiles. There is no second list
  here and no HTTP hop to our own port. Until this existed the panel was the one
  surface drawing the board without the star: same grid, same `tiles.json`, a
  star on one screen and not on the other;
- **playing** = a red border whose opacity pulses, `playingBorderWidth` thick;
- **hover** = the **gutter around the cell filled bright green** (`#39FF14`), and
  **the picture does not move**. The mark reaches exactly one `gap` outwards
  (`highlightGutter`), i.e. up to the neighbours' edges, so the whole black
  channel around the tile lights up with no hairline left down the middle of it;
  at the edges of the grid it eats 6 of the 10 pt of `padding`, which is the same
  mark seen from outside. It is painted by `gutterLayer`, the FIRST sublayer, so
  the artwork always sits on top of it — a frame around the picture, never a wash
  over it. The tile is raised by `zPosition` while marked, because tiles are
  siblings and the later ones draw on top: without it the fill would be clipped
  away on two sides out of four. `zPosition` and not a reorder of the subviews,
  since the grid lays out by the *index* of its `tileViews` array. The view's own
  layer must **not** set `masksToBounds` — a layer clips its sublayers to itself,
  and this one deliberately paints outside its bounds;
- **mouse-down** = the same fill in red (`pressColor`), which is now the only
  press feedback there is;
- one decision makes both marks (`updateHighlight`), because releasing a press
  has to fall back to the hover the mouse is still inside rather than to nothing.

What was here until 2026-09-12 was the opposite arrangement — a 5 pt white ring
over a 7 pt dark rim, a 20 % wash, a 1.04 scale-up and a white glow, all *inside*
the tile — and it had two faults that a bigger ring could not fix. The scale
**moved the artwork** a pixel or two under the pointer, which on a board of 91
photographs reads as the picture twitching rather than as "the mouse is here";
and every version of the outline was paid for out of the picture, on a tile only
~80 pt across. The gutter is dead black space that belongs to nobody, it is
already the full width of the `gap`, and lighting it up costs the artwork
nothing. `ThumbnailPanelCursorTests` reads both tile views' source for
`setAffineTransform` and for a hover shadow, because nothing in the compiler
stops either from creeping back.

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

## 🎬 The video page

The tablet's page 2, on the Mac. Same list, same order, same numbers — because
a snippet called out by its `#NN` in the room has to be in the same place on
whichever board is nearer.

### Where the list comes from

**`GET <addonsBaseURL>/videos`, on the addons app** (55123, `VideoLibrary`).
That route and the two play routes are addons-local and deliberately **not**
proxied back to 55124: the library, IINA, the display arrangement and the ~60 s
auto-kill all live over there, and a proxy hop would only add a way for the two
halves to disagree about what is on the projector. This is therefore the one
place this app dials *out* — `AddonsClient`, and `addonsBaseURL` is an
`EffectsConfig` key (default `http://127.0.0.1:55123`, empty = the page is off)
so a public repo never hardcodes another machine's port.

- **Every entry carries its picture inline**, as a base64 JPEG, exactly as the
  tablet receives it. One call for the list *and* the thumbnails is what keeps
  the two from drifting and what lets the page paint with no per-tile fetch.
- **Refreshed on every show, cached for the session** (`VideosManifest`). Refreshed
  because a clip added with the `add-training-video` skill has to appear without
  restarting this app; cached because the refresh is allowed to fail — a Mac whose
  addons app is restarting still draws the board it drew a minute ago rather than
  replacing eighteen tiles with an error. A **200 carrying an empty list** is a
  real answer (an addons app with no `videos/`) and does replace the cache.
- **Synchronous, capped at 1.5 s.** The panel cannot be sized until the list is
  known, and a background fetch would mean a board that appears empty and resizes
  itself under a key somebody is still holding. Over loopback it costs
  milliseconds; the one case that costs the whole 1.5 s is addons being down, and
  that is the case that then draws the single **`no videos (addons down?)`** tile
  naming the base URL it tried. "The panel is up" and "the panel is up and the
  other app is down" have to be tellable apart at a glance, from a metre back,
  with a key still held.

This is the one place the rule *"never introduce a dependency that makes one app
wait for the other"* is bent, and it is bent on purpose and with a timer: the
wait is bounded, it happens only on this page, and its failure mode is a tile
rather than a hang.

### The layout

Mirrored from `MainActivity.renderVideoTiles`, not invented:

| | page 1 (sounds) | page 2 (videos) |
|---|---|---|
| columns | 13 (`tiles.json`) | **5** (`SNIPPETS_PER_ROW`) |
| shape | square | **16:9** |
| width vs a sound tile | 1× | **2.6×** (13 ÷ 5) |
| `padding` / `gap` | 10 / 6 | the same — they are one decision |
| `#NN` | white bold at 10% of the tile | white bold at 10% of the **sound** tile |
| label | optional word, centred | **the title**, centred across the picture, at 20% of the tile |
| ⭐ | top-right when the asset animates the desktop | — (videos are not in the catalogue) |
| hover / press | green / red fill of the surrounding gutter — the same mark on both pages, and neither moves the picture ||

- **The badge is scaled off the soundboard tile, never off the video tile it is
  drawn on.** `TileNumberBadge` on the tablet says the same thing in the same
  words: a video tile is nearly three times wider, and scaling the badge with it
  would produce a different badge, not the same one. `VideoGridView.badgeUnit`
  re-derives the sound cell for the same panel size to get it.
- **`#NN` is the tile's place in the Mac's order**, 1-based, nothing else — so it
  renumbers itself when a clip is added, and a row this app had to drop (no `id`)
  closes up behind it rather than leaving a hole in the badges.
- **The title sits across the picture, not under it.** A frame grabbed at the
  snippet's own start second is rarely legible enough to name the clip on its own,
  and a caption under the picture would cost a line of height on every row.
- **And it is set at the tablet's own size: 20 % of the tile's width**
  (`VideoTileView.titleSizeRatio`), bold white with a black shadow, centred. It
  was 10 %, from a comment reading "the tablet's 48 px on a ~494 px cell" — but
  `textSize = 48f` on a Kotlin `TextView` is **sp, not px**, and on the board
  (density override 200, i.e. 1.25, times Victor's 1.3 font scale) that is ≈ 78 px
  of type on a cell of (2000 − 2×13 − 4×15) ÷ 5 ≈ 382 px. The panel had been
  drawing the titles at half the size of the ones in the room. A ratio and never
  a point size, for the same reason as the `#NN` badge: the cell is whatever five
  across leaves on the screen the panel opens on.
- **Tile widths are whole multiples of 16** (`widthQuantum`). Not tidiness — it is
  what makes hugging *stable*: the panel measures the grid, shortens its frame to
  the answer and measures again at that height, and a cell whose height was
  `floor(width × 9/16)` loses the fraction and comes back a point smaller, so a
  second show creeps the board down. On a multiple of 16 the height is exact.
  (Page 1 carries the same scar, solved there by writing ⅔ as a division.)
- It fits **both ways** like page 1 — a short frame shrinks the cell rather than
  overflow, because a panel you hold a key to see is one you never get to scroll.

### Switching pages

`PanelHoldRule` answers `.setPage` and the controller does it **in place**: no
hide, no show, no slide. The key is still held and the board has to read as
changing its mind, not as leaving and coming back. The frame does move, because
the two pages hug to different heights — set, never animated, and against the
*remembered* placement (`lastPlacement`) rather than a fresh screen choice, which
would be free to pick a different screen mid-gesture. Both grids live in the
panel for the life of the process with one hidden, so the swap never has to build
eighteen views under a key that is already down.

### What a video press does

`VideoPress`, a port of the tap half of the tablet's `onSnippetTouch`:

1. **Tap** → `GET <addonsBaseURL>/video/play/<id>`, which answers
   `{ok,startSeconds,durationMs}` and puts the clip fullscreen in IINA on the
   Retina. `durationMs` is the shorter of what is left of the clip and addons'
   auto-kill window.
2. **Tap the tile that is playing** → `GET /video/stop`. The playing tile is its
   own stop button, exactly as on the tablet — a tile that stopped the clip there
   and replayed it here would be a bug in the middle of a session.
3. **A different tile** replaces rather than stops: addons kills the previous IINA
   before relaunching, so a stop sent from here could only land *after* the new
   play.
4. The red border clears at `durationMs + 100 ms`. Nothing polls for the end —
   that deadline IS the one addons armed. Completion timers are **outvoted, not
   cancelled**, the same guard `SoundboardPress` carries.

The tablet's *other* gesture on that tile — hold three seconds for the soundtrack
alone — is deliberately not here: it is a gesture for a finger, and this panel is
already being held open with the other hand.

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

Menu rows: **`Show tablet panel on right-⌘ hold (right ⇧ = videos)`** (the
checkbox), **`Show
tablet panel now`** (a toggle, for a mouse-only check), **`Reload tiles.json`**.

The checkbox is stored as `MenuBar.kPanelEnabled` = `ThumbnailPanel.enabled`
(`UserDefaults`, domain `ro.victorrentea.victor-effects`) and
read as `object(forKey:) as? Bool ?? true` — **default on**. `bool(forKey:)`
answers `false` for a key nobody has written, which is exactly how a feature
ships switched off for everyone who never touched it.

| hook | does |
|---|---|
| `GET /test/thumbnail-panel` | show it for `testShowSeconds` (**5 s**) and answer `{ok, page, screen, primary, overlayScreen, frame:{x,y,w,h}, tiles, seconds}` — the headless way to check the placement rule on the rig you are sitting at, and to tell "the panel is up" from "the panel is up and empty" |
| `…?page=videos` | the same on page 2. `tiles` must match `curl -s 127.0.0.1:55123/videos \| jq '.videos\|length'` — the two-command check that the fetch, the parse and the grid agree |
| `GET /test/thumbnail-panel/hide` | hide it early |
| `GET /test/thumbnail-panel/press/<n>` | press tile `n` exactly as a click does → `{ok, n, asset, action, durationMs}`, or `unknown-tile`. The panel need not be visible: the press path is the sound semantics, not the window |
| `…/press/<n>?page=videos` | press video tile `n` → `{ok, n, id, action, durationMs}`, `unknown-video`, or `addons-down`. It really starts IINA — **stop it** with `curl 127.0.0.1:55123/video/stop` or it sits fullscreen until the auto-kill |

`page` is `effects` unless the query says `videos`; an unknown value falls back to
`effects` rather than 404, because these are hooks typed into a shell and a typo
answering "no such route" is not a better error.

All three answer **503 `{"ok":false,"reason":"no-panel"}`** when no panel is
wired, rather than 404: the route exists, the feature is not attached.
