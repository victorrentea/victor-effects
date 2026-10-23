#!/usr/bin/env python3
"""Draft the karaoke timings for review: one folder per clip with the sung or
spoken cues force-aligned to the voice, and a picture to check them against.

    python3 tools/caption-align.py [OUT_DIR] [asset …]

Needs torch, torchaudio, demucs, librosa, soundfile, matplotlib and mlx_whisper
(a throwaway venv is fine). For each clip in `soundsDir` with a cue that is not
a [noise]:

1. **The voice alone** — Demucs (htdemucs, two stems) pulls the vocals out, so
   neither the aligner nor the eye is fooled by a drum hit or a bass note.
2. **Forced alignment of the text we already know** — the MMS_FA wav2vec2
   aligner is given each cue's words and only has to say *where* they are, which
   is far steadier than asking Whisper what was said and fuzzy-matching it.
   Whisper's own word starts are kept next to it as a second opinion.
3. **Vocal onsets** — librosa's onset detector on the vocal stem: where a sung
   syllable actually begins. A held note ends; the next word starts at an onset.
4. **`<asset>.png`** — the vocal spectrogram and loudness with all three marked,
   and **`<asset>.json`** with the numbers. A reviewer (human or agent) settles
   each word on the picture and writes the answer into `tools/caption-words.json`;
   `tools/caption-words.py` turns that file into Swift.
"""
import json, os, re, subprocess, sys, urllib.request

import numpy as np

BASE = os.environ.get("EFFECTS_URL", "http://127.0.0.1:55124")
WHISPER = "mlx-community/whisper-large-v3-mlx"


def words_of(text):
    """The caption's words, exactly as `SoundCaptions.wordEnds` counts them."""
    return [t for t in text.split() if any(c.isalnum() for c in t)]


def letters(word):
    return re.sub(r"[^a-z']", "", word.lower().replace("’", "'")) or "a"


def vocals(src, work):
    out = os.path.join(work, "htdemucs", os.path.splitext(os.path.basename(src))[0], "vocals.wav")
    if not os.path.exists(out):
        subprocess.run([sys.executable, "-m", "demucs", "--two-stems", "vocals", "-n", "htdemucs",
                        "-o", work, src], check=True, capture_output=True)
    return out


def whisper_words(src):
    import mlx_whisper
    r = mlx_whisper.transcribe(src, path_or_hf_repo=WHISPER, word_timestamps=True, language="en",
                               condition_on_previous_text=False)
    return [{"word": w["word"].strip(), "start": round(w["start"], 2), "end": round(w["end"], 2)}
            for s in r["segments"] for w in s.get("words", [])]


class Aligner:
    def __init__(self):
        import torch, torchaudio
        self.torch, self.ta = torch, torchaudio
        self.bundle = torchaudio.pipelines.MMS_FA
        self.model = self.bundle.get_model(with_star=True).eval()
        self.dict = self.bundle.get_dict(star="*")
        self.sr = self.bundle.sample_rate

    def align(self, wave16k, start, end, words):
        """Word starts (seconds into the clip) of `words` sung inside [start, end)."""
        torch, F = self.torch, self.ta.functional
        a, b = int(max(0, start) * self.sr), int(min(len(wave16k), end * self.sr))
        seg = torch.from_numpy(wave16k[a:b]).float().unsqueeze(0)
        with torch.inference_mode():
            emission, _ = self.model(seg)
        tokens = [letters(w) for w in words]
        flat = [self.dict["*"]]
        for t in tokens:
            flat += [self.dict[c] for c in t] + [self.dict["*"]]
        targets = torch.tensor([flat], dtype=torch.int32)
        ali, scores = F.forced_align(emission, targets, blank=0)
        ali, scores = ali[0], scores[0].exp()
        spans = F.merge_tokens(ali, scores)
        # spans follow `flat`; drop the stars, then regroup by word length
        star = self.dict["*"]
        spans = [s for s in spans if s.token != star]
        ratio = (b - a) / emission.size(1) / self.sr
        out, i = [], 0
        for t in tokens:
            chunk = spans[i:i + len(t)]
            i += len(t)
            out.append({"start": round(start + chunk[0].start * ratio, 2) if chunk else None,
                        "end": round(start + chunk[-1].end * ratio, 2) if chunk else None,
                        "score": round(float(np.mean([c.score for c in chunk])), 2) if chunk else 0})
        return out


