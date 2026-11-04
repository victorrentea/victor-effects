# 🎤 The karaoke tuner

A web page for retiming any clip's subtitles, from a phone or a laptop:
`https://victorrentea.ro/karaoke/` (behind a password; code in the `victorrentea.ro`
repo, `karaoke/`). It runs on the cPanel host and not on this Mac, so it works with
the Mac shut, and nothing of this app's HTTP surface is exposed to the internet.

```
 app (55124)  ── /sounds/captions/base + clips ──▶  tools/karaoke-sync.py  ──▶  site
 app  ◀── re-read on the next press ── ~/.victor-effects/caption-edits.json ◀──  site
```

- **`tools/karaoke-sync.py`** runs every 2 minutes (LaunchAgent
  `ro.victorrentea.karaoke-sync`, `… install`, log in `/tmp/karaoke-sync.log`). Up:
  the app's own cues and the clips, only when they moved. Down: the edits. The clips
  go over FTPS, because the host's firewall answers 403 to a binary POST.
- **`CaptionEdits`** reads `caption-edits.json` on every press and reparses when the
  file moved. A clip listed there shows exactly those lines, no build, no restart.
  A broken file means no edits, never a silent press.
- **`SoundCaptions.schedule` never sees the edits**, on purpose: it is what the tests
  pin, and `build-app.sh` must not fail because a word was moved on a phone. Only the
  two live paths go through `SoundCaptions.live`: the press and `/sounds/captions`.

## Which timing wins

The edits are Victor's own data, like `sound-gains.json`: next to the config, not in
this repo. **An edited clip hides later changes to `lyrics` / `caption-words.json`
for that clip.** The ⟲ button in the tuner drops the clip's edits and goes back to
what the app ships with. To bake a tuning into the shipped table, copy the clip's
cues from `caption-edits.json` to `tools/caption-words.json` and `SoundCaptions.lyrics`,
then press ⟲.

## What can be tuned

The Mac's model and nothing else: a line's `at`, its `text`, one onset per word, and
`lastWordEnd`, when a note held at the end of the line is full. Only the last word
has an end: the others sweep to the next onset (`maxWordSweep`), and without
`lastWordEnd` the last one sweeps for `lastWordSweep`. A timed line goes up `leadIn`
before its first word whatever its `at` says, so the tuner only offers `at` on an
untimed line.

`karaoke/core.js` is a port of `wordEnds`, `fill`, `schedule` and `ahead`, so the
preview is what the room sees. **A change to those constants has to be made there
too** (`node tools/karaoke/core.test.js`, there).
