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
| thumbnail panel | `docs/thumbnail-panel.md` | the right-⌥ soundboard grid |
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
  crack and the right-⌥ panel hold all live in it. A second tap would mean a
  second re-enable path for the same fragile resource and a second Accessibility
  failure to explain. Only ⌃W ever returns `nil`; everything else passes through.
- **The two apps degrade independently.** Addons answers `effectsUp:false` while
  this app is down; this app's webhook is fire-and-forget. Never introduce a
  dependency that makes one wait for the other.
