# HTTP API (port 55124)

Everything this app can be asked to do is a **GET** on
`http://127.0.0.1:<port>`, default **55124** (`EffectsConfig.port`, env
`VICTOR_EFFECTS_PORT`). The listener (`EffectsHttpServer`, an `NWListener`)
binds **127.0.0.1 only** since 2026-11-13. `"lanAccess": true` in the config
opens it on every interface — only on a network you trust, since no route asks
for a password (on a shared Wi-Fi the whole room could drive the overlays).

One request line, one response, close. There is no authentication, no TLS and no
body parsing: this is a local control surface, deliberately small enough that a
tablet, a shell script, an editor plugin or another app can drive it without
linking against anything.

## One dispatch table, two callers

`EffectsRouter` is the whole surface as a value:

- `EffectsRouter.route(forPath:)` is `static` and **pure** — it turns a path
  plus query into a `Route` case, so the table can be asserted in
  `EffectsRouterTests` with no socket and no window server.
- `EffectsRouter.dispatch(_:)` is the single place a route becomes an action.
  **Main thread only** (it asserts it): every handler touches AppKit.

The socket path wraps it (`EffectsHttpServer.respond` → `DispatchQueue.main.sync
{ router.dispatch(path) }`); an in-process caller that is *already* on main —
the thumbnail panel's `SoundboardPress` — calls `dispatch` directly. That is the
whole reason the two are separate functions, and why a panel press and a tablet
press cannot drift apart.

**Add a route in `EffectsRouter`, never in the socket code.**

## The routes

