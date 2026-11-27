#!/usr/bin/env python3
"""👁️ ⌘⌃7: a pen drawing of the Tower (a photo of ink on paper) -> assetsDir/eye-tower-drawing.png + .json.

    make-eye-tower-drawing.py <photo.png> <assetsDir> [keep=0.80]

Victor, 2026-11-27, with a picture: *"use this tower draw"* — a fan's ink drawing of Barad-dûr,
570 x 760, signed bottom right, the paper photographed in uneven light, a small eye drawn between
the horns. Not ours to publish: it lives in `assetsDir` only, and without it the bundled
`Resources/eye-tower.png` (Wikimedia, CC BY) stands as before.

What this does:

  - **ink** by an adaptive threshold (darker than the paper around it), since the paper runs from
    grey on the left to white on the right;
  - **the tower's outline**: the ink thickened, the paper OUTSIDE flooded from the borders, the
    thickening given back; then only the piece connected to the tower's body is kept. The little
    eye drawn between the horns is erased first (the app's eye burns there): it touches the horns,
    and left in, it closed the bowl and the flood filled it in black;
  - **painted as drawn, only dark**: the ink near-black, the paper inside the tower a dim warm
    stone — the drawing reads as itself against the dusk (the bundled tower's "black with ember
    lines" turned this dense drawing into a brown mass);
  - **cut straight** at `keep` of its height (the rocks at the foot, and the signature under them,
    go: the tower rises out of the bottom edge of the screen), then cropped.

`eye-tower-drawing.json` says where the eye goes, in unit coordinates of the PNG (y from the top):
`eyeX`, `eyeY`, and `eyeWidth`, the eye's width as a share of the PNG's width — the gap between
the horns at the eye's height, so the eye fits between them (Victor: *"să încapă între marginile
turnului"*).
"""
import json, sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

UP = 3                      # work (and ship) at 3x: the photo is small, the screen is a Retina
INK = np.array([4, 3, 3], np.float32)
PAPER = np.array([46, 30, 24], np.float32)
# In the source photo's pixels: a point surely inside the tower's body, the drawn eye's centre
# (the app's eye takes its place), and the box the horns' inner edges are measured in.
BODY_SEED = (285, 300)
EYE = (283, 47)
EYE_ERASE = (31, 24)        # half-width, half-height of the ellipse the drawn eye is erased in


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    src, assets = Path(sys.argv[1]), Path(sys.argv[2]).expanduser()
    keep = float(sys.argv[3]) if len(sys.argv) > 3 else 0.80
    im = Image.open(src).convert("L")
    im = im.resize((im.width * UP, im.height * UP), Image.BICUBIC)
    g = np.asarray(im).astype(np.float32)
    paper = np.asarray(im.filter(ImageFilter.GaussianBlur(30 * UP))).astype(np.float32)
    ink = np.clip((paper * 0.82 - g) / (paper * 0.45), 0, 1)          # 0 paper .. 1 solid ink
    yy, xx = np.mgrid[0:ink.shape[0], 0:ink.shape[1]]
    drawn_eye = ((xx / UP - EYE[0]) / EYE_ERASE[0]) ** 2 + ((yy / UP - EYE[1]) / EYE_ERASE[1]) ** 2 < 1
    ink[drawn_eye] = 0
    line = ((ink > 0.25) * 255).astype(np.uint8)

    # The outside: flood the paper from the borders, through ink thickened so it cannot slip in.
    t = 3 * UP | 1
    wall = Image.fromarray(line).filter(ImageFilter.MaxFilter(t))
    h, w = g.shape
    pad = Image.new("L", (w + 2, h + 2), 255)
    pad.paste(Image.fromarray(np.where(np.asarray(wall) > 0, 0, 255).astype(np.uint8)), (1, 1))
    ImageDraw.floodfill(pad, (0, 0), 128)
    outside = np.asarray(pad)[1:-1, 1:-1] == 128
    outside = np.asarray(Image.fromarray(outside.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(t))) > 0

    # Only the piece the tower's body is in: the drawn eye floats free of it and goes.
    # .copy(): fromarray shares a read-only buffer, and floodfill then changes nothing, silently.
    inside = Image.fromarray(((~outside) * 255).astype(np.uint8)).copy()
    ImageDraw.floodfill(inside, (BODY_SEED[0] * UP, BODY_SEED[1] * UP), 128)
    body = np.asarray(inside) == 128

    alpha = np.asarray(Image.fromarray(body.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(0.8 * UP)),
                       dtype=np.float32)
    rgb = PAPER * (1 - ink[..., None]) + INK * ink[..., None]
    rgba = np.dstack([rgb, alpha]).astype(np.uint8)

    ys, xs = np.where(alpha > 8)
    top, bottom = ys.min(), ys.max() + 1
    rgba[top + int((bottom - top) * keep):, :, 3] = 0
    ys, xs = np.where(rgba[..., 3] > 8)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    crop = Image.fromarray(rgba[y0:y1, x0:x1])

    # The gap between the horns at the eye's height: the first stone left and right of the eye.
    ey, ex = EYE[1] * UP - y0, EYE[0] * UP - x0
    row = np.asarray(crop)[ey, :, 3] > 128
    left = max(i for i in range(0, ex) if row[i])
    right = min(i for i in range(ex, crop.width) if row[i])
    meta = {"eyeX": round(float(left + right) / 2 / crop.width, 4), "eyeY": round(float(ey) / crop.height, 4),
            "eyeWidth": round(float(right - left) / crop.width, 4),
            "width": crop.width, "height": crop.height}

    assets.mkdir(parents=True, exist_ok=True)
    crop.save(assets / "eye-tower-drawing.png", optimize=True)
    (assets / "eye-tower-drawing.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(crop.size, meta, "->", assets / "eye-tower-drawing.png")


if __name__ == "__main__":
    main()
