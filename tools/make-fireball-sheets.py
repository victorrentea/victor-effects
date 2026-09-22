#!/usr/bin/env python3
"""Turn the three fireball gifs into PNG sprite sheets with 8-bit alpha.

Same recipe `fire-frames.png` was made with, and for the same reason: a gif
carries 1-bit alpha, so a gif of fire fringes against every desktop. We key the
matte out ourselves and write soft alpha into a png grid, read row-major.

Two mattes, because the three clips arrived on two different backgrounds:

  black  alpha = luminance x gain. Fire on black keys perfectly this way.
  white  alpha = (255 - min(r,g,b)) x gain, then the colour is un-premultiplied
         back off white, so the red glow keeps its colour instead of staying
         milky.

`core` is the plasma ball's tax: its interior is genuinely BLACK (dark rock
between glowing veins), and a luminance key cannot tell that black from the
black around the ball. Left alone it turns the sphere into a stencil and the
slide shows through every crack. Flood-filling the silhouette was the obvious
fix and it does not work — the rim is filaments, not a contour, and the fill
leaks through it. So the ball is treated as what it is, a DISC: a measured
radial profile (mean keyed alpha per ring) puts the body's edge at 0.78 of the
half-width and the last spikes at 0.83, so everything inside 0.75 is forced
opaque and 0.75 -> 0.83 feathers back to the keyed value. Numbers as fractions,
so the same two hold at any cell size.

Run it from anywhere:

    python3 tools/make-fireball-sheets.py <gifs-dir> [cell-width]

where <gifs-dir> holds the three source clips under the names in SRC. The
sheets land in Sources/VictorEffects/Resources/, and the grid each one comes
out with has to be typed back into `EmojiAnimator.fireballs` — the sheet does
not carry its own row/column count, and `testEveryFireballGridHoldsItsFrames`
is what catches you if the two drift apart.
"""
import math, os, pathlib, sys
from PIL import Image, ImageSequence

SRC = {
    # sheet name: (source gif, matte, gain, opaque_core)
    "fireball-burst":  ("burst.gif",  "black", 2.0, False),
    "fireball-plasma": ("plasma.gif", "black", 2.0, True),
    "fireball-lava":   ("lava.gif",   "white", 1.6, False),
}

GIFS = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
CELL_W = int(sys.argv[2]) if len(sys.argv) > 2 else 224
OUT = pathlib.Path(__file__).resolve().parent.parent / "Sources/VictorEffects/Resources"


CORE_SOLID, CORE_FEATHER = 0.75, 0.83   # fractions of the frame's half-width


def key_frame(rgba, matte, gain, core):
    px = rgba.load()
    w, h = rgba.size
    cx, cy, half = w / 2, h / 2, min(w, h) / 2
    r0, r1 = CORE_SOLID * half, CORE_FEATHER * half
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if matte == "black":
                if a == 0:          # the gif's own 1-bit alpha only says "drawn"
                    r = g = b = 0
                lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                na = min(255, int(lum * gain))
                if core:
                    d = math.hypot(x - cx, y - cy)
                    if d <= r0:
                        na = 255
                    elif d < r1:
                        na = max(na, int(255 * (r1 - d) / (r1 - r0)))
                op[x, y] = (r, g, b, na)
            else:
                d = 255 - min(r, g, b)
                na = min(255, int(d * gain))
                if na == 0:
                    op[x, y] = (0, 0, 0, 0)
                else:
                    f = na / 255.0
                    op[x, y] = (
                        min(255, max(0, int((r - 255 * (1 - f)) / f))),
                        min(255, max(0, int((g - 255 * (1 - f)) / f))),
                        min(255, max(0, int((b - 255 * (1 - f)) / f))),
                        na,
                    )
    return out


for name, (gif, matte, gain, core) in SRC.items():
    im = Image.open(GIFS / gif)
    frames, durations = [], []
    for f in ImageSequence.Iterator(im):
        durations.append(f.info.get("duration", 100))
        frames.append(key_frame(f.convert("RGBA"), matte, gain, core))

    box = None
    for f in frames:
        b = f.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                     max(box[2], b[2]), max(box[3], b[3]))
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2          # square the crop: a ball is a ball
    half = max(x1 - x0, y1 - y0) / 2 * 1.04
    x0, y0 = int(max(0, cx - half)), int(max(0, cy - half))
    x1, y1 = int(min(frames[0].width, cx + half)), int(min(frames[0].height, cy + half))
    cw, ch = CELL_W, int(CELL_W * (y1 - y0) / (x1 - x0))

    n = len(frames)
    cols = math.ceil(math.sqrt(n))
    rows = math.ceil(n / cols)
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        cell = f.crop((x0, y0, x1, y1)).resize((cw, ch), Image.LANCZOS)
        sheet.paste(cell, ((i % cols) * cw, (i // cols) * ch))
    out = OUT / f"{name}.png"
    sheet.save(out, optimize=True)
    ms = sum(durations) / len(durations)
    print(f"{name}: {n} frames, grid {cols}x{rows}, cell {cw}x{ch}, "
          f"{1000/ms:.1f} fps, {os.path.getsize(out)/1e6:.2f} MB -> {out.name}")
