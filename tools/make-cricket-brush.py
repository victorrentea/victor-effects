#!/usr/bin/env python3
"""🦗 Turns a black brush stroke on white into the backdrop tile 12 draws behind the
cricket and the moon: `assetsDir/cricket-brush.png` (Victor, 2026-11-05). Only this
script is committed; the picture lives in assetsDir (docs/assets-and-licences.md).

- **White goes, the paint stays.** Alpha comes off the luminance. Inside, the stroke is
  fully opaque and keeps its grey texture; the rim takes the paint's own colour. Unmixing
  the rim from the paper was tried first and drew a pale outline on a dark desktop.
- **Enlarged before it is cut out.** The picture is a thumbnail of 643x360 that ends up
  around 1900 px wide on a Retina screen. Cutting it out first would enlarge a hard
  mask; enlarging first gives the matte smooth edges.
- **The film goes where Victor pointed, as near as the shape allows.** He marked where
  the moon and the cricket's body should sit. The film is one picture, so they cannot
  move apart: the search takes the size and place nearest both marks at which every lit
  pixel of the film (stars included) stands on solid stroke. The rectangle it prints is
  `CricketMoon.videoInBackdrop`.

Needs numpy, pillow and ffmpeg.

    tools/make-cricket-brush.py stroke.png ~/.victor-effects/assets/cricket-moon.mov \\
        ~/.victor-effects/assets/cricket-brush.png
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ENLARGE = 3
PAPER = 245           # at this luminance and above, nothing of the stroke
INK = 90              # at this luminance and below, all stroke: the texture stays inside
PAINT = 18            # the stroke's typical luminance, the colour of its semi-transparent rim
SOLID = 230           # alpha from which the stroke counts as solid under the picture
MARGIN = 3            # px of solid stroke kept around every lit pixel
LIT = 30              # the film's premultiplied colour above this is picture
SAMPLE = 15           # one frame in this many
FILM_MOON = (332.5, 129.0)      # centre of the moon in the film, px
FILM_CRICKET = (555.0, 513.0)   # centre of the cricket's body in the film, px
MARK_MOON = (0.3525, 0.2545)    # Victor's marks on the stroke, shares of its size
MARK_CRICKET = (0.5245, 0.5735)
SHARES = np.arange(0.50, 0.76, 0.01)  # the film's width as a share of the stroke's


def cut_out(path):
    """(RGBA image, alpha as an array) of the stroke, enlarged."""
    img = Image.open(path).convert("RGB")
    img = img.resize((img.width * ENLARGE, img.height * ENLARGE), Image.LANCZOS)
    rgb = np.asarray(img).astype(np.float32)
    lum = rgb.mean(axis=2)
    alpha = np.clip((PAPER - lum) / (PAPER - INK), 0, 1)
    ink = np.where(alpha[..., None] >= 1, rgb, PAINT)
    rgba = np.dstack([ink, alpha * 255])
    return Image.fromarray(np.round(rgba).astype(np.uint8), "RGBA"), alpha


def film_mask(video):
    """Every pixel the film lights in any sampled frame."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(video), "-vf",
                        f"select=not(mod(n\\,{SAMPLE})),format=rgb24", "-fps_mode", "passthrough",
                        f"{tmp}/%03d.png"], check=True)
        frames = [np.asarray(Image.open(p)).max(axis=2) > LIT for p in sorted(Path(tmp).glob("*.png"))]
    return np.logical_or.reduce(frames)


def fit(alpha, mask):
    """(x, y, w, h) of the film on the stroke, top-left origin: nearest Victor's marks."""
    solid = Image.fromarray(((alpha * 255 > SOLID) * 255).astype(np.uint8))
    solid = np.asarray(solid.filter(ImageFilter.MinFilter(2 * MARGIN + 1))) > 0
    H, W = solid.shape
    holes = np.fft.rfft2((~solid).astype(np.float32))
    shape = Image.fromarray((mask * 255).astype(np.uint8))
    fh, fw = mask.shape
    best = None
    for share in SHARES:
        w = round(W * share)
        h = round(w * fh / fw)
        if h >= H:
            continue
        pad = np.zeros((H, W), np.float32)
        pad[:h, :w] = np.asarray(shape.resize((w, h), Image.BILINEAR)) > 128
        over = np.fft.irfft2(holes * np.conj(np.fft.rfft2(pad)), s=(H, W))[:H - h, :W - w]
        ys, xs = np.nonzero(over < 0.5)
        if not len(xs):
            continue
        k = w / fw
        cost = sum((xs + c[0] * k - m[0] * W) ** 2 + (ys + c[1] * k - m[1] * H) ** 2
                   for c, m in ((FILM_MOON, MARK_MOON), (FILM_CRICKET, MARK_CRICKET)))
        i = np.argmin(cost)
        if best is None or cost[i] < best[0]:
            best = (cost[i], int(xs[i]), int(ys[i]), w, h)
    if best is None:
        sys.exit("the film fits nowhere on this stroke")
    return best[1:]


def main(stroke_path, video, out):
    rgba, alpha = cut_out(stroke_path)
    x, y, w, h = fit(alpha, film_mask(video))
    rgba.save(out)
    W, H = rgba.size
    print(f"{out}: {W}x{H}")
    print(f"videoInBackdrop = CGRect(x: {x}.0 / {W}, y: {H - y - h}.0 / {H}, width: {w}.0 / {W}, height: {h}.0 / {H})")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
