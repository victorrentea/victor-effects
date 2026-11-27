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

  - **crop** to the eye, x 55..265 and the frame's whole height: cut at y 160 (to leave the
    watermark out) the flames' foot ended on a straight line (Victor: *"animația ochiului pare tăiată
    inferior"*). The watermark (x >= 228, y >= 158) is covered instead with the eye's other side,
    mirrored about its centre, and the top and bottom rows fade out so no frame edge shows;
  - **keep the slit, solid**: until 2026-11-27 evening the clip's pupil was painted over with fire and
    the app drew a pupil of its own; Victor then asked for the clip's own black centre, moved by
    stretching the fire toward where the eye looks (`EyeTower.gazeWarp`). The slit is the dark region
    connected to the middle of the frame (a flood fill, so the black OUTSIDE the eye stays black);
    it is made opaque, so the glow key does not turn the pupil into a hole the tower shows through;
  - **key the black**: alpha from the brightest channel (a glow key — black is nothing, the flames'
    yellow core is solid, their red fringe half), colour un-premultiplied so it composites back to
    the source over black.

Frames go into one sprite sheet (COLS columns, row-major from the top-left) so the app animates
`contentsRect` instead of swapping 151 images; `eye-fire.json` says how to slice it.
"""
import json, sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageSequence

CROP = (55, 0, 265, 180)           # left, top, right, bottom in the 320x180 frame
WATERMARK = (228, 158)             # the watermark lies right of and below this, frame px
EYE_CX = 163                       # the eye's vertical axis, frame px (the mirror for the watermark)
EDGE_FADE = 12                     # px at the top and bottom of the frame faded to nothing
COLS = 12
SLIT_HALF = (24, 60)               # half-width, half-height of the box the slit lives in, px
SLIT_DARK = 0.42                   # brightest channel below this, inside that box = slit


def slit_mask(peak):
    """The dark region connected to the frame's middle, inside the box the slit lives in."""
    h, w = peak.shape
    yy, xx = np.mgrid[0:h, 0:w]
    cy, cx = h / 2, w / 2 + 3
    box = (np.abs(xx - cx) < SLIT_HALF[0]) & (np.abs(yy - cy) < SLIT_HALF[1])
    # .copy(): fromarray shares a read-only buffer, and floodfill then changes nothing, silently.
    dark = Image.fromarray(((box & (peak < SLIT_DARK)) * 255).astype(np.uint8)).copy()
    seeds = [(int(cx) + dx, int(cy) + dy) for dy in range(-20, 21, 4) for dx in range(-4, 5, 2)]
    for sx, sy in seeds:
        if dark.getpixel((sx, sy)) == 255:
            ImageDraw.floodfill(dark, (sx, sy), 128)
    return np.asarray(dark) == 128


def process(frame):
    full = np.asarray(frame.convert("RGB"), dtype=np.float32) / 255
    wx, wy = WATERMARK
    xs = np.arange(wx, full.shape[1])
    full[wy:, xs] = full[wy:, np.clip(2 * EYE_CX - xs, 0, full.shape[1] - 1)]
    rgb = full[CROP[1]:CROP[3], CROP[0]:CROP[2]]
    peak = rgb.max(axis=2)
    slit = slit_mask(peak)
    # Its dark-red rim joins it, so the pupil's edge is the clip's and not a cut-out.
    grown = Image.fromarray(slit.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(5))
    solid = np.asarray(grown.filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float32) / 255

    alpha = np.clip((peak - 0.04) * 1.9, 0, 1)
    alpha = np.maximum(alpha, solid)                # the slit is black, not see-through
    ramp = np.clip(np.minimum(np.arange(alpha.shape[0]), alpha.shape[0] - 1 - np.arange(alpha.shape[0])) / EDGE_FADE, 0, 1)
    alpha = alpha * (ramp * ramp * (3 - 2 * ramp))[:, None]
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
