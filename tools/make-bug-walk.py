#!/usr/bin/env python3
"""🪲 ⌘⌃9: turn the beetle GIF into assetsDir/bug-walk.png, a strip of RGBA frames.

usage: tools/make-bug-walk.py <bug.gif> ~/.victor-effects/assets/bug-walk.png

White becomes alpha ("colour to alpha": the soft grey shadow turns into translucent
black, so it still reads on a dark editor); the body's dark interior is kept opaque
with its own colours. One crop for every frame, so the beetle does not jitter.
Prints the crop and the body's principal axis — BugWalk.spriteHeading comes from it.
"""

import sys, numpy as np
from PIL import Image, ImageFilter
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src); frames=[]
i=0
while True:
    frames.append(np.asarray(im.convert('RGB')).astype(np.float32)); i+=1
    try: im.seek(i)
    except EOFError: break
def cut(f):
    mn = f.min(axis=2)
    # color-to-alpha against white: soft shadow becomes translucent black
    a_raw = (255 - mn) / 255.0
    a = np.clip((a_raw - 0.04) / 0.96, 0, 1)      # kill near-white noise (alpha only)
    core = (mn < 90).astype(np.uint8) * 255
    m = Image.fromarray(core).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))  # close small holes
    m = m.filter(ImageFilter.MinFilter(5))   # interior only: thin legs and rims stay colour-to-alpha
    m = np.asarray(m.filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255
    alpha = np.maximum(a, m)
    # un-blend from white where translucent; keep original colour inside the bug
    a_un = np.maximum(a_raw, m)
    safe = np.maximum(a_un, 1e-3)[..., None]
    rgb = (f - 255 * (1 - a_un[..., None])) / safe
    rgb = rgb * (1 - m[..., None]) + f * m[..., None]
    rgb = np.clip(rgb, 0, 255)
    return np.dstack([rgb, alpha * 255]).astype(np.uint8), (mn < 150)
cuts = [cut(f) for f in frames]
alphas = np.stack([c[0][..., 3] for c in cuts])
ys, xs = np.where(alphas.max(axis=0) > 8)
pad = 6
x0, x1, y0, y1 = xs.min()-pad, xs.max()+pad+1, ys.min()-pad, ys.max()+pad+1
w, h = x1-x0, y1-y0
strip = Image.new('RGBA', (w*len(cuts), h), (0,0,0,0))
for k,(c,_) in enumerate(cuts):
    strip.paste(Image.fromarray(c[y0:y1, x0:x1], 'RGBA'), (k*w, 0))
strip.save(out)
# heading: principal axis of the bug core in frame 0, head = end nearer the antennae (top-left)
core = np.stack([c[1] for c in cuts]).mean(axis=0) > 0.5
yy, xx = np.where(core)
cx, cy = xx.mean(), yy.mean()
cov = np.cov(np.vstack([xx-cx, yy-cy]))
ev, evec = np.linalg.eigh(cov); v = evec[:, 1]
print('crop', x0, y0, w, h, 'frames', len(cuts), 'centroid', round(cx-x0,1), round(cy-y0,1), 'axis(img xy, y down)', v.round(3))
