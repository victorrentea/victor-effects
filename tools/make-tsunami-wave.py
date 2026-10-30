#!/usr/bin/env python3
"""🌊 Turns a filmed breaking wave on a flat light background into the RGBA
frames `Tsunami` slides across the screen: `assetsDir/tsunami-wave/NN.png`.

Written for Victor's Gemini clip (2026-10-31, `gemini_generated_video_*.mp4`,
1280x720 @ 24 fps, 10 s): a cartoon breaker on an off-white (~245 grey) ground
that rolls in from the left, curls, crashes and leaves to the right. Only this
script is committed; the frames live in assetsDir (docs/assets-and-licences.md).

- **The key is by connectivity, not by colour.** The foam is the same grey as
  the background, so a colour key would eat it. Background = the near-grey
  regions connected to the frame's top/left/right border, plus large flat
  enclosed pockets of it (the inside of the barrel once the lip closes onto
  the water; foam is shaded and textured, so it never forms one). The
  drawing's blue outlines are what keep the foam out of the flood. The soft
  edge is un-mixed from the background colour so no grey halo is left.
- **The wave is held in place.** `Tsunami` moves the sprite itself (the lip
  crosses the glass in exactly the 2.5 s the clip's roar pans over), so each
  frame is cropped to a window that rides the crest's front — smoothed (a
  5-frame median against a droplet breaking off, then a 9-frame mean), so the
  spray's jitter does not shake the window. Not a straight-line fit: the crest
  stalls mid-curl and surges as it crashes, and a line let the curl run off
  the window's edge.
- Only the stretch where the wave is big and breaking is used (`START`, `SECONDS`,
  resampled to `Tsunami.spriteFPS`), and the window's left and right edges are
  faded out: the sprite is translated across the screen, and a hard edge of
  sea would slide along with it.

Needs numpy, scipy and pillow.

    tools/make-tsunami-wave.py wave.mp4 ~/.victor-effects/assets/tsunami-wave
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

START = 2.7        # s into the clip: the wave is fully grown and starting to curl…
SECONDS = 4.0      # …through the crash. Must outlast Tsunami's slide (2.5 + 1.2 s).
FPS = 15           # = Tsunami.spriteFPS
WINDOW = 1000      # source px kept behind the crest's front…
AHEAD = 40         # …and ahead of it, for the spray
SCALE = 0.75       # 1000x720 → 750x540: ~1.6 MB decoded per frame, 60 frames
LEFT_FADE = 0.30   # share of the width over which the trailing sea fades in
RIGHT_FADE = 0.04  # and the sea ahead of the window's edge fades out
SKY_TOL = 14       # max channel distance from the background colour
SKY_SAT = 10       # max (max - min) channel spread: the background is grey
POCKET = 0.008     # an enclosed grey pocket this share of the frame is sky too


def ramp(v, lo, hi):
    return np.clip((v - lo) / (hi - lo), 0, 1)


def matte(rgb):
    """RGBA of one frame, the background keyed out."""
    i = rgb.astype(np.float32)
    h, w, _ = i.shape
    sky_rgb = np.median(i[:20].reshape(-1, 3), axis=0)
    cand = (np.abs(i - sky_rgb).max(axis=2) <= SKY_TOL) & (i.max(axis=2) - i.min(axis=2) <= SKY_SAT)
    # Eroded by a pixel so a hairline gap in an outline does not let the flood in.
    lab, n = ndi.label(ndi.binary_erosion(cand))
    # Seeded from a 4 px band, not the edge row itself: the encoder leaves the
    # outermost pixels a shade off the background.
    border = set(np.unique(np.concatenate([lab[:4].ravel(), lab[:, :4].ravel(), lab[:, -4:].ravel()]))) - {0}
    sizes = ndi.sum(np.ones_like(lab), lab, index=np.arange(n + 1))
    pockets = set(np.nonzero(sizes >= POCKET * h * w)[0]) - {0}
    sky = ndi.binary_dilation(np.isin(lab, list(border | pockets))) & cand
    alpha = np.where(sky, 0.0, 1.0)
    rim = ndi.binary_dilation(sky, iterations=2) & ~sky
    alpha = np.where(rim, np.clip(np.linalg.norm(i - sky_rgb, axis=2) / 60, 0, 1), alpha)
    a = alpha[..., None]
    color = np.where(a > 0.02, (i - (1 - a) * sky_rgb) / np.maximum(a, 0.02), 0)
    return np.dstack([np.clip(color, 0, 255), alpha * 255])


def crest_front(rgba):
    """The rightmost column the crest (the top 55 % of rows) reaches."""
    top = rgba[: int(rgba.shape[0] * 0.55), :, 3] > 128
    cols = np.nonzero(top.sum(axis=0) >= 3)[0]
    return int(cols.max()) if len(cols) else None


def window(rgba, right):
    """`rgba` cropped to [right - WINDOW, right + AHEAD), transparent where it runs off."""
    h, w, _ = rgba.shape
    width = WINDOW + AHEAD
    out = np.zeros((h, width, 4), np.float32)
    lo = right - WINDOW
    src_lo, src_hi = max(0, lo), min(w, right + AHEAD)
    out[:, src_lo - lo: src_hi - lo] = rgba[:, src_lo:src_hi]
    # The left fade starts where the film does: early on the window reaches
    # past the frame's left edge, and fading the window's edge alone left the
    # film's own edge standing as a hard line.
    x = np.arange(width, dtype=np.float32)
    start = src_lo - lo
    fade = np.minimum(ramp(x, start, start + LEFT_FADE * width), ramp(width - 1 - x, 0, RIGHT_FADE * width))
    out[..., 3] *= fade[None, :]
    return out


def main(src, dst):
    dst = Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    for old in dst.glob("*.png"):
        old.unlink()
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-ss", str(START), "-t", str(SECONDS), "-i", src,
                        "-vf", f"fps={FPS}", f"{tmp}/%02d.png"], check=True)
        mattes = [matte(np.array(Image.open(f).convert("RGB"))) for f in sorted(Path(tmp).glob("*.png"))]
    raw = np.array([crest_front(m) or -1 for m in mattes], np.float32)
    raw[raw < 0] = np.median(raw[raw >= 0])
    track = ndi.uniform_filter1d(ndi.median_filter(raw, size=5, mode="nearest"), size=9, mode="nearest")
    for k, m in enumerate(mattes):
        out = window(m, int(round(track[k])))
        img = Image.fromarray(out.round().astype(np.uint8), "RGBA")
        img = img.resize((round(img.width * SCALE), round(img.height * SCALE)), Image.LANCZOS)
        img.save(dst / f"{k + 1:02d}.png")
    print(f"{len(mattes)} frames → {dst} (crest {track[0]:.0f} → {track[-1]:.0f} px held in place)")


if __name__ == "__main__":
    main(*sys.argv[1:3])
