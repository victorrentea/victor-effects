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
| `GET /ping` | `{"ok":true,"app":"victor-effects","effectsVersion":"<build>","soundsHash":"…","tilesHash":"…","tabletVolume":<0–100>,"panelMonitor":<bool>}` | See **the /ping contract** below |
| `GET /sounds/manifest` | `{name: sha256}` over `soundsDir/*.mp3` | **503** `{"error":"soundsDir unreadable"}` when the folder is gone |
| `GET /sound/play/<file>?vol=N` | `{"ok":true,"durationMs":N}` | **404** `{"ok":false,"reason":"unknown-sound"}`. Seven files take a paired-visual path — see `docs/sound-routing.md` |
| `GET /sound/volume/<pct>` | `ok` | player level, not system volume |
| `GET /sound/stop` | `ok` | fades over `interruptFade` |
| `GET /sound/pressed/<file>` | `ok`, or `no-effect` | `SoundEffectMap.pressEffect` → `runEffect` |
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
| `GET /tiles` | `tiles.json` verbatim | **404** `{"error":"no tiles.json in <soundsDir>"}` |
| `GET /tiles/<path>` | image bytes | path resolved under `soundsDir` and **re-checked to still be inside it** — the names come from a JSON file this app does not own |
| `GET /test/thumbnail-panel[/hide\|/press/<n>]` | panel JSON | **503** `{"ok":false,"reason":"no-panel"}` when no panel is wired |
| `GET /state` | diagnostics, below | |
| `GET /config/reload` | `{"ok":true,"config":{…}}` | re-reads the file and drops the sounds/tiles/timing caches |

Anything else is **404 `not found`**.

### The `/ping` contract

`/ping` is a **flat object with no nesting**, and that is a requirement rather
than a style: the addons app in front of it splices its own keys in by string
manipulation before the closing brace, so a nested value at the top level would
corrupt the merged body. It is also given about **1.5 s** by that proxy, which
is less than a cold sounds hash takes — hence `soundsHash` is read from a cache
that never blocks and may legitimately answer `""` (see `docs/sound-routing.md`).

Every `/ping` also feeds the routed-sound watchdog: 12 s without one stops a
playing sound.

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
| `label` | string? | optional word drawn across the tile |
| `restartable` | bool | pressing it again restarts instead of stopping (default `false`) |
| `copyright` | bool | third-party audio a client may choose to hide (default `false`) |

Order is grid order, filled in rows of `columns`.

Parsing is **lenient by design** (`TilesDocument.init(from:)`, `Tile.init(from:)`
swallow per-key failures): a manifest written by hand, or by a client build that
predates a key, must not take the whole panel down. `tilesHash` (SHA-256 of the
file bytes) is reported in `/ping` so a client can tell whether its tile list
matches this Mac's, exactly the way `soundsHash` does for the audio.
