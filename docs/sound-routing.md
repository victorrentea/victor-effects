# Sound Routing & Bluetooth Speakers

The soundboard half: where the audio lives, how a client hands playback over to
this Mac, why an interrupted sound fades, and the two Bluetooth-**speaker**
mitigations. Bluetooth here means the boxes plugged into the laptop's ears —
playback hygiene — never networking.

## Where the sounds are: `soundsDir`

**No soundboard audio is in this repo.** The app reads a folder of
`NN_name.mp3` files named by `EffectsConfig.soundsDir`
(`~/.victor-effects/config.json`, env `VICTOR_EFFECTS_SOUNDS_DIR`). The same
folder holds `sound-timing.json` and, for the panel, `tiles.json` + `tiles/`.

`SoundManager.sharedSoundsDir()` resolves it and logs **once** when it is
missing; `soundURL(for:)` falls back to the handful of sounds bundled with the
app itself (`click.wav`, `phoenix.mp3`, `confetti.mp3`, `whip_A..E.mp3`).
`GET /config/reload` re-reads the path and clears the warning
(`resetSoundsDirWarning`).

The old arrangement — a folder symlink dereferenced into the app bundle at build
time — is gone with the extraction. The consequence is worth stating plainly:
**the manifest is computed over the live folder, so replacing an mp3 needs no
rebuild.** There is no such thing as a stale bundle any more; the hash simply
follows the folder.

## Routed playback

A client that has no speaker of its own (the tablet, when it has no Bluetooth
box and no wired headphones) hands playback to the Mac instead of playing
locally:

- `GET /sound/play/<file>?vol=<0-100>` — one sound at a time; a new play
  **preempts** the current one. Answers `{ok, durationMs}`, from which the
  client schedules its own stop chain. **404** for an unknown file, which the
  client reads as "play it yourself".
- `GET /sound/stop`, and `/effect/stop-all` which also stops it.
- `GET /sound/volume/<pct>` — player-level volume, never the macOS system
  volume; plays `click.wav` at the new level as feedback.
- **Watchdog**: the routed sound is stopped if `/ping` stops arriving for >12 s
  (`EffectsEngine.startWatchdog`) — a crashed or disconnected client must not be
  able to leave a long clip blaring with no way to stop it.

Seven files are **not** plain playback (`EffectsEngine.playSound`): their visual
has to start from the same call as their audio, because the cue sits at a fixed
offset *inside* the clip and a separately-clocked visual slides off it — the
radar, the microwave's bing, the heartbeat's onsets, the FBI bangs, Beethoven's
six hits, the money round, the clipped applause. Two more (`34_phoenix.mp3`,
`80_badumtss.mp3`) are silent placeholders on the client whose reported duration
is the *on-screen* life of the effect, so a non-restartable tile stays
"playing" for as long as the visual runs.

## One button, two clips (`AlternatingSounds`)

A few tiles are a **pair behind one press**. `EffectsEngine.playSound` resolves
the requested file through `AlternatingSounds.shared.next(for:)` before anything
else, so the whole method — the special cases above, the `durationMs` handed
back, `playing` in `/state`, the log line — speaks about the file that is really
being played and not the one that was asked for.

Today the table holds one entry: **#19 `19_fail.mp3` alternates with #20
`20_fail2.mp3`**, run by run (19 → 20 → 19 → …). The same trombone joke was
sitting on two squares of a 13-column board and the room only ever heard
whichever one Victor's thumb landed on; now one button carries both takes and the
second press of the evening is not the same noise as the first. Tile #20 keeps
its asset and its artwork — the grid is numbered `#NN` **by position**, so
removing a row would renumber sixty tiles — and is labelled **`N/A`** in
`tiles.json` to say it is no longer its own press.

Three properties are deliberate:

- **The cursor is in memory only.** A restart begins each pair at its first file.
  The point is variety within a session, not a ledger across them, and nothing on
  disk is worth the alternation being one file "off" after a crash mid-workshop.
- **The client knows nothing about it.** The table is keyed by the asset the
  client presses and its first entry is that same asset, so the tablet, the
  panel and every script keep sending `/sound/play/19_fail.mp3`. The paired
  `/sound/pressed/19_fail.mp3` still fires `fail` — the effect belongs to the
  press, the alternation only to the audio — which is why both files of a cycle
  must carry the *same* desktop effect (`AlternatingSoundsTests` asserts it).
- **Pressing a partner directly is left alone.** `20_fail2.mp3` played by name is
  `20_fail2.mp3`, exactly as before: one entry point per pair keeps "what does
  this press do" answerable by reading one row.

Adding the next pair is one line in `AlternatingSounds.defaultTable`.

## Interrupted sounds fade, they never cut

Every early end routes through one helper, `fadeOutAndStop(_:over:)`, with
`SoundManager.interruptFade` = **0.2 s** (it was 3 s for a day; audibly too
long). Re-pressing the playing tile, pressing a different tile, `stop-all`, the
lost-ping watchdog, an effect's own toggle-off — all of them fade. An abrupt
`AVAudioPlayer.stop()` is a hard edge a whole room hears; in a quiet room the
silence lands harder than the sound did. The outgoing clip keeps playing *under*
the incoming one for those 0.2 s: a crossfade, not a gap.

Two mechanics make it work:

- **A fading player is retained in a `fadingOut` pool.** The caller has already
  dropped it, and a released `AVAudioPlayer` stops dead — the exact hard cut the
  fade exists to remove.
