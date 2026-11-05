#!/usr/bin/env python3
"""🦗 Turns a black brush stroke on white into the backdrop tile 12 draws behind the
cricket and the moon: `assetsDir/cricket-brush.png` (Victor, 2026-11-05). Only this
script is committed; the picture lives in assetsDir (docs/assets-and-licences.md).

- **Level first.** The stroke is turned to where it stands thinnest, then the canvas is
  cropped to it. Its principal axis was tried first and read 37°: the stroke is a
  parallelogram, so that axis is its diagonal, and it came out sagging to the right.
- **White is alpha, not colour.** Black on white: coverage is the inverse of the
  luminance, the colour stays pure black, so the torn edges carry no white fringe.
- **The fit is searched, not guessed.** The film's picture (cricket, moon, stars,
  over every sampled frame) is a shape, not its rectangle, so its corners may hang
  over a bay in the stroke. The largest size at which every lit pixel stands on solid
  stroke wins, and the rectangle it prints is `CricketMoon.videoInBackdrop`.

Needs numpy, pillow and ffmpeg.

    tools/make-cricket-brush.py stroke.jpg ~/.victor-effects/assets/cricket-moon.mov \\
        ~/.victor-effects/assets/cricket-brush.png
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

WHITE_NOISE = 20      # JPEG ringing on the paper, below this inverse luminance
SOLID = 200           # alpha from which the stroke counts as solid under the picture
MARGIN = 4            # px of solid stroke kept around every lit pixel
LIT = 30              # the film's premultiplied colour above this is picture
SAMPLE = 15           # one frame in this many
STEP = 20             # px between the sizes tried


def thickness(xs, ys, degrees):
    """How tall the stroke stands once turned, its stray flecks left out."""
    r = np.radians(degrees)
    low, high = np.percentile(ys * np.cos(r) - xs * np.sin(r), (1, 99))
    return high - low


def level(alpha):
    """The stroke turned so its long axis lies flat, cropped to itself."""
    ys, xs = np.nonzero(alpha > 128)
    angle = min(np.arange(-60, 60.5, 0.5), key=lambda a: thickness(xs, ys, a))
    img = Image.fromarray(alpha).rotate(angle, resample=Image.BICUBIC, expand=True, fillcolor=0)
    return img.crop(img.point(lambda p: 255 if p > 8 else 0).getbbox()), angle


def film_mask(video):
    """Every pixel the film lights in any sampled frame."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(video), "-vf",
                        f"select=not(mod(n\\,{SAMPLE})),format=rgb24", "-fps_mode", "passthrough",
                        f"{tmp}/%03d.png"], check=True)
        frames = [np.asarray(Image.open(p)).max(axis=2) > LIT for p in sorted(Path(tmp).glob("*.png"))]
    return np.logical_or.reduce(frames)


def fit(stroke, mask):
    """(x, y, w, h) of the film on the stroke, top-left origin: the largest that fits."""
    solid = Image.fromarray(((np.asarray(stroke) > SOLID) * 255).astype(np.uint8))
    solid = np.asarray(solid.filter(ImageFilter.MinFilter(2 * MARGIN + 1))) > 0
    H, W = solid.shape
    aspect = mask.shape[0] / mask.shape[1]
    shape = Image.fromarray((mask * 255).astype(np.uint8))
    holes = np.fft.rfft2((~solid).astype(np.float32))
    for w in range(W, 0, -STEP):
        h = round(w * aspect)
        if h >= H or w >= W:
            continue
        pad = np.zeros((H, W), np.float32)
        pad[:h, :w] = np.asarray(shape.resize((w, h), Image.BILINEAR)) > 128
        over = np.fft.irfft2(holes * np.conj(np.fft.rfft2(pad)), s=(H, W))[:H - h, :W - w]
        ys, xs = np.nonzero(over < 0.5)
        if len(xs):
            i = np.argmin((xs - xs.mean()) ** 2 + (ys - ys.mean()) ** 2)  # the most central spot
            return int(xs[i]), int(ys[i]), w, h
    sys.exit("the film fits nowhere on this stroke")


def main(stroke_path, video, out):
    grey = np.asarray(Image.open(stroke_path).convert("L")).astype(np.float32)
    alpha = (np.clip((255 - grey - WHITE_NOISE) / (235 - WHITE_NOISE), 0, 1) * 255).astype(np.uint8)
    stroke, angle = level(alpha)
    x, y, w, h = fit(stroke, film_mask(video))
    rgba = Image.new("RGBA", stroke.size, (0, 0, 0, 0))
    rgba.putalpha(stroke)
    rgba.save(out)
    W, H = stroke.size
    print(f"{out}: {W}x{H}, turned {angle:.1f}°")
    print(f"videoInBackdrop = CGRect(x: {x}.0 / {W}, y: {H - y - h}.0 / {H}, width: {w}.0 / {W}, height: {h}.0 / {H})")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
