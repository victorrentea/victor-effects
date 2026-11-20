#!/usr/bin/env python3
"""👁️ ⌘⌃7: turn Wikimedia Commons' Barad-dûr line drawing into eye-tower.png.

usage: tools/make-eye-tower.py <Barad-dûr.svg> Sources/VictorEffects/Resources/eye-tower.png [keep=0.56]

Source: https://commons.wikimedia.org/wiki/File:Barad-d%C3%BBr.svg (CC BY 3.0,
Didelile; derivative work Rondador). The drawing is black lines on white; the
tower has to be a dark solid on the desktop, so: render it, flood the white
OUTSIDE from the borders (lines thickened first so the flood cannot leak in
through a gap), then paint the inside near-black (Victor's reference was a solid black
silhouette) and leave the lines as faint embers, so the drawing still has texture.
Victor, on the first look: "less of the mountain, more of the tower" — so only
the top `keep` of the drawing is kept (the spire and the top of the keep, not
the wide fortress at its foot), cut straight (no fade: the tower rises out of
the bottom edge of the screen, Victor: "să iasă din partea de jos a ecranului"),
then cropped to what is left. Prints the size and where the horns are, which EyeTower's
`towerAspect` / `towerEyeAnchor` / `towerHornShare` are copied from.
"""
import subprocess, sys, tempfile, numpy as np
from PIL import Image, ImageDraw, ImageFilter

svg, out = sys.argv[1], sys.argv[2]
keep = float(sys.argv[3]) if len(sys.argv) > 3 else 0.56
with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
    subprocess.run(["rsvg-convert", "-h", "2400", "-b", "white", "-o", tmp.name, svg], check=True)
    im = Image.open(tmp.name).convert("L")
g = np.asarray(im).astype(np.float32)
line = (g < 128).astype(np.uint8) * 255
# Thicken the lines so a flood from outside cannot slip through a gap.
wall = Image.fromarray(line).filter(ImageFilter.MaxFilter(9))
flood = Image.fromarray(np.where(np.asarray(wall) > 0, 0, 255).astype(np.uint8))
h, w = g.shape
pad = Image.new("L", (w + 2, h + 2), 255)
pad.paste(flood, (1, 1))
ImageDraw.floodfill(pad, (0, 0), 128)
outside = np.asarray(pad)[1:-1, 1:-1] == 128
# Give back what the thickening took off the rim.
outside = np.asarray(Image.fromarray(outside.astype(np.uint8) * 255).filter(ImageFilter.MinFilter(9))) > 0
inside = ~outside
alpha = np.asarray(Image.fromarray(inside.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32)

ink = np.clip((200 - g) / 200, 0, 1)[..., None]           # 1 on a line, 0 between them
stone = np.array([6, 5, 5], np.float32)
ember = np.array([72, 26, 10], np.float32)
rgb = stone * (1 - ink) + ember * ink
rgba = np.dstack([rgb, alpha]).astype(np.uint8)
ys, xs = np.where(alpha > 8)
top, bottom = ys.min(), ys.max() + 1
cut = top + int((bottom - top) * keep)
rgba[cut:, :, 3] = 0
ys, xs = np.where(rgba[..., 3] > 8)
crop = Image.fromarray(rgba).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
crop.save(out, optimize=True)
a = np.asarray(crop)[..., 3]
horns = np.where(a[10:int(a.shape[0] * 0.04)].max(axis=0) > 128)[0]
print(out, crop.size, "horns x", horns.min(), horns.max())
