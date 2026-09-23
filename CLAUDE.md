# victor-effects — agent notes

The presentation-effects half of `victor-macos-addons`: overlays, the soundboard,
the whip, the HTTP API on **55124**. The addons app keeps **55123** and proxies
every effect/sound route here, so local tools and the tablet never learned a new
port.

## Where to read first

| zone | file | you want it for |
|---|---|---|
| the effect catalogue | `docs/overlay-effects.md` | what each `/effect/<name>` draws and how long it lives |
| 🔥 whip | `docs/whip.md` | ⌃W, the crack macro, the OpenWhip parity harness |
| sound routing | `docs/sound-routing.md` | `soundsDir`, the manifest, Bluetooth compensation |
| HTTP contract | `docs/http-api.md` | every route, the webhook, `tiles.json` |
| thumbnail panel | `docs/thumbnail-panel.md` | the right-⌘ soundboard grid |
| testing | `docs/testing.md` | the `/test/*` hooks |
| deploy | `docs/deployment.md` | build-app.sh, LaunchAgent, TCC, code signing |

**Read the zone's doc BEFORE touching its code.** Most of the constants in there
were arrived at by being wrong in front of a room first; the details are
load-bearing, not commentary. When you change something, edit that zone file —
this one only routes.

## Rules

- **Deploy after any code change**: `git push && ./build-app.sh`, then
  `pkill -f "Victor Effects"; open "/Applications/Victor Effects.app"`.
  Never start the app by its binary path (`.../Contents/MacOS/Victor Effects`) —
  macOS then registers it as a *second* app by path and its TCC grants
  (Accessibility, Screen Recording) do not apply.
- **Self-termination rule.** Every `show*` schedules its own removal. A
  `stop-all` or a `/sound/stopped` from a client is an *optimisation*, never the
  thing that ends an effect — with two processes, a missing stop is now also a
  missing proxy hop, and an effect that only dies on a remote message would stay
  on screen forever.
- **`build-app.sh` runs `swift test` first and refuses to deploy on a failure**
  (`SKIP_TESTS=1 ./build-app.sh` forces it, for a hotfix mid-workshop). A
  convention held together by string keys is only protected by a test that
  actually runs, and the deploy is the moment the drift would reach the room.
- **⭐ = "this tile also animates the desktop", and it is a promise, not a
  label.** One function answers it — `EffectsCatalog.effectName(forAsset:)` —
  and `/effects/assets`, `effectsHash` and the `effect` field `GET /tiles` stamps
  on each tile are all views of that one answer. The tablet keeps no list: it
  reads `effect` off the `/tiles` rows it already draws the grid from and
  re-fetches only when `effectsHash` moves in a `/ping`, so that half cannot
  drift. This half can, silently — `fireEffect` answers an unknown name by
  *logging*, and a new inside-the-clip effect lives in `EffectsEngine.playSound`
  where no map can see it. Two guards: `SoundEffectMapDriftTests` PARSES
  `EffectsEngine.swift` (the switch labels, the `if name ==` special cases)
  instead of comparing against a second copy, so the only way to make it pass is
  to make the thing true; `EffectsCatalogTests` writes the 44-name set out by
  hand, so a change to the promise costs a deliberate edit in the file that IS
  the promise. Adding an effect to `playSound` without deciding about its star
  fails the build with the name of the list to edit. Details in
  `docs/http-api.md` under **the ⭐ catalogue**.
- **This Mac owns the soundboard, not just its effects.** Three things the
  tablet used to decide for itself now arrive from here and are re-read whenever
  a hash in `/ping` moves: the grid itself (`GET /tiles` — order, columns,
  labels, `restartable`, ©, and the `effect` field behind the ⭐; `tilesHash` +
  `effectsHash`), and the press counts behind its green dots (`GET /usage`,
  `usageHash`). The tablet caches the last `/tiles` body on disk and builds from
  it at launch **before** its own bundled copy, so a board that boots with no Mac
  in reach still shows this Mac's last word. Anything that changes what a tile IS
  belongs in `tiles.json` or `EffectsCatalog`, never in Kotlin.
- **`UsageCounts` counts every press, from every surface.** The tablet reports
  its own (`/sound/pressed/`, `/alarm/start` for the siren) and the panel presses
  through the same router in-process, so one counter sees both — the panel's
  presses were invisible to the dots before. Stored in `usageFile`
  (`~/.victor-effects/usage.json` by default), NOT in `soundsDir`: that folder is
  a git checkout of the tablet repo.
