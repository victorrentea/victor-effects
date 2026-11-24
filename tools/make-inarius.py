#!/usr/bin/env python3
"""😇 Fable's other half: Inarius -> assetsDir/inarius.mov, HEVC with alpha + its sound.

    make-inarius.py <gemini.mp4> <masks-dir> <out.mov>

Victor's Gemini clip (2026-11-24, 1280x720, 24 fps, 10 s): a hooded angel in dark armour with
wings of golden light, beating them in place over black, sparks drifting. He does not come down
from above like Fable; Victor wanted him *"seen in flight, then slowing down until he stays,
wings open"*. So the clip is RETIMED, not cut:

    0 .. T1          the source at its own speed (the wings beat)
    T1 .. the end    s(t) = T1 + D (1 - e^-(t-T1)/D): the beat slows and never quite stops,
                     closing on HOLD, the top of an upbeat (wings raised in an open V,
                     tips just under the top edge) — a turning point, so the last
                     motion is already the slowest of the cycle

A slowed frame falls between two source frames, so the two are mixed (premultiplied, after the
key); without that the slowdown would stutter instead of gliding.

Keyed like 🔥 Grilled — his armour is dark grey on black, and Fable's luminance key alone would
leave him a see-through ghost:

    alpha  = max(BirefNet matte with its holes filled, glow key on max(R,G,B))   (0.03 -> 0.60, γ 0.85)
    colour = the source clamped to alpha (premultiplied: over black it IS the source)

Mattes from the video-remove-bg skill's venv, only for the frames the retime reaches:

    ffmpeg -i gemini.mp4 -fps_mode passthrough src/f_%04d.png
    rembg p -om -m birefnet-general src masks     # f_0001 .. f_0136, ~3.6 s/frame

Sound: the clip's own track, -14 LUFS, muxed in the SAME ffmpeg run (re-muxing an HEVC-alpha
stream with -c:v copy breaks it for AVFoundation).
"""
import math, subprocess, sys, tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_fill_holes

FPS = 24
LIFE = 10.0                        # = the clip's sound
HOLD = 134                         # 0-based source frame he settles on (t 5.58 s)
D = 1.2                            # seconds of source the slowdown still covers
T1 = HOLD / FPS - D                # the beat starts slowing here (4.38 s)
LO, HI, GAMMA = 0.03, 0.60, 0.85   # Fable's glow curve


def source_time(t: float) -> float:
    return t if t <= T1 else T1 + D * (1 - math.exp(-(t - T1) / D))


def keyed(src: Path, mask: Path) -> np.ndarray:
    s = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255
    m = np.asarray(Image.open(mask).convert("L").resize((s.shape[1], s.shape[0])), dtype=np.float32) / 255
    m = np.maximum(m, binary_fill_holes(m > 0.5))   # the black void inside his hood is a face, not a hole
    k = np.clip((s.max(axis=2) - LO) / (HI - LO), 0, 1) ** GAMMA
    a = np.maximum(m, k)
    return np.dstack([np.minimum(s, a[..., None]), a])


def main(clip: str, masks: str, out: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp, "src"); src.mkdir()
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", clip, "-fps_mode", "passthrough",
                        f"{src}/f_%04d.png"], check=True)
        cache: dict[int, np.ndarray] = {}

        def frame(i: int) -> np.ndarray:
            i = min(i, HOLD)
            if i not in cache:
                name = f"f_{i + 1:04d}.png"
                if not Path(masks, name).exists():
                    sys.exit(f"no matte for {name} in {masks}")
                cache[i] = keyed(Path(src, name), Path(masks, name))
            return cache[i]

        rgba = Path(tmp, "rgba"); rgba.mkdir()
        n = round(LIFE * FPS)
        for k in range(n):
            x = min(source_time(k / FPS) * FPS, HOLD)
            i, f = int(x), x - int(x)
            px = frame(i) if f < 1e-3 else frame(i) * (1 - f) + frame(i + 1) * f
            Image.fromarray(np.round(px * 255).astype(np.uint8), "RGBA").save(f"{rgba}/{k:04d}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y",
                        "-framerate", str(FPS), "-i", f"{rgba}/%04d.png", "-i", clip,
                        "-map", "0:v", "-map", "1:a",
                        "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9", "-q:v", "70",
                        "-pix_fmt", "bgra", "-tag:v", "hvc1",
                        "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000",
                        "-c:a", "aac", "-b:a", "160k", "-shortest", out], check=True)
    print(f"{out}: {n} frames, settles on source frame {HOLD}, {Path(out).stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
