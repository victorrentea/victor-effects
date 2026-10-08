"""Matte a fire-on-black video's frames into RGBA for the 🔥 phoenix (tile #34).

    ffmpeg -i video.mp4 -pix_fmt rgb24 src/f_%03d.png
    python3 tools/phoenix-matte.py src rgba
    ffmpeg -framerate 24 -i rgba/f_%03d.png -c:v hevc_videotoolbox -alpha_quality 0.9 \\
           -q:v 70 -pix_fmt bgra -tag:v hvc1 -an <assetsDir>/phoenix-rising.mov

Alpha is a STEEP, SMOOTH curve of luminance, per pixel: black transparent, the
bird's flames (lum >= 0.38) fully opaque, the dark glow fading out in between.
No spatial mask: a mask that forced the bird's inside opaque left a dark band
round the wings (Victor: "an ugly edge"); a gentle curve (0.07–0.75) left the
body see-through. Colour is PREMULTIPLIED — AVPlayerLayer composites HEVC-alpha
that way; straight colour came out pale with light halos.
See docs/overlay-effects.md, 🔥 Phoenix.
"""
import sys, os, numpy as np
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
only = sys.argv[3:]
LO, HI, G = 0.06, 0.38, 0.7     # a steep, smooth curve: the bird is opaque, the dark glow fades out
for f in (only or sorted(os.listdir(src))):
    a = np.asarray(Image.open(os.path.join(src, f))).astype(np.float32) / 255
    alpha = np.clip((a.max(axis=2) - LO) / (HI - LO), 0, 1) ** G
    rgb = np.minimum(a, alpha[..., None])        # premultiplied
    Image.fromarray((np.dstack([rgb, alpha]) * 255).astype(np.uint8), "RGBA").save(os.path.join(dst, f))
