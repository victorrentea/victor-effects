# Victor Effects 💥

A macOS menu-bar app that draws **presentation effects** over the screen and
plays a **soundboard** on request — confetti, snow, a fire cursor, a chainsaw
cursor, a phoenix, a gong, a heartbeat monitor, fireworks — plus a physics-driven
🔥 **whip** you can crack at a coding agent.

Everything is addressable over a small local HTTP API, so a tablet, a phone, a
shell script, an editor plugin or another app can fire an effect. Hold the right
⌘ key and the soundboard itself appears as a grid of thumbnails you can click.

It was extracted from [victor-macos-addons](https://github.com/victorrentea/victor-macos-addons),
which keeps the training/transcription half and proxies the effect routes here.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/victorrentea/victor-effects/main/install.sh | bash
```

That is the whole install: it downloads the latest release (one app for Apple
silicon and Intel, macOS 13+), puts it in `/Applications`, starts it at login,
fires a confetti burst to prove it works, and opens the one System Settings pane
you have to visit yourself. No Xcode, no config file — it comes with a free
starter soundboard (`starter-pack/`) and every effect is one `curl` away:

```bash
curl http://127.0.0.1:55124/effect/fireworks
```

**Two permissions only you can grant** (macOS lets no script or agent tick
them): *Accessibility* for the hotkeys (hold the right ⌘ for the soundboard, ⌃W
for the whip) and *Screen Recording* for the effects that bend what is on
screen. System Settings › Privacy & Security, switch on "Victor Effects", then
quit and reopen it from its `fx` menu. Everything else works without them.

Options: `--from-source` (build locally instead of downloading), `--no-login-item`,
`--uninstall` — pass them as `curl … | bash -s -- --uninstall`.

### Installing with an AI agent (Claude Code, Codex, …)

Ask it: *"install victor-effects from github.com/victorrentea/victor-effects"*.
What it should do, and all it needs to do:

1. run the one-liner above;
2. check `curl -s http://127.0.0.1:55124/state` — `permissions.accessibility`
   and `permissions.screenRecording` say what is still missing;
3. tell you which of the two switches to flip (it cannot flip them: TCC is
   protected by SIP, and editing it is not something to attempt);
4. after you flipped them, restart the app (`osascript -e 'quit app "Victor Effects"'; open -a "Victor Effects"`)
   and fire `/effect/confetti` to show you.

Your own sounds: a folder of `NN_name.mp3` files plus a `tiles.json`, pointed to
by `"soundsDir"` in `~/.victor-effects/config.json` (see *Bring your own sounds*).

## Build from source

```bash
swift build && swift test
./build-app.sh                 # installs /Applications/Victor Effects.app
open "/Applications/Victor Effects.app"
./install-startup.sh           # optional: start at login (LaunchAgent)
```

An `fx` appears in the menu bar. Its menu: `✨ Effects` (Right ⌘), `🎦 Videos`
(Right ⌘⇧), `🔥 Whip` (⌃W), `🙏 Pray` (⌃W ×2), `🫰 Snap` (⌃W ×3), `✓ BT Keepalive` and `✓ Subtitles` (switches),
`ⓘ Built <timestamp>` (which binary is running; opens this repo) and `⏻ Quit`
(⌘Q) — plus `⚠️ Grant Accessibility` while that grant is missing. The gestures
are drawn as right-aligned **hints**, not as key equivalents, because `NSMenu`
puts a real key equivalent in a column of its own that no tab stop can reach.
The log is `/tmp/victor-effects.log`.

**Stop-all is the icon, not a row.** While anything is running — including an
armed 🔥 whip — the `fx` turns 🛑, and a plain click stops everything at once;
right-click (or ⌃-click) opens the menu in either state. The click asks what is
running at that instant rather than trusting the icon, so it cannot miss an
effect that started a moment ago. See `docs/overlay-effects.md`.

## Permissions

| permission | why | what breaks without it |
|---|---|---|
| **Accessibility** | one `CGEventTap` for ⌃W (whip) and the right-⌘ panel hold | the hotkeys; effects still work over HTTP, and the two menu rows still open the panel |
| **Screen Recording** | `CGDisplayCreateImage` for the effects that distort what is on screen (heartbeat lens, broken glass, FBI knock, beethoven, chainsaw) | those effects draw on a blank backdrop |

Nothing else: no microphone, no location, no Bluetooth permission, no full disk
access.

## Bring your own sounds

The app reads a folder of `NN_name.mp3` files plus a `tiles.json` (the grid:
which sound, which picture, in what order) at runtime, and hashes it so a client
such as a tablet can tell whether its own copy matches.

**Out of the box it uses the starter pack** (`starter-pack/`, bundled in the
app): 43 short sounds — CC0 and public-domain recordings plus a few synthesized
here — each with a Noto Emoji tile and a credit line in
`starter-pack/CREDITS.md`. Sounds named like the starter pack's
(`03_explosion.mp3`, `50_gong.mp3`, …) also fire their desktop effect; the map is
`Sources/VictorEffects/SoundEffectMap.swift`.

To use your own: copy `starter-pack/` somewhere, change it, and set
`"soundsDir"` in `~/.victor-effects/config.json` to that folder (then
`curl 127.0.0.1:55124/config/reload`). Mind the licences of what you put in it
if you share it — the maintainer's own soundboard is not published for exactly
that reason.

## Configuration — `~/.victor-effects/config.json`

```json
{
  "port": 55124,
  "soundsDir": "~/sounds",
  "assetsDir": "~/.victor-effects/assets",
  "eventWebhook": "",
  "bluetoothSpeakerNameMatch": "",
  "overlayScreen": "builtin",
  "chargeEmoji": ["☕"],
  "addonsBaseURL": "http://127.0.0.1:55123"
}
```

| key | default | meaning |
|---|---|---|
| `port` | `55124` | HTTP listen port |
| `soundsDir` | `~/.victor-effects/sounds` | soundboard mp3s, `sound-timing.json`, `tiles.json`, `tiles/` — when the folder does not exist, the bundled starter pack |
| `assetsDir` | `~/.victor-effects/assets` | optional extra images a few effects want (see below) |
| `eventWebhook` | *(none)* | fire-and-forget `GET <url>?type=…` for cross-app gestures |
| `bluetoothSpeakerNameMatch` | *(empty = off)* | substring of a Bluetooth speaker's name to keep awake between sounds |
| `overlayScreen` | `builtin` | `builtin` \| `main` \| a substring of a screen's name |
| `chargeEmoji` | `["☕"]` | emoji that charge up under the cursor and pop |
| `addonsBaseURL` | `http://127.0.0.1:55123` | where the **addons** app answers. The panel's 🎬 video page is built from its `GET /videos` and plays through its `GET /video/play/<id>` — the two routes it does *not* proxy back here. Empty switches the video page off, which is the right setting on a Mac with no addons app |

Env overrides: `VICTOR_EFFECTS_PORT`, `VICTOR_EFFECTS_SOUNDS_DIR`,
`VICTOR_EFFECTS_ADDONS_URL`, `VICTOR_EFFECTS_CONFIG` (path of the config file
itself).
`GET /config/reload` re-reads the file without restarting.

Some effects (`love-hands`, `brother`, `gangnam`, `fail`, the 🚨 air-horn beacon, …) look for extra images
in `assetsDir` and quietly do nothing when they are absent — they are large or
licensed files, so they are not committed here.

## The soundboard panel

Holding the **right ⌘** alone for 180 ms puts the tile grid on a screen the audience is
not looking at; releasing hides it. Add the **right ⇧** (either order, while ⌘ is
down) and the same window shows the 🎬 video snippets — the tablet's page 2 —
switching back in place when ⇧ is let go. Clicking a tile plays its sound and whatever
visual is paired with it, and clicking it again stops both. Left ⌘ never opens
it, and ⌃, ⌥ (right ⌘ + right ⌥ is Wispr Flow's push-to-talk), a left ⇧ or any
key pressed while the right ⌘ is held cancels — so ⌘-shortcuts are untouched.

The grid comes from a `tiles.json` next to the sounds (`soundsDir`), so adding a
tile is one JSON entry plus one image. See `docs/thumbnail-panel.md` and
`docs/http-api.md`.

## HTTP API

Every route is a `GET` on `http://127.0.0.1:<port>`:

| route | does |
|---|---|
| `/ping` | `{ok, app, effectsVersion, soundsHash, tilesHash, tabletVolume, panelMonitor}` |
| `/effect/<name>` | run an effect — `docs/overlay-effects.md` lists them |
| `/effect/stop-all` | stop every effect and sound |
| `/sound/play/<file>?vol=N` | play a sound from `soundsDir` → `{ok, durationMs}` |
| `/sounds/manifest`, `/tiles` | what this Mac has, so a client can compare |
| `/state`, `/config/reload` | diagnostics, and re-read the config |

**`docs/http-api.md` is the full contract** — every route, the query parameters,
the status codes, the one webhook that goes the other way, and the `tiles.json`
schema.

## 🔥 The whip

⌃W shows a whip that follows the mouse; flicking it, pressing **Return**, or a
mouse button 6/7 cracks it. Esc dismisses it.

⌃W again puts a praying man under the pointer instead (🙏 pray — only one mode
is ever out); a click plants him and sings an Ave Maria. His picture is a
drop-in (`praying-man.png` in `assetsDir`); without it he is a 🙏.

⌃W a third time makes the pointer a hand (🫰 snap); a click snaps its fingers.
A fourth goes back to the whip, and Esc ends whichever is up.

**A crack types into whatever app is focused**: it posts ⌃C followed by a short
phrase and Return, which is the point — it is meant for interrupting a coding
agent in a terminal. Do not crack it over something you care about. The physics
and the phrases are a port of [OpenWhip](https://github.com/GitFrog1111/OpenWhip);
`tools/whip-parity/` holds the JS reference and the golden data the Swift
implementation is tested against.

Because the tap swallows ⌃W globally, that key stops reaching terminals
(delete-word-backwards) while this app runs. ⌘⌃W is deliberately *not* bound.

## Assets and licences

Only material that is our own or licensed for redistribution ships in this repo
— each file is credited in `Sources/VictorEffects/Resources/CREDITS.md` and
`starter-pack/CREDITS.md`. The whip's physics, phrases and crack sounds come
from [OpenWhip](https://github.com/GitFrog1111/OpenWhip) (MIT).

Many effects were built around pictures that are someone else's (game sprites,
film stills, GIFs with no licence). Those are **not** published: the app looks
for them in `assetsDir` (`~/.victor-effects/assets`) and the effect degrades
quietly without them. `docs/assets-and-licences.md` lists the names, so you can
drop your own in.

## See them

Every effect, fired over a real editor window and labelled with the route that
fires it:
**[effects-gallery.mp4](https://github.com/victorrentea/victor-effects/releases/latest/download/effects-gallery.mp4)**.

It is a release asset rather than a file in the repo — a montage of fifty
effects outweighs the entire source tree. `tools/record-gallery.sh` records and
republishes it; `docs/gallery.md` explains how.

## Documentation

`docs/` carries the reasoning, not just the interface: the effect catalogue and
why each one looks the way it does (`overlay-effects.md`), the whip
(`whip.md`), sound routing and the Bluetooth mitigations (`sound-routing.md`),
the HTTP contract (`http-api.md`), the panel (`thumbnail-panel.md`), the
gallery video (`gallery.md`), the headless test hooks (`testing.md`) and
deployment (`deployment.md`).

## Licence

MIT — see `LICENSE`.