- **Visual tests go on the non-projected screen.** The built-in retina is the
  overlay screen and may be mirrored to a room.
- **Sounds are not in this repo.** They live in `EffectsConfig.soundsDir`; never
  commit an mp3 beyond the bundled `click.wav`, `phoenix.mp3`, `confetti.mp3`
  and `whip_[A-E].mp3`.
- **This repo is public.** No paths under a home directory, no client names, no
  tokens. Anything machine-specific belongs in `EffectsConfig`.
- The HTTP handlers and the in-process callers share one entry point,
  `EffectsRouter.dispatch(_:)`. Add a route there, not in the socket code.
  `dispatch` is **main-thread only** (it asserts it); the socket path wraps it in
  `DispatchQueue.main.sync`, the thumbnail panel calls it directly.
- **One event tap, `EffectsHotkeyTap`.** ⌃W (swallowed), the Return/buttons-6-7
  crack and the right-⌘ panel hold (plus its right-⇧ video page) all live in it. A second tap would mean a
  second re-enable path for the same fragile resource and a second Accessibility
  failure to explain. Only ⌃W ever returns `nil`; everything else passes through.
- **The ⭐ menu is not a second surface.** Five rows: `✨ Effects` (Right ⌘),
  `🎦 Videos` (Right ⌘⇧), `🔥 Whip` (⌃W), `✔️/✖️ BT Keepalive` (the Bluetooth
  keep-alive's switch, ticked in the title — a real `state` shifts every row right — `docs/sound-routing.md`) and ⏻ Quit with the build stamp
  — plus ⚠️ Accessibility while that grant is missing. **No row carries a
  `keyEquivalent`**: `NSMenu` draws key equivalents in a column outside the
  titles that a tab stop cannot reach, so one native ⌘Q left every hint an icon
  and a half short of it (fixed 2026-09-14, `MenuBar.layOutHints`). Gestures are
  hints in an attributed title; ⌘Q is claimed by `menuHasKeyEquivalent` for the
  length of one open menu; every row opens with a glyph of emoji width (Quit's ⏻
  is an SF Symbol *image*, 21 pt, the way addons does it) so the words line up
  on the left the way the gestures line up on the right. **Stop-all is the icon
  itself** since 2026-09-13, and it is an EMERGENCY stop: while anything is
  running the ⭐ turns 🛑 and a plain click stops everything (layered effects,
  sound, progress bar and an armed 🔥 whip, in one `stopAll()`), right-click (or
  ⌃-click) opens the menu in either state. The click decides on a **live** read
  of `EffectsEngine.isAnythingRunning`, never on the drawn icon — the icon
  *polls* that same accessor every 0.3 s (the self-termination rule means most
  effects end with nobody announcing it), and answering a panicked click from a
  lamp that is up to 300 ms stale would open a menu over exactly the demo that
  needs killing.
  The menu is therefore detached (`statusItem.menu` nil, re-attached for one
  `performClick`) — an attached `NSMenu` swallows the button's action
  (`docs/overlay-effects.md`).
  The 39-row ⭐️ Effects submenu went on 2026-09-12, and with it the panel's
  checkbox, its "show now" and "Reload tiles.json" rows and "Open config
  folder": the panel shows the same effects as *pictures*, in the layout the
  room already knows from the tablet, and every row removed had a route or a
  gesture doing the same job (`/effect/<name>`, `/config/reload`, the right-⌘
  hold, a show that now re-reads `tiles.json` itself). A menu row that
  duplicates a picture is a second list to keep in step, and this repo has
  already paid for one of those. `docs/thumbnail-panel.md`.
- **The two apps degrade independently.** Addons answers `effectsUp:false` while
  this app is down; this app's webhook is fire-and-forget. Never introduce a
  dependency that makes one wait for the other. **The panel's 🎬 video page is the
  one bent case** and it is bent deliberately: the list and the play route live
  only on addons (`addonsBaseURL`, never a hardcoded port), the wait is capped at
  **1.5 s**, it happens on that page alone, and its failure mode is a tile reading
  *no videos (addons down?)* — not a hang and not a missing panel. Any further
  cross-app call owes the same three things: a config key, a timeout, and a
  visible degraded state.
