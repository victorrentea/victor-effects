# Testing & Diagnostics

Every effect is reachable headlessly over HTTP on `127.0.0.1:55124`, so nothing
here needs UI focus, a menu click or a tablet. **All of these also answer on
`127.0.0.1:55123`**, under the same spelling, because the addons app proxies
them — which is why the `/test/` names were kept rather than tidied up.

**Visual checks go on a screen the room is not seeing.** The built-in retina is
the overlay screen (`EffectsConfig.overlayScreen`) and during a session it is
mirrored to the projector, so a test that draws there draws in front of the
audience. `GET /state` exists precisely so the things that are only visible on
screen — what is playing, which effects are active, `whipShowing`,
`panelVisible` — can be read instead of looked at.

## Effects

- `GET /test/sonar` — fire the 🛰️ Sonar overlay now (visual + synced `23_radar.mp3`); same as `/effect/sonar`. The tablet drives it by routing `GET /sound/play/23_radar.mp3` to the Mac (handled in `EffectsEngine.playSound`)
- `GET /test/beethoven` — fire the 🎼 Beethoven zoom now (visual + `51_beethoven.mp3`); same as `/effect/beethoven`. **Not silent**: the whole effect is the screen lunging on the motif, so the test path plays the clip. The tablet drives it by routing `GET /sound/play/51_beethoven.mp3` to the Mac (`EffectsEngine.playSound`)
- `GET /test/money` — fire one round of the 💸 Money rising-dollars overlay now; same as `/effect/money`. The tablet drives it by routing `GET /sound/play/53_rain.mp3` to the Mac (handled in `EffectsEngine.playSound`), which also plays the #57 checkmark "ching"
- `GET /test/iris` — fire the 🕳️ Iris-close blackout now (5s close → 1s hold → auto fade-out reveal); same as `/effect/iris`. The tablet drives it via `GET /sound/pressed/31_tarzan.mp3` (mapped to `iris` in `SoundEffectMap`); a second press before the auto-reveal cancels it early. The `/test/iris` visual itself is silent; the tablet-routed press pairs it with the gong (`50_gong.mp3`) via `EffectsEngine.playSound`
- `GET /test/crt-shutdown` — close the desktop like an old cathode-ray TV now (silent, ~2.1 s: 0.7 s of black shutters coming in from the top and bottom edges, a 10 pt white line held 0.15 s, a 0.4 s sideways collapse into a dot, then the black fades away); same as `/effect/crt-shutdown`. This is the **tail of the 💀 game-over tile**, addressable on its own so it can be rehearsed without sitting through the picture and the 1.6 s clip first. The full path is `GET /sound/play/59_game_over.mp3` + `GET /sound/pressed/59_game_over.mp3`, which shows GAME OVER for the clip's length and *then* closes the tube. `GET /state` reports it as `crt-shutdown` in `activeEffects` while it runs, and `/effect/stop-all` clears it instantly (as does a stop-all fired during the GAME OVER picture, which cancels the close before it starts)
- `GET /test/counter-strike` — fire the 🔫 Counter-Strike overlay now (silent, ~1.4 s in the bottom-left quarter); same as `/effect/counter-strike`. The tablet drives it via `GET /sound/pressed/73_counter_strike.mp3` (mapped to `counter-strike` in `SoundEffectMap`) while the routed `/sound/play/73_counter_strike.mp3` plays the clip
- `GET /test/chainsaw` — replace the mouse pointer with a running 🪚 chainsaw now, **with its engine noise** (it idles until **Escape**; holding the left button cuts, screams and throws sparks; a 180 s cap is the backstop); same as `/effect/chainsaw`. `GET /test/chainsaw/stop` puts it away. The tablet's press arrives as `GET /sound/pressed/18_chainsaw.mp3` (mapped to `chainsaw` in `SoundEffectMap`); the routed `/sound/play/18_chainsaw.mp3` plays **nothing** and there is no `onStop` entry, so the tile's completion never ends the saw. **The real cursor is hidden and left clicks are eaten while it runs**, so if a test ever leaves you without a pointer, Escape, `/test/chainsaw/stop` or `/effect/stop-all` is the way back
- `GET /test/snow` — snow on the desktop now (silent, exactly the clip's ~10.5 s, then a 1 s melt); same as `/effect/snow`. `GET /test/snow/stop` melts it early, which is what the tablet sends when the 🎄 Bublé clip (tile #46) ends — the press itself arrives as `GET /sound/pressed/46_michael_buble.mp3`, mapped to `snow` in `SoundEffectMap`, while the routed `/sound/play/46_michael_buble.mp3` plays the song
- `GET /test/microwave` — fire the ⏲️ Microwave overlay now, **with its sound** (~4.4 s: 2.7 s of ticking at a closed door, then the BING and the door swinging open); same as `/effect/microwave`. Unlike the other effect hooks this one is not silent — the sync between the bell and the door is the whole thing being tested. The tablet drives it via the routed `GET /sound/play/61_dinner.mp3` (handled in `EffectsEngine.playSound`, deliberately not in `SoundEffectMap`)
- `GET /test/elephant` — walk the 🐘 elephant into the left half of the screen now (silent, toggles: a second call walks it back out, and it leaves on its own after 25 s); same as `/effect/elephant`. `GET /test/elephant/stop` is the explicit exit. This is the headless twin of ⌘⌃O — the overlay is click-through, so a screenshot of the built-in Retina is the only way to see it
- `GET /test/claude-peek` — slide the 🤖 Claude Code mark in from the left of the built-in Retina, hanging from 82% of the screen height at ~28.5% of it tall (silent, wearing the white rim `PeekMascotOutline` strokes onto its alpha so the cut-out still reads on a dark editor or slide, toggles: a second call slides it back out, and it leaves on its own after 5 s); `GET /test/claude-peek/stop` is the explicit exit. The headless twin of **⌘⌃Q**, which does nothing else — the mascot began on that key next to a Claude terminal, lost the terminal, spent 2026-09-09 on ⌃⌥G so macOS could have Lock Screen back, and came home the next day when ⌃⌥ became the emoji board and G went to the goose
- `GET /test/sketch-arrow` — sketch the 🔁 "one more time" replay arrow across the middle of the overlay screen now (silent, half-transparent, ~2 s of drawing, then it boils in place until the clip's 13.56 s are up and dissolves over the last 0.8 s); same as `/effect/sketch-arrow`. The tablet drives it via `GET /sound/pressed/71_one_more_time.mp3` (mapped to `sketch-arrow` in `SoundEffectMap`) while the routed `/sound/play/71_one_more_time.mp3` plays the clip down the ordinary path. It is click-through and centred on the built-in Retina, so `GET /state` (`activeEffects` contains `sketch-arrow`) is the headless way to see that it is up, and a screenshot of that display the only way to see what it drew
- `GET /test/coffee` — spawn 3 rising ☕ so the **hold-charge** gesture can be exercised headlessly. Rest the cursor on one (or on several at once — they all inflate): each freezes, grows for 3 s, then shatters into its own pixels (`EmojiAnimator.tickCoffeeCharge`, which returns where each one popped). Every pop fires one `?type=coffee-popped&x=&y=` at `eventWebhook`; with no webhook configured the ☕ still charges and still pops
- `GET /test/coffee/pop` — pop ONE fully-charged ☕ mid-screen right now, dissolve and webhook included, without holding a cursor still for three seconds. NB **not read-only** in the wider sense: the webhook really fires, and whatever is listening for it really acts. Point `eventWebhook` at an `nc -l` to watch the GET arrive without triggering the real payoff
- `GET /test/coffee/storm` — a salvo of ☕ at ~8/s for 2.5 s, past the **storm** threshold (more than 4 in any one second): the cups fly the wild storm flight — spawned across the width, wide zigzags, tumbling, higher and faster, 1.3–2× bigger — and **blow up 100% at the top** into 22×22 fragments with a real muzzle flash, all of it escalating as the salvo goes on. Calms down on its own ~2 s after the salvo; `/effect/stop-all` resets it at once. Hover a cup mid-flight to pop it early
- `GET /ping`, `GET /sounds/manifest`, `GET /sound/play/<file>?vol=N`, `GET /sound/volume/<pct>`, `GET /sound/stop` — tablet sound routing (see `sound-routing.md`)
- `GET /bt-compensation` — JSON `{"ms":<current>,"maxMs":1200}` of the Bluetooth wake-up compensation in effect (override if set, else the `sound-timing.json` default). `GET /bt-compensation/<ms>` — set it (clamped `0…1200`), returns `{"ok":true,"ms":<applied>}`; this is what the tablet's header **BT wake** slider pushes on release + on reconnect
- `GET /sound/pressed/<file>`, `GET /sound/stopped/<file>` — tablet reports a sound press/stop; the Mac maps it to an overlay effect via `SoundEffectMap` (e.g. `/sound/pressed/40_joker.mp3` → blood drip). `GET /effect/blood-drip` triggers the blood overlay directly.

## 🔥 Whip

- `GET /test/whip` — show the 🔥 whip on the screen under the cursor (same as ⌃W and the `🔥 Whip` menu row). NB it stays up until Esc, a second call, or `/effect/stop-all`
- `GET /test/whip/crack` — crack it: the scripted flick (`forceCrack`) plus one of `whip_A..E.mp3`. A no-op while the whip is hidden, not an error. It does **not** fire the typing macro — that only happens on a real click, and it types into whatever app has focus (`docs/whip.md`)
  - To see the mascot flinch, call `/test/claude-peek` first and crack within its five seconds: he jumps, lands on the same pixel, and his exit timer restarts (`docs/whip.md`). With nothing on screen the crack is unchanged

## Thumbnail panel

- `GET /test/thumbnail-panel` — show the tile grid on the screen the placement rule picks, and answer with the frame and screen name it chose. The headless way to check `ThumbnailPanelPlacement` on a rig you are actually sitting at
- `GET /test/thumbnail-panel/hide` — hide it
- `GET /test/thumbnail-panel/press/<n>` — press tile `n` exactly as a click does: stop-all, play, paired effect, and the scheduled `/sound/stopped`. The headless proof of `SoundboardPress`, and the only way to exercise it without a mouse on the right screen
- `GET /test/thumbnail-panel?page=videos` — the same, on the panel's 🎬 **second page**. The answer carries `"page":"videos"` and a `tiles` count that must match `curl -s 127.0.0.1:55123/videos | jq '.videos|length'` — the two-command check that the fetch, the parse and the grid all agree
- `GET /test/thumbnail-panel/press/<n>?page=videos` — press video tile `n` (its `#NN`, i.e. its place in the Mac's order): plays the clip in IINA through addons, or stops it when it is the one already playing. **Stop it when you are done** (`curl 127.0.0.1:55123/video/stop`) or it sits fullscreen on the Retina until the ~60 s auto-kill
- All of them answer **503** `{"ok":false,"reason":"no-panel"}` when the panel is not wired. Page 1 needs a `tiles.json` in `soundsDir` (`GET /tiles` tells you whether there is one); page 2 needs the addons app up on `addonsBaseURL` and answers `unknown-video` for a number past the end of its list
- **The hold gestures themselves cannot be tested from a shell.** Right ⌘ and right ⌘+⇧ need synthesised input on a live machine, which is not something to do here — `ThumbnailPanelHoldTests` and `EffectsHotkeyTapRulesTests` are the assertions that stand in for it

## Sound and state

- `GET /ping` — `{ok, app, effectsVersion, soundsHash, tilesHash, tabletVolume, panelMonitor}` — `panelMonitor` is now simply whether the event tap is running, the checkbox that used to be ANDed into it having gone. Also feeds the routed-sound watchdog: 12 s without a ping stops a playing sound
- `GET /state` — what is playing, which effects are live, `whipShowing`, `panelMonitor`, `panelVisible`, and the whole live config including `soundsDirExists` — the first thing to check when everything answers `ok` and nothing is audible
- `GET /config/reload` — re-read `~/.victor-effects/config.json` and drop the sounds, tiles, tile-image and timing caches (the image half is what the retired `Reload tiles.json` menu row used to be for). Answers with the config it ended up with, so a typo in a path is visible immediately
- `GET /tiles` — the tile manifest, or a 404 naming the `soundsDir` it looked in

**Quirk worth knowing:** `state.playing` is `null` during the sonar and the
money round even while you can hear them. Those two take the special audio paths
in `EffectsEngine.playSound` (the sonar plays its own beep-synced audio, the
money round layers an overlapping "ching"), and `stateJSON` gates `playing` on
`SoundManager.isTabletSoundPlaying` — which is the *routed* player, not those.
Not a bug to chase: check `activeEffects` instead.

## Unit tests

`swift test`. The parts worth knowing about:

- `EffectsRouterTests` — the whole route table, asserted as values with no socket
- `EffectsHotkeyTapRulesTests` — `decideKey` / `decideMouse` / `decideModifier` as pure rules: ⌃W swallows, ⌘⌃W passes, Return cracks only while the whip is showing, and the panel arms on **right ⌘ (54) alone** — never on left ⌘ (55), never on right ⇧ (60) by itself, and never under ⌃⌘ / ⌘⌥ / left-⌘⇧. The page switch is **right ⇧ (60)**, told from the left one (56) by the device bits; `testWisprPushToTalkNeverOpensThePanel` pins the reason it is not ⌥ — that chord is Wispr Flow's push-to-talk
- `WhipPhysicsTests.testSettleMatchesJSGolden` — frame-by-frame parity with the JavaScript original (`tools/whip-parity`)
- `PeekWhipJumpTests` — the ⌘⌃Q mascot's hop on a crack: one crack is one hop, consecutive cracks throw him to opposite sides, every arc stays on the screen (top bezel *and* the tight left one) without the clamp doing the work, a crack mid-hop rises from where he already is and he still lands on the pixel he came in on, he hangs low enough for the tallest hop to fit above him, both cut-outs flinch identically, and — by parsing `WhipOverlay.swift` — every crack still goes through the `cracked()` funnel rather than calling `playCrack()` directly
- `SoundsManifestTests` — the canonical hash form, which an Android client reproduces byte for byte
- `TilesManifestTests`, `EffectsConfigTests` — both parse literals rather than reading this machine, so no test depends on what is installed here
