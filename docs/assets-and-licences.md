# Assets and licences

**Rule: nothing in this public repo is someone else's work unless its licence
allows redistribution, and its origin is written down.** A file whose origin
nobody recorded counts as someone else's.

## The audit of 2026-10-14

Every binary that was committed here was traced through the history of this
repo and of the private repo it was extracted from, through the docs and the
generator scripts, and looked at. 34 files left the repo:

- **9 identifiable third-party works** — the Counter-Strike AK-47 sprite, its
  draw sound and the CS key art (Valve); the Death Star render (Lucasfilm); the
  Minions GIF (Universal/Illumination); the Claude and Copilot logos
  (Anthropic, GitHub); and the app icon, which was Apple's own 💥 emoji glyph
  rendered by a script — replaced by the menu bar's 𝓯𝔁 drawn large (`tools/make-icon.swift`).
- **25 with no recorded origin** — GIFs and sprites downloaded over the years
  (applause hands, blood drip, bullet hole, cavalry knight, chainsaw sheet,
  confetti pop (replaced by a CC0 party popper, shipped), drum, ECG line, explosion, falling bomb, fire alarm, fire and
  fireball sheets, game-over, gong, heartbeat dog, leg, microwave, phoenix art
  and cry, red phone, Santa hat, "wasn't me", wolf howl, Zorro fire).

What stayed is listed with its licence in
`Sources/VictorEffects/Resources/CREDITS.md`.

**Removing a file from `master` does not remove it from the history.** The
files above are still reachable in older commits until the history is
rewritten (`git filter-repo --invert-paths --path …` + a force push), which is
the maintainer's call.

## How the effects find their pictures now

`EffectsResources.url(name, ext)` asks `assetsDir/<name>.<ext>` first
(`~/.victor-effects/assets`, see `EffectsConfig`), then the copy inside the app.
So:

- on the maintainer's Mac the pulled files sit in `assetsDir` and every effect
  looks exactly as before;
- on any other Mac those effects **degrade quietly** — the same contract the
  large optional assets (love hands, brother, gangnam, minions) always had: no
  crash, no error dialog, a log line, and either a simpler drawing or nothing;
- anyone can drop their own file under the same name into `assetsDir` and the
  effect picks it up on its next run.

The drop-in names (the tests check every one the code asks for is either
shipped or listed here):

`ak47.png` `ak47_draw.mp3` `applause-hands.gif` `blood-drip.gif`
`bullet_hole.png` `cavalry.png` `chainsaw-frames.png` `claude-icon.png`
`confetti.mp3` `copilot-icon.png` `counter-strike.png` `death-star.png`
`drum.gif` `ecg_line.png` `explosion.gif` `falling-bomb.png` `fire-alarm.gif`
`fire-frames.png` `fireball-sun.png` `game-over.png` `gong.gif`
`heartbeat-dog.png` `leg.png` `microwave.gif` `minion.gif` `phoenix.mp3`
`phoenix.png` `red-phone.png` `santa-hat.png` `wasnt-me.gif` `wolf-howl.gif`
`zorro_fire.gif`

Plus the ones that were never in the repo: `brother_full.gif`,
`love_hand_left.png`, `love_hand_right.png`, `pngtree-fail-stamp-cleaned.png`,
`wazzup.png`, `siren_lamp.png`, `scared_cat.gif`, `red_button.gif`,
`phoenix-rising.mov`, `phoenix-rising.mp3`, `universal-minions.mp3` and the
folders `gangnam_frames/`, `skull-boom/`, `universal-minions/`.

## The soundboard

None of the maintainer's soundboard audio is published: almost all of it is
YouTube rips (the DASH container signature is in the files) or a commercial
library (Sound Ideas). The app ships a separate **starter pack** instead
(`starter-pack/`), sourced only from CC0 / public-domain / CC-BY material and
from sounds synthesized for this project, each file credited in
`starter-pack/CREDITS.md` and checked by `tools/check-starter-pack.py`.

## The guard

`tools/copyright-guard.py check` runs in `build-app.sh` and `tools/release.sh`.
On the maintainer's Mac it reads a private ledger (sha256 of every file in the
private soundboard and `assetsDir`, each classified) and fails if any of those
bytes is tracked in this repo. Elsewhere the ledger is absent and the check
says it skipped.