def plot(path, voice, sr, duration, cues, onsets, rms, rms_t):
    import librosa, librosa.display, matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    width = max(12, duration * 2.2)
    fig, (ax, ax2) = plt.subplots(2, 1, figsize=(width, 7), sharex=True,
                                  gridspec_kw={"height_ratios": [3, 1]})
    S = librosa.amplitude_to_db(np.abs(librosa.stft(voice, n_fft=2048, hop_length=256)), ref=np.max)
    librosa.display.specshow(S, sr=sr, hop_length=256, x_axis="time", y_axis="linear", ax=ax, cmap="magma")
    ax.set_ylim(0, 4000)
    ax2.plot(rms_t, rms, color="black", lw=1)
    for o in onsets:
        ax2.axvline(o, color="orange", lw=0.8)
    for cue in cues:
        ax.axvline(cue["start"], color="cyan", lw=1.5, ls=":")
        for w, m in zip(cue["words"], cue["mms"]):
            if m["start"] is not None:
                ax.axvline(m["start"], color="lime", lw=1.2)
                ax.text(m["start"], 3850, w, color="lime", fontsize=10, rotation=90, va="top")
        for h in cue.get("whisper", []):
            ax.axvline(h["start"], color="red", lw=1, ls="--")
            ax.text(h["start"], 200, h["word"], color="red", fontsize=8, rotation=90, va="bottom")
    ax.set_title(f"{os.path.basename(path)}  — lime: MMS forced-align word start · red dashed: Whisper · "
                 f"cyan dotted: cue start · orange (below): vocal onsets")
    ax2.set_xticks(np.arange(0, duration + 0.01, 0.25), minor=True)
    ax2.set_xticks(np.arange(0, duration + 0.01, 1))
    ax2.grid(True, which="both", axis="x", alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=80)
    plt.close(fig)


def main():
    args = sys.argv[1:]
    out_dir = args.pop(0) if args and not args[0].endswith(".mp3") else os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "caption-align")
    os.makedirs(out_dir, exist_ok=True)
    cfg = json.load(open(os.path.expanduser("~/.victor-effects/config.json")))
    sounds = os.path.expanduser(cfg["soundsDir"])
    catalogue = json.load(urllib.request.urlopen(BASE + "/sounds/captions", timeout=30))
    import librosa
    aligner = Aligner()
    for asset in sorted(catalogue):
        if args and asset not in args:
            continue
        src = os.path.join(sounds, asset)
        cues = [dict(c) for c in catalogue[asset]["cues"] if not c["text"].startswith("[")]
        if not cues or not os.path.exists(src):
            continue
        all_cues = catalogue[asset]["cues"]
        duration = catalogue[asset]["durationSeconds"]
        voice, sr = librosa.load(vocals(src, os.path.join(out_dir, "_demucs")), sr=22050, mono=True)
        voice16 = librosa.resample(voice, orig_sr=sr, target_sr=16000)
        heard = whisper_words(vocals(src, os.path.join(out_dir, "_demucs")))
        onsets = [round(float(t), 2) for t in librosa.onset.onset_detect(y=voice, sr=sr, units="time", backtrack=True)]
        rms = librosa.feature.rms(y=voice, hop_length=256)[0]
        rms_t = librosa.times_like(rms, sr=sr, hop_length=256)
        for cue in cues:
            k = next(i for i, c in enumerate(all_cues) if c["start"] == cue["start"] and c["text"] == cue["text"])
            nxt = all_cues[k + 1]["start"] if k + 1 < len(all_cues) else duration
            cue["words"] = words_of(cue["text"])
            lo, hi = max(0, cue["start"] - 0.8), min(duration, nxt + 0.6)
            cue["mms"] = aligner.align(voice16, lo, hi, cue["words"]) if cue["words"] else []
            cue["whisper"] = [h for h in heard if lo <= h["start"] < hi]
        json.dump({"asset": asset, "durationSeconds": duration, "cues": cues, "vocalOnsets": onsets,
                   "whisperAll": heard}, open(os.path.join(out_dir, asset + ".json"), "w"), indent=1)
        plot(os.path.join(out_dir, asset + ".png"), voice, sr, duration, cues, onsets, rms, rms_t)
        print(f"{asset:28} " + " | ".join(
            f"{c['text']} {[m['start'] for m in c['mms']]}" for c in cues), file=sys.stderr)


if __name__ == "__main__":
    main()
