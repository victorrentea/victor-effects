# Victor Effects 🎆

A macOS menu-bar app that draws **presentation effects** over the screen and
plays a **soundboard** on request — confetti, snow, a fire cursor, a chainsaw
cursor, a phoenix, a gong, a heartbeat monitor, fireworks — plus a physics-driven
🔥 **whip** you can crack at a coding agent.

Everything is addressable over a small local HTTP API, so a tablet, a phone, a
shell script, an editor plugin or another app can fire an effect. Hold the right
⌘ key and the soundboard itself appears as a grid of thumbnails you can click.

It was extracted from [victor-macos-addons](https://github.com/victorrentea/victor-macos-addons),
which keeps the training/transcription half and proxies the effect routes here.

## Build and run

```bash
swift build && swift test
./build-app.sh                 # installs /Applications/Victor Effects.app
open "/Applications/Victor Effects.app"
./install-startup.sh           # optional: start at login (LaunchAgent)
```

A 🎆 appears in the menu bar. `Quit – built <timestamp>` tells you which binary
is running; the log is `/tmp/victor-effects.log`.

## Permissions

| permission | why | what breaks without it |
|---|---|---|
| **Accessibility** | one `CGEventTap` for ⌃W (whip) and the right-⌘ panel hold | the hotkeys; effects still work over HTTP and from the menu |
| **Screen Recording** | `CGDisplayCreateImage` for the effects that distort what is on screen (heartbeat lens, broken glass, FBI knock, beethoven, chainsaw) | those effects draw on a blank backdrop |

Nothing else: no microphone, no location, no Bluetooth permission, no full disk
access.

## Bring your own sounds

**No audio for the soundboard ships in this repo.** The app reads a folder of
`NN_name.mp3` files at runtime, named in the config, and hashes it so a client
can tell whether its own copy matches. Only three tiny bundled sounds are part of
the app itself (a click, a phoenix screech, a confetti pop) plus the five whip
cracks.

## Configuration — `~/.victor-effects/config.json`

```json
{
  "port": 55124,
  "soundsDir": "~/sounds",
  "assetsDir": "~/.victor-effects/assets",
  "eventWebhook": "",
  "bluetoothSpeakerNameMatch": "",
  "overlayScreen": "builtin",
  "chargeEmoji": ["☕"]
}
```

| key | default | meaning |
|---|---|---|
| `port` | `55124` | HTTP listen port |
| `soundsDir` | `~/.victor-effects/sounds` | soundboard mp3s, `sound-timing.json`, `tiles.json`, `tiles/` |
| `assetsDir` | `~/.victor-effects/assets` | optional extra images a few effects want (see below) |
| `eventWebhook` | *(none)* | fire-and-forget `GET <url>?type=…` for cross-app gestures |
| `bluetoothSpeakerNameMatch` | *(empty = off)* | substring of a Bluetooth speaker's name to keep awake between sounds |
| `overlayScreen` | `builtin` | `builtin` \| `main` \| a substring of a screen's name |
| `chargeEmoji` | `["☕"]` | emoji that charge up under the cursor and pop |

Env overrides: `VICTOR_EFFECTS_PORT`, `VICTOR_EFFECTS_SOUNDS_DIR`,
`VICTOR_EFFECTS_CONFIG` (path of the config file itself).
`GET /config/reload` re-reads the file without restarting.

Four effects (`love-hands`, `brother`, `gangnam`, `fail`) look for extra images
in `assetsDir` and quietly do nothing when they are absent — they are large or
licensed files, so they are not committed here.

## The soundboard panel

Holding the **right ⌘** for 180 ms puts the tile grid on a screen the audience is
not looking at; releasing hides it. Clicking a tile plays its sound and whatever
visual is paired with it, and clicking it again stops both. Left ⌘ never opens
it, and a key pressed while the right one is held cancels — so ⌘-shortcuts are
untouched.

The grid comes from a `tiles.json` next to the sounds (`soundsDir`), so adding a
tile is one JSON entry plus one image. See `docs/thumbnail-panel.md` and
`docs/http-api.md`.

## HTTP API

Every route is a `GET` on `http://127.0.0.1:<port>`:

| route | does |
|---|---|
| `/ping` | `{ok, app, effectsVersion, soundsHash, tilesHash, tabletVolume, panelMonitor}` |
| `/effect/<name>` | run an effect — the ⭐️ Effects menu lists them |
| `/effect/stop-all` | stop every effect and sound |
| `/sound/play/<file>?vol=N` | play a sound from `soundsDir` → `{ok, durationMs}` |
| `/sounds/manifest`, `/tiles` | what this Mac has, so a client can compare |
| `/state`, `/config/reload` | diagnostics, and re-read the config |

**`docs/http-api.md` is the full contract** — every route, the query parameters,
the status codes, the one webhook that goes the other way, and the `tiles.json`
schema.

## 🔥 The whip

⌃W shows a whip that follows the mouse; flicking it, pressing **Return**, or a
mouse button 6/7 cracks it. Esc or a second ⌃W dismisses it.

**A crack types into whatever app is focused**: it posts ⌃C followed by a short
phrase and Return, which is the point — it is meant for interrupting a coding
agent in a terminal. Do not crack it over something you care about. The physics
and the phrases are a port of [OpenWhip](https://github.com/aleiby/openwhip);
`tools/whip-parity/` holds the JS reference and the golden data the Swift
implementation is tested against.

Because the tap swallows ⌃W globally, that key stops reaching terminals
(delete-word-backwards) while this app runs. ⌘⌃W is deliberately *not* bound.

## Assets and licences

The GIFs and PNGs in `Sources/VictorEffects/Resources/` came over from the
public addons repo; their provenance is not tracked and using them is your
responsibility. The soundboard audio is never committed for exactly that reason.
`claude-icon.png` and `copilot-icon.png` are third-party logos used for an
optional mascot.

## Documentation

`docs/` carries the reasoning, not just the interface: the effect catalogue and
why each one looks the way it does (`overlay-effects.md`), the whip
(`whip.md`), sound routing and the Bluetooth mitigations (`sound-routing.md`),
the HTTP contract (`http-api.md`), the panel (`thumbnail-panel.md`), the
headless test hooks (`testing.md`) and deployment (`deployment.md`).

## Licence

MIT — see `LICENSE`.
