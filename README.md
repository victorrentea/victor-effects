# Victor Effects 🎆

A macOS menu-bar app that draws **presentation effects** over the screen and
plays a **soundboard** on request — confetti, snow, a fire cursor, a chainsaw
cursor, a phoenix, a gong, a heartbeat monitor, fireworks — plus a physics-driven
🔥 **whip** you can crack at a coding agent.

Everything is addressable over a small local HTTP API, so a tablet, a phone, a
shell script, an editor plugin or another app can fire an effect.

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

## HTTP API

Every route is `GET` on `http://127.0.0.1:<port>`.

| route | does |
|---|---|
| `/ping` | `{ok, app, version, soundsHash, tilesHash, tabletVolume, panelMonitor}` |
| `/effect/<name>` | run an effect — see the ⭐️ Effects menu for the list |
| `/effect/stop-all` | stop every effect and sound |
| `/effect/progress-bar/<seconds>?rider=🏁`, `/effect/progress-bar/stop` | a countdown bar |
| `/effect/emoji?e=❤️&count=3&glow=…` | fly emoji up the screen |
| `/effect/whip`, `/effect/whip/crack` | show/hide the whip, crack it |
| `/effect/coffee`, `/effect/coffee/pop` | the chargeable ☕ |
| `/effect/green-flash`, `/effect/click` | link-feedback flash and click |
| `/sound/play/<file>?vol=N` | play a sound from `soundsDir` → `{ok, durationMs}` |
| `/sound/pressed/<file>`, `/sound/stopped/<file>` | the effect paired with a sound |
| `/sound/volume/<pct>`, `/sound/stop` | volume, stop |
| `/sounds/manifest` | `{name: sha256}` over `soundsDir/*.mp3` |
| `/alarm/start`, `/alarm/stop` | the siren overlay |
| `/bt-compensation`, `/bt-compensation/<ms>` | Bluetooth latency offset |
| `/tiles`, `/tiles/<path>` | `tiles.json` and its images |
| `/state` | what is playing/showing right now |
| `/config/reload` | re-read the config file |
| `/test/<name>` | historical aliases of the `/effect/` routes |

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

## Licence

MIT — see `LICENSE`.
