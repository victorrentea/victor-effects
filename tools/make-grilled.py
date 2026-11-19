#!/usr/bin/env python3
"""🔥 Grilled (⌘⌃8): Victor's Gemini clip -> assetsDir/grilled.mov, HEVC with alpha + its sound.

    make-grilled.py <gemini.mp4> <masks-dir> <out.mov>

The clip (1280x720, 24 fps, ~10 s): its first second is a cartoon grill on WHITE that fades
into the real scene on BLACK — two men in dark suits over a red grill, flames, a storm of
question marks, a golden "?" burst, smoke. The first FIRST frames are cut; the rest is keyed.

A luminance key alone (✨ Fable's) would make the navy suits see-through, so:

    alpha = max(BirefNet matte, glow key on the brightest channel)
    colour = the source, clamped to alpha  (= premultiplied: over black it IS the source)

The matte keeps the men and the grill solid; the glow key lets fire, sparks, question marks
and smoke light the desktop translucently. The mattes come from the video-remove-bg skill's
venv, one PNG per frame with the source frame's name (frames from FIRST on):

    ffmpeg -i gemini.mp4 -fps_mode passthrough src/f_%04d.png
    rembg p -om -m birefnet-general src masks        # ~3.6 s/frame on an M-series CPU

Sound: the same file's track from the cut on, normalised to -14 LUFS, muxed in the SAME
ffmpeg run (re-muxing an HEVC-alpha stream with -c:v copy breaks it for AVFoundation).
"""
import subprocess, sys, tempfile
from pathlib import Path

import numpy as np
from PIL import Image

FIRST = 25            # f_0025 = t 1.000 s: the white has gone to black by then
FPS = 24
LO, HI, GAMMA = 0.03, 0.60, 0.85   # glow key on max(R,G,B), Fable's gentler curve


def frame_rgba(src: Path, mask: Path) -> np.ndarray:
    s = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255
    m = np.asarray(Image.open(mask).convert("L").resize((s.shape[1], s.shape[0])), dtype=np.float32) / 255
    k = np.clip((s.max(axis=2) - LO) / (HI - LO), 0, 1) ** GAMMA
    a = np.maximum(m, k)
    rgb = np.minimum(s, a[..., None])
    return np.round(np.dstack([rgb, a]) * 255).astype(np.uint8)


def main(clip: str, masks: str, out: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp, "src"); src.mkdir()
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", clip, "-fps_mode", "passthrough",
                        f"{src}/f_%04d.png"], check=True)
        frames = sorted(src.glob("f_*.png"))[FIRST - 1:]
        rgba = Path(tmp, "rgba"); rgba.mkdir()
        for n, f in enumerate(frames):
            mask = Path(masks, f.name)
            if not mask.exists():
                sys.exit(f"no matte for {f.name} in {masks}")
            Image.fromarray(frame_rgba(f, mask), "RGBA").save(f"{rgba}/{n:04d}.png")
        start = (FIRST - 1) / FPS
        subprocess.run(["ffmpeg", "-v", "error", "-y",
                        "-framerate", str(FPS), "-i", f"{rgba}/%04d.png",
                        "-ss", f"{start:.3f}", "-i", clip,
                        "-map", "0:v", "-map", "1:a",
                        "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9", "-q:v", "70",
                        "-pix_fmt", "bgra", "-tag:v", "hvc1",
                        "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000",
                        "-c:a", "aac", "-b:a", "160k", "-shortest", out], check=True)
    print(f"{out}: {len(frames)} frames from {start:.3f} s, {Path(out).stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