- **`fadeOutAndStop` no-ops on a player that is not playing.** That is what
  keeps the fade off the *natural* end of a sound: the `/sound/stopped/<file>` →
  `<effect>/stop` chain calls the same stop functions after the clip has already
  finished, so passing the interrupt fade there costs nothing. The natural-end
  paths that *do* still hold audio keep the older 0.3 s tail — the visual has
  just ended and a longer tail would outlive it. `fade: 0` forces the old
  instant stop.

## Anti-drift: the manifest

`SoundsManifest` hashes every `*.mp3` in `soundsDir` (SHA-256), in a canonical
form that the Android client reproduces byte for byte:

```
files sorted by name, one "<filename>:<sha256-hex-lowercase>\n" line each
combined hash = SHA-256 of the concatenated lines
```

`GET /sounds/manifest` returns the per-file map; `/ping` carries only the
combined `soundsHash`. A client whose own hash differs plays the differing files
itself.

Two properties are load-bearing:

- **`cachedCombinedHash` never blocks.** `/ping` is answered through a proxy
  that allows about 1.5 s, and hashing ~15 MB cold takes longer. The cache is
  keyed on `soundsDir`'s own mtime (one `stat` per ping catches an edited
  folder), warmed off the main thread at launch (`SoundsManifest.warm()`), and
  an **empty** hash is a defined answer — the client skips the comparison —
  whereas a timed-out ping looks like the whole app is down.
- **An empty result is never cached.** An unreadable folder for one instant
  would otherwise have the app advertise a bogus hash for the rest of its life.

## Bluetooth wake-up compensation

When the Mac's **own** default output is a Bluetooth speaker, a short
near-silent "wake" tone is prepended before a sound so the A2DP amp is spun up
and the attack is not clipped, and the paired **visual is delayed by the same
amount** so it stays in sync with the silence-prefixed audio
(`EffectsEngine.runEffect` → `SoundManager.consumePendingVisualCompensation`).

The value lives in `SoundTimingConfig`: the file default comes from
`soundsDir/sound-timing.json` (`macBluetoothCompensationMs`, currently 800 ms),
and `setBluetoothCompensation(seconds:)` stores a runtime override clamped to
`0…maxCompensationSeconds` (1.2 s) that wins over it. The override is
**not persisted here** — the client that owns the slider pushes it on
`GET /bt-compensation/<ms>` and re-pushes on every reconnect, because this app
resets to the file default on restart. `GET /bt-compensation` reads it back as
`{"ms":…,"maxMs":1200}`.

`green-flash` is the one effect that takes `currentBluetoothCompensation`
directly rather than consuming a pending one: it is the visual half of an
audible "the link works" tap, and firing it immediately lit the border up to
1.2 s before the beep reached the speaker, which reads as two separate events.

## Keep-alive (`BluetoothKeepAlive`)

Bluetooth speakers mute their amplifier after a few seconds of silence and then
clip the start of the next sound. While the current default output is a
Bluetooth speaker whose name contains `EffectsConfig.bluetoothSpeakerNameMatch`
(via `BluetoothOutput.speakerNameMatch`; **empty by default, which disables the
whole thing**), the app keeps a **continuously looping** near-silent tone
playing (≈ −56 dBFS, a 2 s lap faded at both ends so the loop boundary cannot
click), so the stream — and the amp — never sees silence. A 30 s timer only
re-checks the output and restarts a player that died on a route change or a
sleep/wake.

**Why continuous** (2026-09-10): the first version played a 0.5 s burst every
30 s and stopped keeping a JBL Go 4 awake — 29.5 s of every 30 were silence, so
each burst only arrived to re-wake an already-muted amp with its own first
moments swallowed, and the clipping came back. The whip already knew this
(`BluetoothOutput.startContinuousWarm()` exists precisely because a periodic
tone cannot give a crack zero spin-up lag); the keep-alive now uses the same
shape with **its own player**, so the whip starting or stopping its warm never
cuts the keep-alive's loop.

Scope is deliberately narrow: only the *active* output, and only speakers that
actually standby-mute. It is distinct from the wake-up compensation above —
that one warms the link immediately before each individual sound, this one stops
the speaker ever falling into standby *between* sounds.

**The 🔵 / ⚪️ / 🚫 menu row** (2026-09-14). The keep-alive is the one thing in
this app with a row of its own that nothing routes to, and it earned it twice
over: the tone is inaudible by design, so a working keep-alive and a broken one
looked identical outside the log, and "stop playing into that speaker" has to be
possible in the middle of a recording or a call without quitting the app. The
row is a live read at menu-open time — 🔵 the tone is playing, ⚪️ armed but the
default output is not a speaker that needs it, 🚫 switched off (or no
`bluetoothSpeakerNameMatch` configured, which can never become ⚪️: idle promises
a speaker it would start for). Clicking toggles the switch and takes the tone
down *now*, not at the next tick. The choice is persisted (`KeepAliveSettings`,
`UserDefaults` key `BluetoothKeepAlive.enabled`, **default on**) because this app
is restarted several times an hour and the reason to switch it off outlives a
relaunch; the 30 s poll keeps running while it is off, since that poll is what
notices the switch coming back. The three-way mapping is pure
(`BluetoothKeepAlive.state(enabled:configured:playing:)`) and pinned by
`BluetoothKeepAliveStateTests`.
