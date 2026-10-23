#!/usr/bin/env python3
"""Regenerate Sources/VictorEffects/SoundCaptionWords.swift: when each word of
every spoken or sung caption is heard in its clip, for the karaoke fill.

    /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 tools/caption-words.py

(any Python with `mlx_whisper`). Reads the cues the running app would show
(`GET /sounds/captions`, so the text is exactly what `SoundCaptions.schedule`
draws), Whispers each clip from `soundsDir` with word timestamps, and aligns the
caption's words to the heard ones with a fuzzy LCS — "Shady's" still lands on
Whisper's "Shaney's". A cue where fewer than half the words are heard is left
out: it keeps the even pace, which is honest for [noises] and instrumentals.
Prints one report line per cue; read it before committing.
"""
import difflib, json, os, re, sys, urllib.request

BASE = os.environ.get("EFFECTS_URL", "http://127.0.0.1:55124")
MODEL = "mlx-community/whisper-large-v3-mlx"
OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "VictorEffects", "SoundCaptionWords.swift")
SHORT_LEAD = 0.6
CACHE = os.path.join(os.environ.get("TMPDIR", "/tmp"), "caption-words-cache")


def words_of(text):
    """The caption's words, exactly as `SoundCaptions.wordCount` counts them."""
    return [t for t in text.split() if any(c.isalnum() for c in t)]


def norm(w):
    return re.sub(r"[^a-z0-9]", "", w.lower())


def similar(a, b):
    a, b = norm(a), norm(b)
    return bool(a) and bool(b) and (a == b or difflib.SequenceMatcher(None, a, b).ratio() >= 0.6)


def align(caption, heard):
    """Fuzzy LCS: caption word index -> heard word index."""
    n, m = len(caption), len(heard)
    L = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            L[i][j] = L[i + 1][j + 1] + 1 if similar(caption[i], heard[j]["word"]) else max(L[i + 1][j], L[i][j + 1])
    out, i, j = {}, 0, 0
    while i < n and j < m:
        if similar(caption[i], heard[j]["word"]) and L[i][j] == L[i + 1][j + 1] + 1:
            out[i] = j; i += 1; j += 1
        elif L[i + 1][j] >= L[i][j + 1]:
            i += 1
        else:
            j += 1
    return out


def transcribe(path):
    os.makedirs(CACHE, exist_ok=True)
    cached = os.path.join(CACHE, os.path.basename(path) + ".json")
    if os.path.exists(cached) and os.path.getmtime(cached) > os.path.getmtime(path):
        return json.load(open(cached))
    import mlx_whisper
    r = mlx_whisper.transcribe(path, path_or_hf_repo=MODEL, word_timestamps=True, language="en",
                               condition_on_previous_text=False)
    heard = [{"word": w["word"].strip(), "start": w["start"]} for s in r["segments"] for w in s.get("words", [])]
    json.dump(heard, open(cached, "w"))
    return heard


def onsets(cue, end, heard):
    caption = words_of(cue["text"])
    if not caption:
        return None
    window = [h for h in heard if cue["start"] - 0.6 <= h["start"] < end + 0.3]
    hit = align(caption, window)
    if len(hit) * 2 < len(caption):
        return None
    t = [None] * len(caption)
    for i, j in hit.items():
        t[i] = max(cue["start"], float(window[j]["start"]))
    # Words Whisper missed: between two heard ones, evenly; at either end, 0.25 s a word.
    known = sorted(hit)
    for i in range(len(caption)):
        if t[i] is not None:
            continue
        before = max((k for k in known if k < i), default=None)
        after = min((k for k in known if k > i), default=None)
        if before is not None and after is not None:
            t[i] = t[before] + (t[after] - t[before]) * (i - before) / (after - before)
        elif after is not None:
            t[i] = max(cue["start"], t[after] - 0.25 * (after - i))
        else:
            t[i] = t[before] + 0.25 * (i - before)
    # Whisper starts a word where the previous one ended, so a short word after
    # a held note ("Hello… is it me") lights up seconds early. A word of three
    # letters or less is not sung for longer than SHORT_LEAD: pull it to its
    # next word. Long words keep their hold (everywhere, Hallelujah).
    for i in range(len(t) - 2, -1, -1):
        if len(norm(caption[i])) <= 3:
            t[i] = max(t[i], t[i + 1] - SHORT_LEAD)
    for i in range(1, len(t)):
        t[i] = max(t[i], t[i - 1])
    return [round(x, 2) for x in t]


def main():
    cfg = json.load(open(os.path.expanduser("~/.victor-effects/config.json")))
    sounds = os.path.expanduser(cfg["soundsDir"])
    cues_by_asset = json.load(urllib.request.urlopen(BASE + "/sounds/captions", timeout=30))
    table = {}
    for asset in sorted(cues_by_asset):
        cues = cues_by_asset[asset]["cues"]
        spoken = [c for c in cues if not c["text"].startswith("[")]
        if not spoken or not os.path.exists(os.path.join(sounds, asset)):
            continue
        heard = transcribe(os.path.join(sounds, asset))
        for k, cue in enumerate(cues):
            if cue["text"].startswith("["):
                continue
            end = cues[k + 1]["start"] if k + 1 < len(cues) else cues_by_asset[asset]["durationSeconds"]
            t = onsets(cue, end, heard)
            mark = "✓" if t else "· even"
            print(f"{mark:7} {asset:28} {cue['start']:5.1f}  {cue['text']}  {t or ''}", file=sys.stderr)
            if t:
                table.setdefault(asset, []).append((cue["start"], t))

    lines = []
    for asset in sorted(table):
        rows = ",\n".join(f"            ({at:g}, [{', '.join(f'{x:g}' for x in t)}])" for at, t in table[asset])
        lines.append(f'        "{asset}": [\n{rows}],')
    swift = f"""import Foundation

// GENERATED by tools/caption-words.py — do not edit by hand; rerun it after a
// caption, a lyric line or a clip changes (it Whispers the clips in soundsDir).

extension SoundCaptions {{
    /// When each word of a spoken or sung cue is heard, in seconds into the
    /// clip: per asset, the cue's start (`CaptionLine.at`) and one onset per
    /// word as `wordCount` counts them. A cue not listed — a [noise], an
    /// instrumental title, a word Whisper could not hear — fills at an even pace.
    static let wordTimes: [String: [(at: TimeInterval, words: [TimeInterval])]] = [
{chr(10).join(lines)}
    ]
}}
"""
    open(OUT, "w").write(swift)
    print(f"wrote {os.path.normpath(OUT)}: {sum(len(v) for v in table.values())} timed cues", file=sys.stderr)


if __name__ == "__main__":
    main()
