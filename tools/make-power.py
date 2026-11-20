#!/usr/bin/env python3
"""⚡ Unlimited power (⌘⌃6): Victor's Gemini clip -> assetsDir/power.mov, HEVC with alpha + its sound.

    make-power.py <gemini.mp4> <masks-dir> <out.mov>

The clip (1280x720, 24 fps, 10 s, on BLACK): two old hands in dark robe sleeves rise from the
bottom edge (0-1.3 s), sparks crawl between their fingers, then from ~2.4 s blue lightning
shoots from the fingertips until it fills the frame, to the end.

Keyed like 🔥 Grilled (tools/make-grilled.py):

    alpha = max(BirefNet matte, glow key on the brightest channel)
    colour = the source, clamped to alpha  (= premultiplied: over black it IS the source)

so the hands and the dark sleeves stay solid and the lightning lights the desktop.

**The ending closes the circle** (Victor: "loop it backwards … pulling the hands down at the
end"): after the last frame the storm cross-fades in XFADE frames into CALM (hands up, no
lightning yet), then the clip runs BACKWARDS from CALM to its first frame, so the hands sink
out of the bottom edge. The sound does the same: the storm fades out while the opening hum,
reversed, goes down with the hands.

Mattes: the video-remove-bg skill's venv, one PNG per matted source frame, same name:

    ffmpeg -i gemini.mp4 -fps_mode passthrough src/f_%04d.png
    rembg p -om -m birefnet-general src masks        # ~10 s/frame niced on 2 threads

Every frame up to f_0040 (the hands are still rising) needs its own matte; after that the hands
barely move, so every third frame is enough: a frame without one takes the max of the nearest
matted frames before and after it (a hair wider than the hand, never narrower).
"""
import subprocess, sys, tempfile
from pathlib import Path

import numpy as np
from PIL import Image

FPS = 24
CALM = 31             # f_0031 = hands fully up, before the first spark
XFADE = 12            # 0.5 s from the full storm back to CALM
LO, HI, GAMMA = 0.03, 0.60, 0.85   # Fable's / Grilled's glow curve


def load_mask(path: Path, size) -> np.ndarray:
    return np.asarray(Image.open(path).convert("L").resize(size), dtype=np.float32) / 255


def matte(masks: Path, frames: list, i: int, size) -> np.ndarray:
    """Frame i's own matte, else the max of the nearest matted frames on either side."""
    own = masks / frames[i].name
    if own.exists():
        return load_mask(own, size)
    near = [j for j in (next((j for j in range(i - 1, -1, -1) if (masks / frames[j].name).exists()), None),
                        next((j for j in range(i + 1, len(frames)) if (masks / frames[j].name).exists()), None))
            if j is not None]
    if not near or min(abs(j - i) for j in near) > 3:
        sys.exit(f"no matte near {frames[i].name} in {masks}")
    return np.maximum.reduce([load_mask(masks / frames[j].name, size) for j in near])


def frame_rgba(src: Path, m: np.ndarray) -> np.ndarray:
    s = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255
    k = np.clip((s.max(axis=2) - LO) / (HI - LO), 0, 1) ** GAMMA
    a = np.maximum(m, k)
    rgb = np.minimum(s, a[..., None])
    return np.dstack([rgb, a])


def main(clip: str, masks: str, out: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp, "src"); src.mkdir()
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", clip, "-fps_mode", "passthrough",
                        f"{src}/f_%04d.png"], check=True)
        frames = sorted(src.glob("f_*.png"))
        size = Image.open(frames[0]).size
        keyed = lambda i: frame_rgba(frames[i], matte(Path(masks), frames, i, size))   # 0-based
        rgba = Path(tmp, "rgba"); rgba.mkdir()
        n = 0
        def put(px: np.ndarray) -> None:
            nonlocal n
            Image.fromarray(np.round(px * 255).astype(np.uint8), "RGBA").save(f"{rgba}/{n:04d}.png")
            n += 1
        for i in range(len(frames)):                       # forward: rise, sparks, storm
            put(keyed(i))
        last, calm = keyed(len(frames) - 1), keyed(CALM - 1)
        for j in range(1, XFADE + 1):                      # storm -> calm (premultiplied: a plain lerp)
            t = j / (XFADE + 1)
            t = t * t * (3 - 2 * t)
            put(last * (1 - t) + calm * t)
        for i in range(CALM - 1, -1, -1):                  # backwards: the hands sink
            put(keyed(i))

        main_s = len(frames) / FPS
        tail_s = (XFADE + CALM) / FPS
        audio = (f"[1:a]atrim=0:{main_s:.3f},asetpts=PTS-STARTPTS,"
                 f"afade=t=out:st={main_s - 0.5:.3f}:d=0.5[a];"
                 f"[1:a]atrim=0:{tail_s:.3f},asetpts=PTS-STARTPTS,areverse,"
                 f"afade=t=in:d=0.4,afade=t=out:st={tail_s - 0.4:.3f}:d=0.4[b];"
                 f"[a][b]concat=n=2:v=0:a=1,loudnorm=I=-14:TP=-1.5:LRA=11[aout]")
        subprocess.run(["ffmpeg", "-v", "error", "-y",
                        "-framerate", str(FPS), "-i", f"{rgba}/%04d.png",
                        "-i", clip,
                        "-filter_complex", audio,
                        "-map", "0:v", "-map", "[aout]",
                        "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9", "-q:v", "70",
                        "-pix_fmt", "bgra", "-tag:v", "hvc1",
                        "-ar", "48000", "-c:a", "aac", "-b:a", "160k", "-shortest", out], check=True)
    print(f"{out}: {n} frames ({n / FPS:.2f} s), {Path(out).stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
