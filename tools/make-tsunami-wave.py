#!/usr/bin/env python3
"""🌊 Turns a looping breaking-wave GIF on a light-blue sky into the RGBA
frames `Tsunami` slides across the screen: `assetsDir/tsunami-wave/NN.png`.

The source is not ours to publish (docs/assets-and-licences.md), so only this
script is committed; the frames live in assetsDir. It was written for
"ocean-wave-6-big-fast-blue-wave" (usagif.com, 520x293, 60 frames @ 15 fps):
a cartoon breaker that curls in place, breaking to the right.

The sky is keyed out by colour, not matted by a model: it is a flat
light-blue gradient (G-R >= 26, B-R >= 42, G >= 185; paler toward the horizon), the foam is white and the
water dark, so a soft colour ramp beats BiRefNet here — and it keeps the spray.
Edge pixels are un-mixed from that row's sky colour so no blue halo is left.
The frame's left and right edges are faded out: the wave is translated across
the screen, and a hard edge of sea would slide along with it.

    tools/make-tsunami-wave.py wave.gif ~/.victor-effects/assets/tsunami-wave
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

LEFT_FADE = 0.30   # share of the width over which the trailing sea fades in
RIGHT_FADE = 0.04  # and the sea ahead of the foam fades out
BOTTOM_CROP = 12   # rows: the source's "ACEGIF.COM" watermark sits there


def ramp(v, lo, hi):
    return np.clip((v - lo) / (hi - lo), 0, 1)


def reachable_from_top(candidate):
    reach = np.zeros_like(candidate)
    reach[0] = candidate[0]
    while True:
        grown = reach.copy()
        grown[1:] |= reach[:-1]
        grown[:-1] |= reach[1:]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= candidate
        if (grown == reach).all():
            return reach
        reach = grown


def matte(rgb):
    i = rgb[:-BOTTOM_CROP].astype(np.float32)
    r, g, b = i[..., 0], i[..., 1], i[..., 2]
    sky = np.minimum.reduce([ramp(g - r, 8, 26), ramp(b - r, 22, 42), ramp(g, 165, 185)])
    # Only sky that is reachable from the top edge: the pale streaks inside
    # the water match the colour too, and would come out as holes.
    sky *= reachable_from_top(sky > 0.25)
    alpha = 1 - sky
    # Each row's pure-sky colour, to un-mix the soft edges from it.
    h, w = sky.shape
    pure = sky > 0.95
    fallback = i[pure].mean(axis=0) if pure.any() else np.array([140, 200, 226], np.float32)
    row_sky = np.empty((h, 3), np.float32)
    for y in range(h):
        row_sky[y] = i[y][pure[y]].mean(axis=0) if pure[y].sum() > 8 else fallback
    a = alpha[..., None]
    color = np.where(a > 0.02, (i - (1 - a) * row_sky[:, None, :]) / np.maximum(a, 0.02), 0)
    x = np.arange(w) / (w - 1)
    edge = np.minimum(ramp(x, 0, LEFT_FADE), ramp(1 - x, 0, RIGHT_FADE))
    alpha = alpha * edge[None, :]
    out = np.dstack([np.clip(color, 0, 255), alpha * 255]).round().astype(np.uint8)
    return out


def main(src, dst):
    dst = Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-fps_mode", "passthrough",
                        f"{tmp}/%02d.png"], check=True)
        frames = sorted(Path(tmp).glob("*.png"))
        for f in frames:
            Image.fromarray(matte(np.array(Image.open(f).convert("RGB"))), "RGBA").save(dst / f.name)
    print(f"{len(frames)} frames → {dst}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
