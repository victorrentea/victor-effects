#!/usr/bin/env python3
"""👁️ The Eye's living fire: a looping GIF of a fiery eye on black -> assetsDir/eye-fire.png (+ .json).

    make-eye-fire.py <eye.gif> <assetsDir>

Victor, 2026-11-27, over the drawn eye: *"iterate a bit better on the burning eye … make it
somehow burning, spreading like bits of fire around it"*, then he picked a clip from an image
search — makeagif.com's "The Eye of Sauron (Free Stock Footage)", 320x180, 151 frames at 15 fps,
a round eye of flame on black with a vertical slit, the site's watermark bottom right. Its licence
is not ours to give, so the output lives in `assetsDir` only and is never committed; without it the
eye is drawn in code as before (`EyeTower.eyeSprite`).

What this does, per frame:

  - **crop** to the eye (x 55..265, y 10..160 of the 320x180 frame), which also leaves the
    watermark (x >= 230, y >= 162) out;
  - **fill the slit**: the clip's pupil is fixed in the middle and the app draws its own, which
    looks where the light is — two pupils would be one too many. The dark pixels of the slit are
    replaced by the fire around them (half a normalised blur of everything that is not slit, half
    the flames BORROW px to either side, for texture), solid, so the middle is an iris for the app's own pupil to sit on;
  - **key the black**: alpha from the brightest channel (a glow key — black is nothing, the flames'
    yellow core is solid, their red fringe half), colour un-premultiplied so it composites back to
    the source over black.

Frames go into one sprite sheet (COLS columns, row-major from the top-left) so the app animates
`contentsRect` instead of swapping 151 images; `eye-fire.json` says how to slice it.
"""
import json, sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter, ImageSequence

CROP = (55, 10, 265, 160)          # left, top, right, bottom in the 320x180 frame
COLS = 12
SLIT_HALF = (24, 60)               # half-width, half-height of the box the slit lives in, px
SLIT_DARK = 0.30                   # brightest channel below this, inside that box = slit
FILL_DARKEN = 1.05
BORROW = 36                        # px sideways the patch takes its flame texture from


def blur(a, r):
    """Gaussian blur of an HxWx3 float image, channel by channel, through PIL's 8-bit "L"."""
    out = np.empty_like(a)
    for c in range(a.shape[2]):
        ch = Image.fromarray((np.clip(a[:, :, c], 0, 1) * 255).round().astype(np.uint8), mode="L")
        out[:, :, c] = np.asarray(ch.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255
    return out


def process(frame):
    rgb = np.asarray(frame.convert("RGB").crop(CROP), dtype=np.float32) / 255
    h, w, _ = rgb.shape
    peak = rgb.max(axis=2)
    yy, xx = np.mgrid[0:h, 0:w]
    cy, cx = h / 2, w / 2 + 3
    box = (np.abs(xx - cx) < SLIT_HALF[0]) & (np.abs(yy - cy) < SLIT_HALF[1])
    slit = box & (peak < SLIT_DARK)
    # Grow the slit a touch so its dark rim goes too.
    slit = np.asarray(Image.fromarray(slit.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))) > 0
    slit &= box
    keep = (~slit).astype(np.float32)[:, :, None]
    num = blur(rgb * keep, 14)
    den = blur(np.repeat(keep, 3, axis=2), 14)
    smooth = num / np.maximum(den, 1e-3)
    # Texture: the flames from either side of the slit, borrowed across it, so
    # the patch flickers like what is around it instead of glowing flat.
    grain = 0.5 * (np.roll(rgb, BORROW, axis=1) + np.roll(rgb, -BORROW, axis=1))
    fill = (0.45 * smooth + 0.55 * grain) * FILL_DARKEN
    # Feather the patch into its surroundings.
    soft = np.asarray(Image.fromarray(slit.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(2)),
                      dtype=np.float32)[:, :, None] / 255
    rgb = rgb * (1 - soft) + fill * soft

    peak = rgb.max(axis=2)
    alpha = np.clip((peak - 0.04) * 1.9, 0, 1)
    alpha = np.maximum(alpha, soft[:, :, 0])       # the patch is fire, solid like what surrounds it
    straight = np.where(alpha[:, :, None] > 1e-3, rgb / np.maximum(alpha[:, :, None], 1e-3), 0)
    out = np.dstack([np.clip(straight, 0, 1), alpha])
    return Image.fromarray((out * 255).round().astype(np.uint8), mode="RGBA")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, assets = Path(sys.argv[1]), Path(sys.argv[2]).expanduser()
    gif = Image.open(src)
    frames, delays = [], []
    for f in ImageSequence.Iterator(gif):
        frames.append(process(f))
        delays.append(f.info.get("duration", 66) / 1000)
    fw, fh = frames[0].size
    rows = (len(frames) + COLS - 1) // COLS
    sheet = Image.new("RGBA", (fw * COLS, fh * rows))
    for i, f in enumerate(frames):
        sheet.paste(f, ((i % COLS) * fw, (i // COLS) * fh))
    assets.mkdir(parents=True, exist_ok=True)
    sheet.save(assets / "eye-fire.png", optimize=True)
    meta = {"cols": COLS, "rows": rows, "frames": len(frames), "frameWidth": fw, "frameHeight": fh,
            "seconds": round(sum(delays), 3)}
    (assets / "eye-fire.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"{len(frames)} frames {fw}x{fh}, {meta['seconds']} s -> {assets / 'eye-fire.png'}")


if __name__ == "__main__":
    main()
