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
- **Visual tests go on the non-projected screen.** The built-in retina is the
  overlay screen and may be mirrored to a room.
- **Sounds are not in this repo.** They live in `EffectsConfig.soundsDir`; never
  commit an mp3 beyond the bundled `click.wav`, `phoenix.mp3`, `confetti.mp3`
  and `whip_[A-E].mp3`.
- **This repo is public.** No paths under a home directory, no client names, no
  tokens. Anything machine-specific belongs in `EffectsConfig`.
- The HTTP handlers and the in-process callers share one entry point,
  `EffectsRouter.dispatch(_:)`. Add a route there, not in the socket code.
