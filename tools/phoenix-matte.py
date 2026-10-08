"""Matte a fire-on-black video's frames into RGBA for the 🔥 phoenix (tile #34).

    ffmpeg -i video.mp4 -pix_fmt rgb24 src/f_%03d.png
    python3 tools/phoenix-matte.py src rgba
    ffmpeg -framerate 24 -i rgba/f_%03d.png -c:v hevc_videotoolbox -alpha_quality 0.9 \
           -q:v 70 -pix_fmt bgra -tag:v hvc1 -an <assetsDir>/phoenix-rising.mov

Alpha = luminance for the sparks and glow (black transparent), and fully OPAQUE
inside the bird: its flames, closed over the thin dark lines between feathers
and eroded back so the rim keeps the soft luminance alpha (no black outline).
Colour is PREMULTIPLIED — AVPlayerLayer composites HEVC-alpha that way; straight
colour came out pale with light halos. See docs/overlay-effects.md, 🔥 Phoenix.
"""
import sys, os, numpy as np
from PIL import Image
from scipy import ndimage
src, dst = sys.argv[1], sys.argv[2]
only = sys.argv[3:]  # optional subset of frames for a quick check
LO, HI = 0.07, 0.75
disk = lambda r: (lambda y, x: x*x + y*y <= r*r)(*np.ogrid[-r:r+1, -r:r+1])
for f in (only or sorted(os.listdir(src))):
    a = np.asarray(Image.open(os.path.join(src, f))).astype(np.float32) / 255
    lum = a.max(axis=2)
    soft = np.clip((lum - LO) / (HI - LO), 0, 1) ** 0.85          # sparks + glow, as before
    body = lum > 0.16                                               # the bird's flames
    body = ndimage.binary_closing(body, structure=disk(7))          # bridge the dark feathers
    # no hole filling: a dark gap the flames curl around is background, not bird
    lab, n = ndimage.label(body)
    if n:
        sizes = ndimage.sum(body, lab, range(1, n + 1))
        body = np.isin(lab, 1 + np.flatnonzero(sizes > 6000))        # the bird, not the sparks
    body = ndimage.binary_erosion(body, structure=disk(8))          # back inside the flames: the rim keeps soft alpha
    solid = ndimage.gaussian_filter(body.astype(np.float32), 3.0)   # a soft rim, not a cut-out edge
    alpha = np.maximum(soft, solid)
    rgb = np.minimum(a, alpha[..., None])                           # premultiplied
    Image.fromarray((np.dstack([rgb, alpha]) * 255).astype(np.uint8), "RGBA").save(os.path.join(dst, f))
