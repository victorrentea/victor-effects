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
  able to leave a long clip blaring with no way to stop it. **Only a sound that
  had a pinging client behind it** (`PingWatchdog`: a ping within 12 s before
  the start, or after it). Until 2026-09-22 it asked only "is the last ping
  stale?", which is also true whenever the tablet is simply not connected — so
  every sound started from the Mac itself (right-⌘ panel, `/press/<n>`,
  `/test/*`) was cut at the next 5 s tick, a few seconds in, logged as
  `Client ping lost >12s`. `PingWatchdogTests` pins both halves.

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

Today the table holds one entry: **`19_fail.mp3` alternates with
`20_fail2.mp3`**, run by run (19 → 20 → 19 → …). The same trombone joke was
sitting on two squares of a 13-column board and the room only ever heard
whichever one Victor's thumb landed on; now one button carries both takes and the
second press of the evening is not the same noise as the first.

**`20_fail2.mp3` no longer has a tile at all** (2026-09-19). It kept square #20
and its `N/A` label for a week — the grid is numbered `#NN` **by position**, so
removing a row would renumber sixty tiles — but a labelled square is still a
square, and #20 was the only one the board had spare when the ⛈️ storm arrived
(`docs/overlay-effects.md`). The square is now the storm's; the clip stayed
exactly where it was, in `soundsDir`, as the second take it always was. That is
what "merged away" was supposed to mean all along: **a partner needs a file, not
a square.** Two things follow, and both are pinned by tests:

- Its `SoundEffectMap.onPress` entry is gone. The press path reports the *key* of
  a pair and never the file that was actually played, so that mapping could only
  ever have fired for a direct press of #20 — which no longer exists. Leaving it
  would have put a ⭐ on an asset with no tile, which `SoundEffectMapDriftTests`
  correctly reads as a renamed or deleted mp3.
- `AlternatingSoundsTests` checks the two halves of a cycle against **different**
  things now: the KEY must be a tile in `tiles.json` (something has to press it),
  every FILE must exist in `soundsDir` (something has to play it). A partner may
  carry no effect of its own, but never a *different* one from the key's — that
  would be a mapping which looks like it fires every other run and never fires at
  all.

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

**The delay is a gap the room keeps pressing into.** `runEffect` checks the
⏸️ hold when the request *arrives*, but the visual draws ~0.8 s later — and a
`stop-all` (the next tile's pre-press stop, a re-tap, the 🛑) or a suspend (a
crop) that lands inside that gap has already cleared the screen. Until
2026-10-05 the queued visual then appeared anyway, over the next tile's effect
or in the middle of the crop, with its paired `/stop` already spent. It is now
**outvoted, not cancelled** (`DeferredFires`, the `SoundboardPress.generation`
pattern): the fire takes a ticket when queued and `stopAll()` moves the
generation, so a stale ticket draws nothing and logs `⏸️ dropping deferred
effect`. The next tile's own visual is queued *after* its stop-all, so it keeps
its ticket.

## Keep-alive (`BluetoothKeepAlive`)

A JBL switches itself **off** after ~20 min without audio, even while
connected. While a Bluetooth speaker whose name contains
`EffectsConfig.bluetoothSpeakerNameMatch` is connected (via
`BluetoothOutput.speakerNameMatch`; **empty by default, which disables the
whole thing**), the app gives it a **nudge every 15 min**: 2 s of **30 Hz at
−30 dBFS** (200 ms fades) — loud enough for the speaker's silence detector, at
a frequency a palm-sized box barely moves air at and the ear barely hears.
Between nudges, **nothing** plays. A 30 s timer re-checks the connected
speakers and fires the nudges that are due.

**Why 15 min.** JBL publishes no auto-off figure for the Go 4 (the manual is
silent; its other portables are quoted at ~20 min), so the number comes from
our own log: with only a −56 dBFS tone playing — which the speaker counts as
silence — the Go 4 dropped 18–19 min after every connect, five times on 30 Sep
(18:22→18:41, 19:03→19:21, 19:43→20:01, 20:10→20:28, 20:36→20:54) and twice on
1 Oct (09:36→09:55, 10:00→10:18). 15 min plus at most one 30 s poll stays well
under 18. And the nudge does count as audio: the two hours on 1 Oct with a
nudge every 4 min (15:56→17:56) had no drop.

**No continuous tone, ever (2026-10-01).** From 2026-09-10 to 2026-10-01 the
keep-alive looped a −56 dBFS 220 Hz tone into the speaker non-stop, so the amp
would never mute between sounds and clip the start of the next one (the first
version, a 0.5 s burst every 30 s, had not been enough for that). It was a
mistake: the amp never idled, so the speaker **hummed audibly** in a quiet room
— switching the keep-alive off made the hum stop on the spot — and a stream
that never ends keeps the speaker's battery draining all day. The start-of-sound
clipping is the job of the per-sound wake-up compensation above; the 🔥 whip
keeps its own `startContinuousWarm()` loop, but only while it is on screen.
Do not bring back a loop that runs while nothing is happening.

Scope: **every connected** Bluetooth speaker matching the name, not only the
default output (also 2026-10-01). Victor carries two JBL boxes as each other's
spare; the one that was not the default got no audio at all, timed itself out,
and was already off when the other died. Each speaker gets its own nudge player,
pointed at it by CoreAudio UID (`AVAudioPlayer.currentDevice`). A device that
also has an **input** is skipped: that is a headset (HFP mic), e.g. the
"JBL TUNE500BT" the name would otherwise catch, and 30 Hz in a pair of
headphones is felt. The selection is `BluetoothKeepAlive.targets`, pinned by
`BluetoothKeepAliveTargetsTests`. Getting the spare *connected* in the first
place is the other app's job (`SpeakerReconnect` in victor-macos-addons). It is distinct from the wake-up compensation above —
that one warms the link immediately before each individual sound, this one stops
the speaker switching itself off *between* sounds.

**The ✅ / ⚪️ / 🚫 menu row** (2026-09-14). The keep-alive is the one thing in
this app with a row of its own that nothing routes to, and it earned it twice
over: the nudge is near-inaudible by design, so a working keep-alive and a broken one
looked identical outside the log, and "stop playing into that speaker" has to be
possible in the middle of a recording or a call without quitting the app. The
row is a live read at menu-open time — ✅ a speaker is connected and being nudged, ⚪️ armed but
no speaker that needs it is connected, 🚫 switched off (or no
`bluetoothSpeakerNameMatch` configured, which can never become ⚪️: idle promises
a speaker it would start for). Clicking toggles the switch and cuts a nudge in
flight *now*, not at the next tick. The choice is persisted (`KeepAliveSettings`,
`UserDefaults` key `BluetoothKeepAlive.enabled`, **default on**) because this app
is restarted several times an hour and the reason to switch it off outlives a
relaunch; the 30 s poll keeps running while it is off, since that poll is what
notices the switch coming back. The three-way mapping is pure
(`BluetoothKeepAlive.state(enabled:configured:playing:)`) and pinned by
`BluetoothKeepAliveStateTests`.