| route | answers | notes |
|---|---|---|
| `GET /ping` | `{"ok":true,"app":"victor-effects","effectsVersion":"<build>","soundsHash":"…","tilesHash":"…","effectsHash":"…","usageHash":"…","gainsHash":"…","speakerChargePct":<0–100 or -1>,"speakerCharging":<bool>,"speakerChargeAgeS":<s>,"tabletVolume":<0–100>,"panelMonitor":<bool>}` | See **the /ping contract** below |
| `GET /sounds/manifest` | `{name: sha256}` over `soundsDir/*.mp3` | **503** `{"error":"soundsDir unreadable"}` when the folder is gone |
| `GET /sound/play/<file>?vol=N` | `{"ok":true,"durationMs":N}` | **404** `{"ok":false,"reason":"unknown-sound"}`. Several files take a paired-visual path. In `docs/sound-routing.md` (no tile alternates between two clips any more: #19's and #49's second takes are their layer B since 2026-11-12) |
| `GET /sound/volume/<pct>` | `ok` | player level, not system volume |
| `GET /sound/stop/<asset>` | `ok` | ⏹ That **tile** pressed again while it runs: its clip (`SoundManager.stopTabletSound(tile:)`), its desktop effect (`EmojiAnimator.stopEffect(named:)` under its catalogue name) and its looping stop-effect end — every other tile keeps running. Since 2026-10-29 tiles **overlap**: `/sound/play` replaces only the same tile's clip, and neither the tablet nor the panel sends `/effect/stop-all` before a press any more (stop-all stays the 🛑 panic button) |
| `GET /sound/running/<asset>` | `{"running":<bool>}` | ♾️ For the **open-ended** tiles only — #11 fire, #18 chainsaw, #22 minigun (until Escape), #41 love hands (until the click, ≤ 30 s), #3 bombs (while planted) — `OpenEndedTiles`: their length is not known at the press, so the `durationMs` their `/sound/play` answers is only how long the tile looks lit. Their `/sound/play` also carries **`"open":true`** (not while suspended: then only the plain clip plays); the tablet then draws a spinning green ring with no number and polls this once a second until `false`. **404** `{"ok":false,"reason":"not-open-ended"}` for any other tile |
| `GET /sound/gains` | `{"gains":{"<key>":<pos>,…},"defaultPct":80,"hash":"…","recommended":{…},"recommendedBoostDb":{…},"loudness":{"referenceLufs":R,"maxShortTermLufs":{…},"currentLufs":{…}},"boosts":{"<key>":{"db","readyDb","busy","limitedDb","limited","rev"?},…}}` | 🔉 Each tile's own volume (`SoundGains`), as a slider position **0–80, down only since 2026-11-09**: 80 = the clip as stored (×1.0), shown on the tablet as **100%** (display % = pos / 80), the x² curve (pos/80)²: 40 → ×0.25 ("50%"). Only tiles moved off 80 are listed. Rows stored above 80 from the days the bar boosted (`BoostedClips`, removed) are clamped to 80 on load, and the log names them. Keyed by the **tile** asset that `/sound/play` was asked for, not the file that plays (#31 → its gong), and applied on every surface — tablet-routed and thumbnail panel alike. Stored in `sound-gains.json` beside `usageFile`. The Mac plays `master × tile` (≤ ×1): blue × green on the tablet. 🔺 **The hints** (`RecommendedVolumes`): `recommended` = the bar position (< 80) that brings a LOUDER-than-average clip's loudest 3 s down to the mean (the tablet's ▲); `recommendedBoostDb` = the ＋ presses (whole 1.5 dB steps) that would lift a QUIETER one to it (the "＋3 dB" on the button). Measured per clip on the file(s) its press is heard as (`TileAudio`; a sound made in code has none and gets no hint), as max EBU R128 short-term loudness (3 s, or the clip when shorter; mono as dual-mono; −70 LUFS gate = silent, no hint) of the raw file + `fileGain`; a video over its played window (`startSeconds` +60 s); `R` = plain mean of the ORIGINALS' maxima (`maxShortTermLufs`), each clip judged as it plays now (`currentLufs`, its ＋ render). `boosts` = the ＋ state per clip (`DiskBoosts`), `rev` = the render the tablet downloads. `hash` (= `gainsHash` in `/ping`) moves with any of it |
| `GET /sound/boost/<key>/up` | the `/sound/gains` body | ＋ One more **+1.5 dB on disk** for a tile or `video:<id>` (cap +12): rendered at the new total FROM THE ORIGINAL (never from the previous render), through a look-ahead limiter at −1 dBFS, to a 16-bit WAV in `~/.victor-effects/boosted/`; the original is never written. Answers at once with `busy:true`; until the render lands, plays use the previous one. **Per FILE, pressed per tile**: a press raises every file the tile is HEARD as (`TileAudio`, the table `EffectsEngine.playSound` plays its remaps from and `TileAudioTests` holds it to: #31 → `iris_gong.mp3`, #53 → `money_ching.mp3`, #14 → `universal-minions.mp3`, #9 → the long hymn, #34 → the phoenix's cry, #19/#49 → both takes). **No two tiles share a file** since 2026-11-09: #31 and #53 have their own copies of #50's gong and #57's ching, so a ＋ on one is never heard on the other (only on a machine without the copies — the starter pack — do they borrow #50/#57's file again). Every player resolves its file through `SoundManager.soundURL(for:)`, which answers with the render — the routed play and the special paths alike (FBI, heartbeat, chainsaw, minigun, the hymn…); the per-tile bar reaches those paths through `SoundManager.tileGain(forFile:)`. A video boosts only the AUDIO of its played window, laid over the untouched mp4 by addons. **404** `unknown-clip` when there is nothing to render. `limited:true` when the limiter took more than 1 dB off a peak (the tablet's "limitat") |
| `GET /sound/boost/<key>/reset` | the `/sound/gains` body | ＋ Long-press: back to the original (0 dB); the renders are deleted, the original was never touched |
| `GET /sound/boost/<key>/file` | `audio/wav` | ＋ The tile's render of its own file, for the tablet's local plays (it re-downloads when `rev` moves). 404 when the tile has none |
| `GET /sound/boost/<key>` | `{"key","db","readyDb","busy","audio":{"path","start"}\|null}` | ＋ What addons asks at a video's play: the render to lay over `[start, start+len)` of the mp4, or `null` to play the file as it is |
| `GET /sound/gain/<asset>/<pct>` | the table | 🔉 Move one tile's volume; persisted, and applied live if that tile is the clip sounding. **Video snippets too** (2026-11-03): the row `video:<id>` is a page-2 clip's own volume — the tablet shows the same bar when a video or its ♪ soundtrack plays, sends `?gain=<pct>` on addons' `/video/play/<id>` and `/video/sound/<id>` (so does the panel's 🎬 page), and addons applies a live move as this route passes through its proxy. Same curve, same 0–80 (down only); a quiet video is lifted by its ＋ (`/sound/boost/video:<id>/up`) instead. **No click**, unlike `/sound/volume`: the tablet drags this bar while the clip plays |
| `GET /sound/stop` | `ok` | fades over `interruptFade` |
| `GET /voice/ref?sharing=0\|1&ref=<LUFS>&src=` | `{"ok":true,"active":<bool>}` | 🎚️ **Pushed by addons** once a second while Victor screen-shares (its `VoiceMeter`), and once with `sharing=0` when the share ends: his voice level, the reference every effect is held under (`VoiceCeiling`, `docs/sound-routing.md`). Dropped after 60 s without a push |
| `GET /voice/ceiling?key=<key>\|file=<name>&volume=<0–1>` | `{"subject","sharing","active","voiceRef","voiceRefSource","offsetDb","systemDb","clipLufs","measured","asked","volume","maxVolume","takenDb","refAgeS"}` | 🎚️ The cap for one clip: `key` = a `/sound/gains` key (addons asks `video:<id>` at a video's play), `file` = a sound file (its ＋ render if any). `volume` ≤ `asked`, always; `maxVolume` null when no share |
| `GET /test/voice/players` | `{"sharing":<bool>,"players":[{"file","asked","volume"}]}` | 🎚️ Every player still sounding: the volume it was asked for and the one it really plays at |
| `GET /sound/pressed/<file>` | `ok`, or `no-effect` | `SoundEffectMap.pressEffect` → `runEffect`; also counts the press and shows its caption (`docs/overlay-effects.md`, **💬 Every press is captioned**) |
| `GET /usage` | `{"counts":{"<asset>":n,…},"hash":"…"}` | The press count behind each of the tablet's green dots. **This Mac is the only counter**: every `/sound/pressed/` (tablet) and every in-process panel press lands in `UsageCounts`, so the dots finally include the presses made on the Mac itself. The body carries the hash it was computed from — a client adopting the table records THAT, not the one from a `/ping` its own press may have crossed |
| `GET /usage/import?counts=<asset>:<n>,…` | the merged table | One-shot seed of a client's history (the years the tablet counted alone). **Max-merged**, so a retry or a second tablet cannot inflate anything |
| `GET /usage/reset` | the empty table | Wipes the counts — what the tablet's "Reset usage stats" now calls, since clearing only its own copy would be undone by the next ping |
| `GET /effects/assets` | `{"assets":["02_siren.mp3",…]}` | Every sound whose tile ALSO does something on the desktop, sorted — `EffectsCatalog.assets`. See **the ⭐ catalogue** below |
| `GET /sound/effects` | same body | The older spelling, kept for scripts and for tablet builds that predate the `effect` field on `/tiles` |
| `GET /sound/stopped/<file>` | `ok`, or `no-effect` | `SoundEffectMap.stopEffect` → `runEffect` |
| `GET /bt-compensation` | `{"ms":N,"maxMs":1200}` | |
| `GET /bt-compensation/<ms>` | `{"ok":true,"ms":<applied>}` | clamped `0…1200` |
| `GET /alarm/start`, `GET /alarm/stop` | `ok` | the siren overlay; the one unbounded toggle |
| `GET /effect/<name>` | `ok` | the `EffectsEngine.fireEffect` switch, nested names included. **An unknown name is 200 + a log line**, not a 404 |
| `GET /effect/emoji?e=❤️&count=3&glow=💛` | `ok` | `count` is **clamped to 1…50** — the query comes off the wire and a stray `count=100000` would spawn a hundred thousand layers |
| `GET /effect/progress-bar/<seconds>?rider=🏁` | `ok` | `seconds` must parse and be > 0, else **404** |
| `GET /effect/progress-bar/stop` | `ok` | |
| `GET /effect/whip`, `GET /effect/whip/crack` | `ok` | `docs/whip.md` |
| `GET /effect/ave-maria` (or `/effect/pray`), `GET /effect/pray/sing` | `ok` | toggles tile #9's 🙏 hands, hymn included; `sing` is a click — `docs/whip.md` |
| `GET /effect/red-button`, `GET /effect/red-button/click` | `ok` | tile #7's 🔴 pointer, without its clip; `click` is a click where the pointer is — `docs/overlay-effects.md` |
| `GET /effect/snap`, `GET /effect/snap/click` | `ok` | toggles 🫰 snap, the whip's other mode; `click` snaps the fingers — `docs/whip.md` |
| `GET /effect/coffee`, `GET /effect/coffee/pop`, `GET /effect/coffee/storm`, `GET /effect/coffee/won` | `ok` | three cups to pour into; the pop bursts one and fires the webhook below (none after a win); the storm is a salvo of ~8 cups; `won` is what addons sends when a ☕ −1 empties the UNTIL BREAK watch — yee-haw, then big bursts with fireworks (`docs/overlay-effects.md`) |
| `GET /effect/stop-all` | `ok` | sound + every active effect + the progress bar + the whip + 🙏 pray + 🫰 snap |
| `GET /test/<name>` | as `/effect/<name>` | the historical alias list — `docs/testing.md` |
| `GET /test/caption/<asset>` | `ok` | the press caption alone — no sound, no effect, no press counted; nothing while Subtitles is off |
| `GET /caption/video/<id>?cues=<json>` | `ok`, `not-shown` (Subtitles off, no words, suspended), 400 on bad JSON | 🎵 addons' soundtrack-only play hands over the `.srt` cues of its window, `[{at,end,text}]` in seconds from the first sound; sung karaoke-style as track `video:<id>` (`VideoCaptions`) |
| `GET /caption/video/<id>/stop` | `ok` | that soundtrack was stopped from outside: its lines go (`hide(asset: "video:<id>")`) |
| `GET /tiles` | `tiles.json` **plus** `effect` per tile and a top-level `effectsHash` | **404** `{"error":"no tiles.json in <soundsDir>"}`. See **the ⭐ catalogue** |
| `GET /sounds/captions` | `{"<asset>":{"durationSeconds":12.4,"cues":[{"start":0.0,"end":6.0,"text":"…"}]},…}` | Every asset in `tiles.json`, layer A and `under` B. Built from `SoundCaptions.live(for:clipSeconds:)` with the clip's real length, so it is exactly what the Mac shows; a cue's `end` is `start` + the seconds the caption stays up; a timed line also has `words`, the onsets into the clip. A silent asset has `"cues":[]`. Cached by `soundsHash`+`tilesHash` (durations open every mp3) — `CaptionsExport` |
| `GET /sounds/captions/base` | same shape | The same without the karaoke tuner's edits (`CaptionEdits`): what the app ships with, what `tools/karaoke-sync.py` publishes |
| `GET /tiles/<path>` | image bytes | path resolved under `soundsDir` and **re-checked to still be inside it** — the names come from a JSON file this app does not own |
| `GET /test/thumbnail-panel[/hide\|/press/<n>]` | panel JSON | `/press/<n>b` (and `/press/<n>b` outside `/test`) presses the tile under #n, layer B. `?page=videos` on the show and the press picks the panel's 🎬 second page (default `effects`; an unknown value falls back to it rather than 404). **503** `{"ok":false,"reason":"no-panel"}` when no panel is wired |
| `GET /state` | diagnostics, below | |
| `GET /config/reload` | `{"ok":true,"config":{…}}` | re-reads the file and drops the sounds/tiles/tile-image/timing caches |

Anything else is **404 `not found`**.

### The one route this app *calls*

Everything above is answered here. The panel's video page is the exception in the
other direction: it is built from **`GET <addonsBaseURL>/videos`** and a tile
press is **`GET <addonsBaseURL>/video/play/<id>`** / **`/video/stop`**, on the
**addons** app (55123). Those three are addons-local — not among the ones it
proxies back to 55124 — because the library, IINA, the display arrangement and
the auto-kill all live over there, and a proxy hop for them would only add a way
for the two halves to disagree about what is on the projector. `addonsBaseURL`
is an `EffectsConfig` key (default `http://127.0.0.1:55123`, empty = the page is
off) so nothing in this public repo knows another machine's ports. Every call has
a **1.5 s** cap and a failure is a page saying *no videos (addons down?)*, never
a wait — see `docs/thumbnail-panel.md`.

### The `/ping` contract

`/ping` is a **flat object with no nesting**, and that is a requirement rather
than a style: the addons app in front of it splices its own keys in by string
manipulation before the closing brace, so a nested value at the top level would
corrupt the merged body. It is also given about **1.5 s** by that proxy, which
is less than a cold sounds hash takes — hence `soundsHash` is read from a cache
that never blocks and may legitimately answer `""` (see `docs/sound-routing.md`).

Every `/ping` also feeds the routed-sound watchdog: 12 s without one stops a
playing sound — one a pinging client started (`docs/sound-routing.md`).

`effectsHash` needs no cache of its own: it is a SHA-256 over ~43 short strings
already in memory, with no I/O, so it cannot be the thing that blows the 1.5 s.

### The ⭐ catalogue

**`EffectsCatalog.effectName(forAsset:)` is the single answer** to "does pressing
this tile also do something on the desktop, and what?", and everything below is a
view of it:

- `EffectsCatalog.assets` — the sorted list, served as `/effects/assets`.
- `effectsHash` — SHA-256 of that list, newline-joined, in `/ping` and `/tiles`.
- `"effect": "<name>"` on each tile of `GET /tiles`.

It unions the two places a sound can acquire a visual, plus the siren:

| source | why it is separate | example |
|---|---|---|
| `SoundEffectMap.onPress` | the press path: the client reports the press, the Mac fires the effect | `03_explosion.mp3` → `explosion` |
| `SoundEffectMap.playPathVisuals` | the cue sits at a fixed offset INSIDE the clip, so `EffectsEngine.playSound` owns audio and visual together; mapping the press too would double-trigger | `53_rain.mp3` → `money` |
| `SoundboardPress.sirenAsset` | a toggled overlay via `/alarm/*`, not a self-terminating effect, so it is in neither table | `02_siren.mp3` → `alarm` |

**The badge is a promise, not a label** — an FX mark (this app's menu-bar 𝓯𝔁)
in the tile's top-right corner on the tablet and on the panel since 2026-10-22,
a ⭐ before that, which is where this section's name comes from. The tablet keeps no list of its
own: it reads the `effect` field off the `/tiles` rows it already draws the grid
from, caches the set together with the hash that produced it, and re-fetches only
when `effectsHash` moves in a `/ping`. Adding a desktop effect therefore makes
the badge appear with no tablet redeploy.

Two test files hold this together, and both are guards rather than copies:

- `EffectsCatalogTests` writes the 51-name set out BY HAND. It is the only place
  that says which tiles are *supposed* to animate the desktop, so adding an
  effect costs a deliberate second edit and the diff says so out loud.
- `SoundEffectMapDriftTests` PARSES `EffectsEngine.swift` — `fireEffect`'s switch
  labels and `playSound`'s `if name ==` special cases — so the only way to make
  it pass is to make the real thing true. It also checks every catalogued asset
  against the live `tiles.json` (skipped when `soundsDir` is not on this machine)
  to catch a renamed mp3 leaving a star over nothing.

`usageHash` is the third: a SHA-256 over the sorted `asset:count` lines of
`UsageCounts`. It moves on every press — including a press made on the Mac's own
thumbnail panel, which is exactly the event the tablet had no way of hearing
about — and the tablet re-pulls `/usage` when it does.

`gainsHash` is the fourth, the same contract over `SoundGains` (`asset:pct`
lines) — plus, since 2026-11-09, the 🔺 hints and the ＋ disk boosts (busy
state included): the tablet re-pulls `/sound/gains` when it moves, for the
clips it plays locally, the ▲, the "＋N dB" and the renders it downloads.

`tilesHash` and `effectsHash` answer different questions and must not be merged:
`tilesHash` is the hash of the manifest's own BYTES ("is my tile list the Mac's
tile list") and is unaffected by the enrichment, while `effectsHash` covers only
the asset list ("is my star set the Mac's star set"). Renaming an effect moves
neither, on purpose — nothing the client draws changes, so a refetch would buy
nothing.

### `/state`

```json
{"playing":{"asset":"50_gong.mp3","durationMs":8600,"startedAt":1757000000000},
 "activeEffects":["snow"],
 "whipShowing":false,"prayShowing":false,"snapShowing":false,
 "panelMonitor":true,"panelVisible":false,
 "config":{…}}
```

`playing` is `null` when nothing is routed. `whipShowing` (and `prayShowing`, `snapShowing`), `panelMonitor` and
`panelVisible` are the three pieces of state that are otherwise only readable
off the screen — which is the projector. `config` is the live
`EffectsConfig.asJSON`, including `soundsDirExists`, which is the first thing to
check when everything answers `ok` and nothing is audible.

## The webhook out

One event goes the other way, fire-and-forget (`EventWebhook`, 1 s timeout,
nothing retried, nothing reported):

```
GET <eventWebhook>?type=coffee-popped&x=<global>&y=<global>
```

`eventWebhook` is a full URL in the config; empty (the default) disables it.
Existing query parameters on the configured URL are preserved. Reserved for
later: `sound-started`, `sound-ended`, `effect-ended`.

A missed pop is a missed payoff, never a stuck effect — the ☕ dissolve does not
wait for the delivery.

## The press log (`pressLogFile`)

Wherever `UsageCounts` counts a press (`/sound/pressed/<file>`, `/alarm/start`,
panel presses), `PressLog` also appends one JSON line to `pressLogFile`
(default `~/.victor-effects/presses.jsonl`; env `VICTOR_EFFECTS_PRESS_LOG`):

```json
{"ts":"2026-10-22T17:32:01.123+03:00","file":"53b_7_rings.mp3","n":53,"layer":"b","source":"tablet"}
```

`ts` is ISO-8601 with local offset; `n`/`layer` (`"a"`|`"b"`) are resolved from
`tiles.json` (an `under` tile shares its host's `n`), both `null` for a file not
on the grid. `source`: `tablet` = a press that arrived over HTTP, `panel` = the
in-process panel, `other` = a `/press/<n>` link fired over HTTP (script, daemon).
Append-only and best-effort: written on a utility queue, a failure is logged and
never reaches the press.

## `tiles.json` — the tile manifest

Read from `soundsDir/tiles.json` (`TilesManifest`), so the folder that carries
the audio also carries the grid. Adding a tile is one JSON entry plus one image
in `tiles/` — no code change on either end.

```json
{
  "columns": 13,
  "tiles": [
    { "n": 1,  "asset": "01_baby.mp3",          "image": "tiles/sfx_01_baby.jpg" },
    { "n": 53, "asset": "53_rain.mp3",          "image": "tiles/sfx_53_money.png", "restartable": true },
    { "n": 62, "asset": "62_lionel_richie.mp3", "image": "tiles/sfx_62_lionel_richie.jpg",
      "label": "HELLO", "copyright": true }
  ]
}
```

| key | type | meaning |
|---|---|---|
| `columns` | int | grid width; **13** if missing or ≤ 0 |
| `n` | int | the number drawn in the tile's corner, and how `/test/thumbnail-panel/press/<n>` addresses it |
| `asset` | string | filename inside `soundsDir` |
| `image` | string | image path **relative to `soundsDir`** |
| `effect` | string? | **added by `GET /tiles`, never present in the file** — the desktop effect this tile also fires (see **the ⭐ catalogue**). A stale copy written into the file by some older tool is overwritten, so the catalogue stays the only source |
| `label` | string? | optional word drawn across the tile |
| `restartable` | bool | pressing it again restarts instead of stopping (default `false`) |
| `copyright` | bool | third-party audio a client may choose to hide (default `false`) |

Order is grid order, filled in rows of `columns`.

Parsing is **lenient by design** (`TilesDocument.init(from:)`, `Tile.init(from:)`
swallow per-key failures): a manifest written by hand, or by a client build that
predates a key, must not take the whole panel down. `tilesHash` (SHA-256 of the
file bytes) is reported in `/ping` so a client can tell whether its tile list
matches this Mac's, exactly the way `soundsHash` does for the audio.

The `/tiles` body is enriched by re-serialising through `JSONSerialization`
rather than by splicing strings or round-tripping `TilesDocument`, so **keys this
app has never heard of survive**: the manifest is written in the tablet's repo,
and a Mac build that predates a new key must pass it through rather than filter
it out. `effect` itself is REPLACED, never merged.
