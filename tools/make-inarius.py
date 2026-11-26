#!/usr/bin/env python3
"""😇 Fable's other half: Inarius -> assetsDir/inarius.mov, HEVC with alpha + its sound.

    make-inarius.py <gemini.mp4> <out.mov>

Victor's third Gemini clip of him (2026-11-24 evening, 1280x720, 24 fps, 10 s), shot on a GREEN
SCREEN: the hooded angel in dark armour comes down from above the top edge, opens his wings of
golden light, beats them a few times and ends with them open in a V. It already does what the
earlier black-background clip had to be retimed into (seen arriving, then staying), so it plays
as it is, whole.

Keyed by green UNMIXING, not a hard chroma key: the wings and the sparks are a see-through glow
over the green, and a hard key either cuts them out or leaves them tinted green. With B the
screen's green (median of the frame's border), every pixel is read as  I = C·a + B·(1-a):

    a      = 1 - clip(spill(I) / spill(B), 0, 1),  spill(x) = G - max(R, B)   (then a small
             floor/ceiling stretch, so the screen's noise is 0 and the armour is 1)
    colour = I - B·(1-a)                         (premultiplied: the glow keeps only what it adds)
             then G <= 0.92 R (the solid wing is G/R 0.94; the fringes went yellow-green without), and
             where a channel still exceeds a, a is RAISED to it — clamping each channel down
             to a instead cut the red and kept the green, and the wing fringes came out lime

His dark armour has no green excess -> a = 1; the bare screen -> a = 0; a glow pixel gets the
alpha of how much the green under it is washed out, and its colour without the green.

2026-11-27: Victor's next clip (same size, rate and length, same green screen) adds a flaming
sword in his right hand and fades into the green over the last second; keyed unchanged.

Sound: the clip's own track, -14 LUFS, muxed in the SAME ffmpeg run (re-muxing an HEVC-alpha
stream with -c:v copy breaks it for AVFoundation).
"""
import subprocess, sys, tempfile
from pathlib import Path

import numpy as np
from PIL import Image

FPS = 24
LO, HI = 0.08, 0.92                # alpha stretch: screen noise -> 0, near-solid -> 1


def keyed(src: Path) -> np.ndarray:
    s = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255
    border = np.concatenate([s[:8].reshape(-1, 3), s[-8:].reshape(-1, 3),
                             s[:, :8].reshape(-1, 3), s[:, -8:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    spill_bg = bg[1] - max(bg[0], bg[2])
    spill = s[..., 1] - np.maximum(s[..., 0], s[..., 2])
    a0 = 1 - np.clip(spill / spill_bg, 0, 1)                 # the alpha the unmix needs
    c = np.clip(s - bg * (1 - a0[..., None]), 0, None)        # premultiplied by a0
    c[..., 1] = np.minimum(c[..., 1], 0.92 * c[..., 0])       # despill: his wings keep G/R ~0.94
    a = np.clip((a0 - LO) / (HI - LO), 0, 1)                  # the alpha shown
    c = c * (a / np.maximum(a0, 1e-3))[..., None]             # same straight colour, new alpha
    c = np.minimum(c, 1)
    a = np.maximum(a, c.max(axis=2))   # a glow brighter than its alpha raises the alpha; clamping
    return np.dstack([c, a])           # each channel to it instead cut R, kept G: lime fringes


def main(clip: str, out: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp, "src"); src.mkdir()
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", clip, "-fps_mode", "passthrough",
                        f"{src}/f_%04d.png"], check=True)
        rgba = Path(tmp, "rgba"); rgba.mkdir()
        frames = sorted(src.glob("f_*.png"))
        for k, f in enumerate(frames):
            Image.fromarray(np.round(keyed(f) * 255).astype(np.uint8), "RGBA").save(f"{rgba}/{k:04d}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y",
                        "-framerate", str(FPS), "-i", f"{rgba}/%04d.png", "-i", clip,
                        "-map", "0:v", "-map", "1:a",
                        "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9", "-q:v", "70",
                        "-pix_fmt", "bgra", "-tag:v", "hvc1",
                        "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000",
                        "-c:a", "aac", "-b:a", "160k", "-shortest", out], check=True)
    print(f"{out}: {len(frames)} frames, {Path(out).stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
