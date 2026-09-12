# HTTP API (port 55124)

Everything this app can be asked to do is a **GET** on
`http://127.0.0.1:<port>`, default **55124** (`EffectsConfig.port`, env
`VICTOR_EFFECTS_PORT`). The listener (`EffectsHttpServer`, an `NWListener`)
binds all interfaces, not just loopback, so a device on the LAN can reach it the
same way a local script can.

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
| `GET /ping` | `{"ok":true,"app":"victor-effects","effectsVersion":"<build>","soundsHash":"…","tilesHash":"…","effectsHash":"…","usageHash":"…","tabletVolume":<0–100>,"panelMonitor":<bool>}` | See **the /ping contract** below |
| `GET /sounds/manifest` | `{name: sha256}` over `soundsDir/*.mp3` | **503** `{"error":"soundsDir unreadable"}` when the folder is gone |
| `GET /sound/play/<file>?vol=N` | `{"ok":true,"durationMs":N}` | **404** `{"ok":false,"reason":"unknown-sound"}`. Seven files take a paired-visual path, and a few are **alternating pairs** — one press, two clips in turn (#19/#20), with the duration of the file actually played. Both in `docs/sound-routing.md` |
| `GET /sound/volume/<pct>` | `ok` | player level, not system volume |
| `GET /sound/stop` | `ok` | fades over `interruptFade` |
| `GET /sound/pressed/<file>` | `ok`, or `no-effect` | `SoundEffectMap.pressEffect` → `runEffect` |
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
| `GET /effect/coffee`, `GET /effect/coffee/pop` | `ok` | the pop fires the webhook below |
| `GET /effect/stop-all` | `ok` | sound + every active effect + the progress bar + the whip |
| `GET /test/<name>` | as `/effect/<name>` | the historical alias list — `docs/testing.md` |
| `GET /tiles` | `tiles.json` **plus** `effect` per tile and a top-level `effectsHash` | **404** `{"error":"no tiles.json in <soundsDir>"}`. See **the ⭐ catalogue** |
| `GET /tiles/<path>` | image bytes | path resolved under `soundsDir` and **re-checked to still be inside it** — the names come from a JSON file this app does not own |
| `GET /test/thumbnail-panel[/hide\|/press/<n>]` | panel JSON | `?page=videos` on the show and the press picks the panel's 🎬 second page (default `effects`; an unknown value falls back to it rather than 404). **503** `{"ok":false,"reason":"no-panel"}` when no panel is wired |
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
playing sound.

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
| `SoundEffectMap.playPathVisuals` | the cue sits at a fixed offset INSIDE the clip, so `EffectsEngine.playSound` owns audio and visual together; mapping the press too would double-trigger | `61_dinner.mp3` → `microwave` (the BING at 2.695 s) |
| `SoundboardPress.sirenAsset` | a toggled overlay via `/alarm/*`, not a self-terminating effect, so it is in neither table | `02_siren.mp3` → `alarm` |

**The ⭐ badge is a promise, not a label**, and the tablet keeps no list of its
own: it reads the `effect` field off the `/tiles` rows it already draws the grid
from, caches the set together with the hash that produced it, and re-fetches only
when `effectsHash` moves in a `/ping`. Adding a desktop effect therefore makes
the star appear with no tablet redeploy.

Two test files hold this together, and both are guards rather than copies:

- `EffectsCatalogTests` writes the 44-name set out BY HAND. It is the only place
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
 "whipShowing":false,
 "panelMonitor":true,"panelVisible":false,
 "config":{…}}
```

`playing` is `null` when nothing is routed. `whipShowing`, `panelMonitor` and
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
