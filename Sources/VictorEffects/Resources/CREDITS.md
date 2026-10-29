# What ships inside the app, and under what licence

Everything in this folder is either made for this project or carries a licence
that allows redistribution. Anything else lives outside the repo, in
`assetsDir` (`~/.victor-effects/assets`), and the effect that wants it degrades
quietly when it is missing — see `docs/assets-and-licences.md`.

| file | origin | licence |
|---|---|---|
| `click.wav` | a generated 1800 Hz tap | own work (MIT, with the code) |
| `elephant.png`, `panda.png`, `opus.png` | generated for this project (image tools), cut out locally | own work (MIT) |
| `Nosifer-Regular.ttf`, `Eater-Regular.ttf` | [Google Fonts](https://github.com/google/fonts/tree/main/ofl) — Nosifer by Typomondo, Eater by Typomondo; the 🤖 Opus caption | SIL OFL 1.1 (`OFL-Nosifer.txt`, `OFL-Eater.txt`) |
| `heartbeat_beats.json` | measured from a recording | own work (MIT) |
| `clouds/*.png` | two public-domain / CC0 photographs — `clouds/CREDITS.md` | PD / CC0 |
| `espresso_pour.mp3` | Wikimedia Commons, [Espresso machine.ogg](https://commons.wikimedia.org/wiki/File:Espresso_machine.ogg) | Public domain |
| `coffee_pour.mp3` | Wikimedia Commons, [Boiling water being poured into a mug for tea.ogg](https://commons.wikimedia.org/wiki/File:Boiling_water_being_poured_into_a_mug_for_tea.ogg) | Public domain |
| `whip_A.mp3` … `whip_E.mp3` | [OpenWhip](https://github.com/GitFrog1111/OpenWhip) `sounds/A–E.mp3`, byte-identical | MIT (OpenWhip `package.json`) |
| `pray-hymn-long.mp3` | Wikimedia Commons, [Franz Schubert - Ellens dritter Gesang.oga](https://commons.wikimedia.org/wiki/File:Franz_Schubert_-_Ellens_dritter_Gesang.oga) — Schubert's Ave Maria, D. 839, sung by Dorothea Fayne with Uwe Streibel (piano); 47 s from the voice's entry (20.6 s), faded in/out, level-matched | CC BY 3.0 |
| `finger-snap.png` | Wikimedia Commons, [Finger snapping impact frame.gif](https://commons.wikimedia.org/wiki/File:Finger_snapping_impact_frame.gif) by Boing747Ha — the hand cut out of its background (rembg, BiRefNet), cropped, wrist faded, re-saved as an animated PNG (rest pose, the two impact frames, snapped pose) | CC0 |
| `finger-snap-1.mp3` … `finger-snap-3.mp3` | Wikimedia Commons, [Finger clicks.ogg](https://commons.wikimedia.org/wiki/File:Finger_clicks.ogg) by cori — three single clicks (at 2.49, 3.75, 6.38 s), 0.35 s each, faded, loudness-normalised | Public domain |
| `stop-hand.png` | Wikimedia Commons, [Blinking Stop hand.gif](https://commons.wikimedia.org/wiki/File:Blinking_Stop_hand.gif) by I Seek To Help & Repair! (a derivative of [Stop hand.svg](https://commons.wikimedia.org/wiki/File:Stop_hand.svg) by Silsor) — its lit frame, unchanged; the blink is done in code | CC BY-SA 3.0 |
| `confetti.mp3` | Freesound, [partypopper.flac](https://freesound.org/people/Streety/sounds/26349/) by Streety, trimmed | CC0 |
| Clawd's moods (drawn in code, `ClawdMood.swift`) | faces, colours and emotes ported from John Heibel's [ClaudeAnimationBase](https://github.com/JohnHeibel/ClaudeAnimationBase) model sheet | MIT, © 2026 John Heibel |
| `icon_fx.png` | the menu bar's 𝓯𝔁 drawn large by `tools/make-icon.swift` | own work (MIT) |
