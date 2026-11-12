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

Several files are **not** plain playback (`EffectsEngine.playSound`): their visual
has to start from the same call as their audio, because the cue sits at a fixed
offset *inside* the clip and a separately-clocked visual slides off it — the
radar, the heartbeat's onsets, the FBI bangs, Beethoven's
six hits, the Sparta shield, the money round, the clipped applause. One more (`34_phoenix.mp3`)
is a silent placeholder on the client whose reported duration
is the *on-screen* life of the effect, so a non-restartable tile stays
"playing" for as long as the visual runs.

## Second takes are layer-B tiles, not alternations (since 2026-11-12)

Until 2026-11-12 two tiles were a **pair behind one press** (`AlternatingSounds`,
now deleted): #19 played `19_fail.mp3` and `20_fail2.mp3` in turns, #49 played
`49_wrong.mp3` and `49b_tiktok_core.mp3`. Victor: there are two sounds, so there
should be two buttons, and **no tile alternates any more**. Each second take is
now the `under` tile (layer B, the folded bottom-left corner) of its host in
`tiles.json`, and fires the host's desktop effect from `SoundEffectMap.onPress`:

| tile | file | picture | desktop |
|---|---|---|---|
| 19b | `20_fail2.mp3` (the second trombone) | `sfx_20_fail2.jpg` (FAIL #2) | `fail` |
| 49b | `49b_tiktok_core.mp3` (myinstants "TikTok Core") | `sfx_49_wrong.jpg`, the same as #49 | `wrong-x` |

**49b's note sounds at the midpoint of the X.** `showWrongX` draws for 0.5 s,
holds to 1.54 s and fades for 1.2 s: 2.74 s in all, midpoint **1.37 s**. The
delay is **1.37 s of silence inside the mp3**, with no timer in the code: the
press path starts `wrong-x` and the play path starts the file at the same moment,
and a routed clip's Bluetooth wake-up and output latency delay the picture by the
same amount (`currentPictureDelay`), so the file is the one clock they cannot
disagree on. The same re-cut made it **×1.3 louder** (+2.3 dB, peak −5.5 dBFS):
it was 0.9 s of lead-in, timed to the finished X, until then. Changing the X's
timings means re-cutting this lead-in (`silencedetect` should put the onset at
the new midpoint). A lead-in of silence stays the cheapest way to delay any
paired clip: `durationMs` and the stop path need no special case.

`20_fail2.mp3` still has no square of its own (#20 is the ⛈️ storm since
2026-09-19); as 19b it needs none.

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

**A sound and its picture start together: the invariant (2026-11-05).** Victor:
*"întotdeauna sunetele să pornească împreună cu animația … asta e un invariant"*.
What the room hears comes after the wake-up AND the speaker's own latency, so every
paired picture waits for both: `currentPictureDelay`, handed over by
`pendingVisualCompensation` or read directly by the visuals that own their audio.
The siren was the worst of them, 1.6 s early, because `/alarm/start` skipped the
hand-over altogether; it now goes through `runEffect` like the rest. Waiting for
the wake-up alone used to leave pictures ahead of the sound.

**Only the first sound waits, and hot lasts 2 s (2026-11-05).** A speaker that has
just played needs no wake-up, so a sound started during another, or within
`speakerHotMs` of the last one ending (`SpeakerWake`), gets no delay and no wake tone,
which is what lets two tiles be mixed at once. `currentBluetoothCompensation`
answers "how long until the speaker is awake", which is why two tiles pressed 0.3 s
apart land together instead of the second clipping into the tone, and why reading
it after starting a clip still gives that clip's wait. The clock runs from the real
end of the sound: a stop cuts it short (`fadeOutAndStop`), unless another clip is
still sounding. Only what `SoundManager` plays and the 🙏 hymn are counted; sounds
with their own player (chainsaw, AK-47) wake nothing here.

Measured on the JBL Go 4 with the laptop mic (Victor put the speaker next to it), a
400 ms 2 kHz tone from `AVAudioPlayer`, heard time from `play()`. Other apps
silent. A probe that used `AVAudioEngine` for the mic ran the output device and kept
the link hot, so the mic must be an input-only `AudioQueue`:

| after the last sound ended | heard after | of the 400 ms tone |
|---|---|---|
| 1.2–2 s | 360 ms | all of it |
| 3 s | 490 ms | mostly |
| 4–6 s | 400–720 ms | unreliable |
| 9 s and on, 30 s the same | 720–750 ms | **the first ~190 ms are lost** |
| any, with the 1.05 s wake tone | 1450 ms | all of it |

It fits the device, not the box: `AVAudioPlayer` keeps the output running ~2.3 s
past the end of a clip, and the sound starts clipping about when it stops (a guess
at the cause, nobody looked inside the link). JBL publishes no figure for any of this. Holding the link open with an inaudible tone would give
any window asked for, and Victor refused it: it eats the battery. The 30 Hz tone
gets the attack through in full. Even a silent Chrome audio service waking the
device resets all this, so a probe has to count the pause on the device itself
(`kAudioDevicePropertyDeviceIsRunningSomewhere`). The value shows read-only on the
tablet's ⋮ menu.

**The wake tone is 30 Hz (2026-11-05).** It was 220 Hz at the same −56 dBFS from
the start, and "near-silent" stopped being true once the Mac sat at 100 % volume
on two linked Go 4s with the slider at 1050 ms: a second of audible buzz before
every sound (the same hum the old keep-alive loop was removed for, below). It
now uses the nudge's frequency, which a palm-sized box barely moves air at; the
🔥 whip's warm loop shares the tone. **Not measured:** the laptop mic could not
separate it from the room on 2026-11-05, so whether the amp still spins up as
early on 30 Hz is a thing to listen for. If sound attacks start clipping, this
is the change to look at.

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

**A re-press is a stop too, for its own tile only.** Since effects overlap
(2026-10-29) a re-press ends one tile with `stopTile`, not `stopAll`, and that
path never moved the generation: on 2026-11-02 Hallelujah was re-pressed 0.6 s
into its 1050 ms gap, the clip stopped, and the angels came up half a second
later — silent, with `heaven/stop` already spent. The ticket now also carries
the effect's own stop count; `stopTile` bumps it (`stopped(effect:)`), so only
that tile's queued visual is outvoted and every other tile's still draws.

**A stop has to reach the pool the sound is in.** There are three, and
`cancelIfRunning` touches none of them unless told to:

| pool | filled by | stopped by |
|---|---|---|
| `tabletClips` | `playTabletSound*`, each with its `tile` | `stopTile`, `stopAll`, `stopWherever` |
| `players` | `play` | `stopAll`, `stop(name)`, `stopWherever`; NOT `stopTile` |
| `overlappingPlayers` | `playClip`, `playOverlapping` | **only `stopOverlapping(name)`** |

Nearly every tile's sound is a routed clip, so the tile's own key stops it. The
exceptions are sounds the EFFECT owns, which `stopEffect(named:)` has to name: the
🔥 phoenix, the 🛰️ radar and the 💣 raid's booms. A sound it forgets plays on over
an empty desktop (the phoenix, 5 s of it, 2026-11-05), so
`StopSilencesTheSoundTests` parses the pool and both stops. Escape stops its own
effect's sound by file and nothing else: tiles overlap.

## Keep-alive (`BluetoothKeepAlive`)

A JBL switches itself **off** after ~20 min without audio, even while
connected. While a Bluetooth speaker whose name contains
`EffectsConfig.bluetoothSpeakerNameMatch` is connected (via
`BluetoothOutput.speakerNameMatch`; **empty by default, which disables the
whole thing**), the app gives it a **nudge every 15 min**: 2 s of **30 Hz at
−45 dBFS** (600 ms fades), 11 dB over the −56 dBFS the speaker took for silence,
at a frequency a palm-sized box barely moves air at. It was −30 dBFS with 200 ms
fades until 2026-11-05, when Victor heard it in a quiet room ("too strong, it must
be inaudible"). **−45 is not measured against the box:** if a JBL starts dropping
18–19 min after connecting again, the nudge has fallen under its detector.
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

## Speaker battery (`SpeakerBattery`, 2026-10-29)

The tablet's top bar shows the JBL's battery next to the phone's, from three
flat `/ping` keys: `speakerChargePct` (-1 = none known), `speakerCharging`,
`speakerChargeAgeS`.

**macOS never knows it.** The Go 4 has no microphone, so no HFP — and the
HFP AT commands are where macOS gets every third-party battery it shows. It
declares only A2DP 1.4 + AVRCP 1.6 and exposes no Battery Service (0x180F).
What it does expose, over BLE, is the JBL Portable app's own channel: service
`65786365-6C70-6F69-6E74-2E636F6D0000` (the bytes spell `excelpoint.com`),
write to `…0002`, answers on notify `…0001`. `AA 11 00` gets a burst of
`AA 12 <len> 00 <token> <value…>` frames: `0x44` battery (low 7 bits %, top
bit charging), `0x48` the classic MAC, `0x42` the model (`20 E4` = Go 4),
`0xC1` the name. Found in JBLControl / jbl-charge5 (reverse-engineered on a
Flip 7 and a Charge 5), confirmed on Victor's Go 4 the same evening. Never
send `AA 01 02 82 00`: it wipes the speaker's usage counters.

**A visit, not a connection.** The speaker takes one control connection at a
time, so while we hold it the phone's JBL app cannot connect. Every 2 min
(first at +10 s): ask, and let go as soon as battery + MAC are in (6 s cap
per speaker).

**Over the Classic link, not over BLE adverts.** The same service is reachable
as GATT over the BR/EDR link the audio already uses:
`retrieveConnectedPeripherals(withServices:)` hands it over with no scan. That
is the first choice, because a Go 4 **stops advertising over BLE** a while
after it connects — on 2026-10-29 the adverts were gone ~10 min in, the
reading froze, and the one LE read it had given said 100 % where the Classic
path said 75 % (twice, same MAC). Only when nothing comes back that way does a
round fall back to scanning 6 s for Harman adverts (company `0x0057`).
Over that link, subscribing to `…0001` reports *"The attribute could not be
found"* and the answers arrive anyway — so the error is only logged into the
visit's stage, and the 6 s deadline is what ends a real silence. Every visit
that ends without a battery logs `🔊🔋 <name> gave no battery (stopped at: …)`.
A round that finds nobody to visit logs `🔊🔋 no JBL to visit: …` once (what
the Classic link and the scan saw, which MACs are connected and known) — until
2026-10-30 that case was silent and the tablet simply had no 🔊 chip.

**Hidden both ways → re-link once.** On 2026-10-30 a second Go 4
(`F3-69`) sat connected for hours with neither: no adverts, and nothing over
the Classic link, although its SDP lists ATT (PSM 31) for that very service
(opening PSM 31 ourselves with IOBluetooth fails — bluetoothd owns it). Dropping
the Classic link and having the Mac reopen it (`closeConnection` +
`openConnection`) brought the service back over the Classic link, and the next
round read 60 %. So a round that finds nobody to visit re-links the connected
speaker that has no *fresh* reading (`relinkCandidate`; fresh = under 10 min,
the tablet's own grey threshold — on 2026-11-03 yesterday's 100 % counted as
"read" and kept a speaker that reconnected hidden grey all morning): once per connection, only while
nothing plays into it (`kAudioDevicePropertyDeviceIsRunningSomewhere` **and** an audible process behind it — `audibleOutputProcesses`, minus `silentOutputHolders`: Wispr Flow's helper holds the output open in silence all day, and on 2026-11-03 that alone kept the re-link from ever running; a skip now logs `🔊🔋 not re-linking … yet: audio running (<bundle ids>)` once), and the
default output is put back if it was that speaker. The cost is ~6 s of the
speaker gone and its reconnect beep, once; it logs `🔊🔋 re-linking …`.

**Only this Mac's speakers.** A reading counts only if its MAC is a connected
audio output here — the keep-alive's own `targets`, matched against the
CoreAudio UID (`E8-26-CF-C6-97-0B:output`). An advertiser is visited once to
learn its MAC (`toVisit`); a JBL that turns out to be somebody else's is not
visited again. With two boxes connected the tablet gets the default output's,
else the emptiest (`pick`).

**Two boxes linked to each other** (2026-11-03). Two Go 4s linked by their
own Auracast button play as one: only the first is connected to the Mac, the
other takes the audio from it, refuses a page from the Mac (`openConnection`
times out) and advertises non-connectable only — so it cannot be reached
directly at all. It is reached *through* the first: the byte after `<len>`
is the box's index in the link (`00` the one we talk to, `01` the linked
one), and ~2 s after the first box's burst come, unasked, `01` frames with
the linked box's battery, firmware and serial (no `0x48` MAC). Until this
date the parser ignored that byte, so the linked box's 60 % overwrote the
connected one's 45 % whenever both landed in one visit — the log's 45 ↔ 60
flapping. Now `parseFrames` keeps them apart, a visit waits up to 3 s more
for the `01` battery when token `0x4F` is not a clear `00` (`01` on both
while linked; its unlinked value is a guess), and the linked box's reading is
dropped once a visit sees `0x4F` = `00` or it is 10 min old.

The re-link (*Hidden both ways* above) does not break the link: on
2026-11-03, with both boxes linked and playing, the first box came back from
a hidden reconnect only after a re-link, and the very next visit read both
(45 % and 60 %), the two boxes still playing together. The only cost is the
audio gap while the Mac's link is down.

**The level comes in steps.** Every value logged 3–5 Nov, on both boxes, draining
or charging, was one of 15, 45, 60, 75 or 100: `0x44` is not a fine gauge, so
`100` means "the top step", not "full". On 2026-11-05 the box with the ribbon
said 100 from 09:13 until 17:16 and then 75, with nothing in between; the other
one, off the charger by 12:18, still said 100 at 18:04 in a raw dump
(`AA 12 03 01 44 64`, serial `…8222`, against the connected box's `4B` = 75,
serial `…4533`). A 100 hours after unplugging is therefore normal, and the
linked box's value is live, not cached: it follows both charging and draining
in the log. (Why it can also be read wrongly: the 100 vs 75 over LE, above.)

`/ping` carries a second chip: `speaker2ChargePct` / `speaker2Charging` /
`speaker2ChargeAgeS` (same -1 when none) — the box linked to the first, else
the other connected one (`pickBoth`). The first chip's three keys are
unchanged, so a tablet that does not know `speaker2*` still shows the same
box as before.

Two identical boxes need telling apart, so `markedSpeakerMac` in the config
names the one wearing a physical mark, and `speakerMarked` / `speaker2Marked`
say which chip it is; the tablet draws a 🎗️ (no ring; a ① until 2026-11-05) before that chip's icon (Victor,
2026-11-04). A position would not do: the first chip is whichever box the Mac
holds. The linked box never says its MAC, so `marks` reads the second chip as
"the other one", which assumes two boxes in total.

**Grant.** CoreBluetooth needs `NSBluetoothAlwaysUsageDescription`
(`build-app.sh` writes it) and asks for the Bluetooth permission the first
time a JBL is connected — not before, the manager is created lazily. Denied →
one `🔊🔋 Bluetooth access denied` log line and the tablet shows no speaker.
Pinned by `SpeakerBatteryTests` (frames, UID parsing, choice, visit list).


## 🎚️ Held under Victor's voice while he screen-shares (`VoiceCeiling`, 2026-11-09)

On 2026-11-09, in a Zoom call with **Share sound** on, the soundboard came out far louder
than Victor's voice: his mic gain was low and the effects went to the room at full level.
He changes mics (lapel, Bose, the XLR on the Elgato, the built-in, usually through Krisp),
so no fixed attenuation fits — the voice is **measured**. Victor Addons does that
(`VoiceMeter`: K-weighted momentary loudness on the mic the meeting actually captures,
only while he is screen-sharing in Zoom or Teams) and **pushes** the result here:
`GET /voice/ref?sharing=1&ref=<LUFS>&src=live|held|previous|default` once a second during
a share, `sharing=0` when it ends. Push and not pull because addons is the one that sees
the share start and stop (the edge lands at once), nothing is sent or polled outside a
share, and a play here never waits on the other app — it uses the last value it was given,
and a value older than **60 s** is dropped, so a crashed addons cannot leave the board
muffled.

While a reference is on hand, **every** player is held so that

    M(file) + 20·log10(player volume) + system dB  ≤  voiceRef + offset

- `M(file)` — the loudest 3 s (EBU R128 short-term) of **the file actually played**: its
  ＋ render when it has one. Every audio file a player may open — `soundsDir`,
  `assetsDir`, the bundle's own sounds, the renders — is measured in the 🔺 hints'
  background pass (`RecommendedVolumes.ceilingFiles`, cached in `loudness-cache.json`).
  A file not measured yet counts as −10 LUFS (`unmeasuredLufs`), a silent one is never cut.
- player volume — what this app already multiplies in: the blue wedge × the tile's bar ×
  the mastering trim. So the left side is the clip's loudness + tile gain + global volume.
- **system dB** — the macOS output volume, but **only while the default output is
  `ZoomAudioDevice`**. Zoom's Share sound makes that virtual device the default output and
  reads its loopback; measured 2026-11-09 (a 1 kHz tone played into its output, captured
  from its input with ffmpeg): output volume scalar 1.0 → −44.1 dB, 0.25 → −56.1 dB, i.e.
  the device applies its own volume control, **−12.0 dB for 0.25**, before Zoom hears it.
  So a share with the volume keys turned down already sends the effects quieter, and that
  is credited. `Microsoft Teams Audio` looped nothing at all with Teams closed (−91 dB at
  both scalars), so for Teams — and any other output — nothing is credited: not knowing
  means capping harder, never softer. To be confirmed in a real Teams share.
- `offset` — `voiceCeilingOffsetDb` in `config.json`, **default −3** (−30…+12 accepted).

**Only ever lower**: `min(asked, allowed)`; a clip already under the line keeps its own
level and a quiet one is never raised to meet it (`VoiceCeilingTests.testNeverRaises`).
Where it is applied: `SoundManager.player(contentsOf:)` builds only `CeilingPlayer`s, an
`AVAudioPlayer` whose `volume` setter, `setVolume(_:fadeDuration:)` and first `play()` all
go through `VoiceCeiling.clamp` — every path (the routed press, the panel, the special
paths in `EmojiAnimator`, a live wedge or tile-bar drag, a fade-in) without a call site
that could forget it. The two `AVAudioEngine` sounds (minigun, chainsaw) are clamped at
construction. A share that starts or ends mid-clip re-levels the players still sounding
from what they were asked (`CeilingPlayer.reapplyAll`). Videos are played by addons, which
asks `GET /voice/ceiling?key=video:<id>&volume=<v>` at play time (0.4 s timeout; no answer
= its own level, logged) and keeps a live drag of the clip's bar under the same cap.

Every capped play is logged once, with what was taken off:

    🎚️ capped 01_baby.mp3 vol 1.00 → 0.35, −9.1 dB (clip -10.8 LUFS at +0.0 dB, sys +0.0 dB; voice -16.9 live -3.0 → ≤ -19.9)
    🎚️ kept 56_door_open.mp3 vol 0.50 → 0.50, under the voice (clip -16.1 LUFS at -6.0 dB, …)

**Calibration caveat.** The comparison is digital file loudness against the mic's digital
loudness (both counted as heard on two speakers: a mono mic as dual-mono, like a mono clip
here). What the meeting does next — Zoom's own mic AGC and its share-audio mix — is not
in the formula; that is what the −3 dB offset is for, and it is to be calibrated against a
local Zoom recording of a real share (Victor's checklist in the 2026-11-09 report).
