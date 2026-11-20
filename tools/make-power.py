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

**The hands go first** (Victor, 2026-11-20: "the hands fade out right before the lightning
disappears, while lightning is still coming out"): over HANDS_OUT the hands fade away inside their
matte while the storm keeps raging around them; their place fills with the storm's own glow,
blurred in from around them. The storm itself is faded by the player (playAlphaClip's fadeOut),
not in here: faded inside the file, low alpha lost its colour to the encoder and went grey. (A first cut played the opening backwards so the hands sank out of the screen; he
preferred this.)

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
HANDS_OUT = (196, 220)   # frames (0-based) over which the hands fade: 8.2 -> 9.2 s
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


def smooth(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def blur(x: np.ndarray, size) -> np.ndarray:
    """A wide, cheap blur: down to 1/8, Gaussian, back up."""
    w, h = size
    small = np.asarray(Image.fromarray(x.astype(np.float32), "F").resize((w // 8, h // 8), Image.BILINEAR))
    r = np.arange(-18, 19)
    g = np.exp(-(r / 6.0) ** 2 / 2); g /= g.sum()
    small = np.apply_along_axis(lambda v: np.convolve(np.pad(v, 18, mode="edge"), g, "valid"), 0, small)
    small = np.apply_along_axis(lambda v: np.convolve(np.pad(v, 18, mode="edge"), g, "valid"), 1, small)
    return np.asarray(Image.fromarray(small.astype(np.float32), "F").resize((w, h), Image.BILINEAR), dtype=np.float32)


def frame_rgba(src: Path, m: np.ndarray, hands: float) -> np.ndarray:
    """hands: 1 = hands solid, 0 = gone — replaced by the storm's own glow around them, blurred
    in, so no hand-shaped hole is left in the haze (there is nothing BEHIND them in the clip)."""
    s = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255
    k = np.clip((s.max(axis=2) - LO) / (HI - LO), 0, 1) ** GAMMA
    a = np.maximum(m, k)
    rgb = np.minimum(s, a[..., None])
    px = np.dstack([rgb, a])
    if hands >= 1:
        return px
    size = (s.shape[1], s.shape[0])
    out = 1 - m                                            # where the storm is not hidden
    weight = np.maximum(blur(out, size), 1e-3)
    fill = np.dstack([blur(px[..., c] * out, size) / weight for c in range(4)])
    gone = (m * (1 - hands))[..., None]
    return px * (1 - gone) + fill * gone


def main(clip: str, masks: str, out: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp, "src"); src.mkdir()
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", clip, "-fps_mode", "passthrough",
                        f"{src}/f_%04d.png"], check=True)
        frames = sorted(src.glob("f_*.png"))
        size = Image.open(frames[0]).size
        rgba = Path(tmp, "rgba"); rgba.mkdir()
        n = len(frames)
        for i in range(n):
            hands = 1 - smooth((i - HANDS_OUT[0]) / (HANDS_OUT[1] - HANDS_OUT[0]))
            px = frame_rgba(frames[i], matte(Path(masks), frames, i, size), hands)
            Image.fromarray(np.round(px * 255).astype(np.uint8), "RGBA").save(f"{rgba}/{i:04d}.png")

        audio = "[1:a]loudnorm=I=-14:TP=-1.5:LRA=11[aout]"
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
