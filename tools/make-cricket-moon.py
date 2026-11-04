#!/usr/bin/env python3
"""🦗 Turns Victor's Gemini cricket clip into the alpha video tile 12 plays in the
bottom-left corner: `assetsDir/cricket-moon.mov`.

Written for his clip of 2026-11-04 (1280x720 @ 24 fps, 239 frames): a flat cartoon
cricket under a crescent moon. For 0.5 s it stands on a brown hill under a blue sky,
then the whole landscape fades to pure black and only the cricket and the moon stay
lit, blinking, until the stars fade back in for the last 0.8 s. Only this script is
committed; the video lives in assetsDir (docs/assets-and-licences.md).

- **The landscape is cut in time, not keyed.** The hill runs under the feet and the
  sky behind the antennae, so no key takes them off cleanly. By frame `FIRST` the
  scene has faded out and the feet stand on nothing: everything before it is dropped.
  What is left is 227 frames, 9.46 s, for a 9.41 s clip.
- **Over black, the picture already IS the premultiplied foreground**, so only the
  alpha has to be found: the colour is the source pixel, untouched, which is what
  `AVPlayerLayer` composites (`tools/phoenix-matte.py`). A dark backdrop therefore
  gets exactly the film back; only a light one can show a bad alpha.
- **Alpha is solid inside and a ratio on the rim.** Eroded from a low threshold
  (`KEY`), the shape is opaque, dark wing bands included. In the soft rim alpha is
  the pixel over the brightest pixel near it, the real coverage of a bright shape
  over black. A plain luminance ramp would leave the moon a dark fringe on white.
- **The eyes are black on black.** Open, they are the same 0 as the sky, so no key
  can see them: they are drawn into the alpha as two discs, measured on the first
  frames while the sky is still blue behind them. Their height follows the white
  highlight, since the head tilts a few pixels; shut, the lid is lit and needs only
  a smaller disc, for the dark line across it.
- **The stars are held from the first frame.** The film only has them under the
  blue sky and in its last 0.8 s, so they would have reached the room a fraction of
  a second before the sound ended. They are read off the last frames and put behind
  the cricket in every frame, tinted the moon's colour: white ones vanish on a white
  slide.

Needs numpy, pillow and ffmpeg with hevc_videotoolbox.

    tools/make-cricket-moon.py clip.mp4 ~/.victor-effects/assets/cricket-moon.mov
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

W, H = 1280, 720
FPS = 24
FIRST = 12            # frame 11 still carries the sky at level 1; 12 is clean black
CROP = (120, 0, 1004, 646)   # the stars' left, the frame's top, the antennae, under the feet
NOISE = 6             # below this the codec's ringing, never picture
KEY = 14              # above this, subject (the dim antennae sit around 40-60)
RIM_OUT = 3           # px the soft rim reaches outside the keyed shape…
RIM_IN = 4            # …and inside it: the film's edges are soft over about that much
LOCAL = 5             # radius of "the brightest pixel near it": must reach the plateau
DIM_NEAR = 110        # with nothing brighter than this near, a pixel is on a dark shape's rim
EYES = ((815.5, 339.6, 12.5), (887.6, 327.2, 15.3))  # x, y of the disc, highlight's dx
EYE_R = 29.0          # measured under the blue sky
EYE_R_SHUT = 25.0     # inside the lid, for the dark line across it
EYE_SWING = 7         # px the highlight rides above/below rest with the head's tilt
LIT = 70              # a lid shows this much in the disc; an open eye is black
STAR_FRAMES = 5       # the last frames, where every star has finished fading in
STAR_TINT = np.array((250, 226, 140), np.float32)
SLIVER = (640, 700, 14)  # a star cut by the film's top edge: x from, x to, y to
HIGHLIGHT = 200       # min channel of the eye's white dot
ANTENNAE = (600, 300, 30, 0.8, 90)  # x from, y to, ramp px, extra gain, only below this level


def read_frames(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo",
                          "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3).astype(np.float32)


def grow(mask, r):
    return np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).filter(
        ImageFilter.MaxFilter(2 * r + 1))) > 0


def shrink(mask, r):
    return np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).filter(
        ImageFilter.MinFilter(2 * r + 1))) > 0


def local_max(lum, r):
    img = Image.fromarray(np.clip(lum, 0, 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.MaxFilter(2 * r + 1))).astype(np.float32)


def disc(cx, cy, r):
    """An antialiased disc as alpha."""
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    return np.clip(r - np.hypot(x - cx, y - cy) + 0.5, 0, 1)


def key(frame, stars, eyes):
    """(alpha, premultiplied colour) of the cricket and moon in one frame. The eyes
    count as shape, or the seam where the head meets them would turn see-through."""
    lum = frame.max(axis=2)
    lum = np.where(stars, 0, lum)
    shape = lum > KEY
    near = local_max(lum, LOCAL)
    alpha = np.where(lum > NOISE, lum / np.maximum(near, 1), 0)
    # A dark shape's rim has no plateau to be a share of, and the ratio came out
    # serrated along the wing's top: where nothing bright is near, a plain ramp.
    dim = np.clip((DIM_NEAR - near) / 40, 0, 1) * np.clip((lum - KEY) / KEY, 0, 1)
    alpha = np.where(grow(shape, RIM_OUT), np.maximum(alpha, dim), 0)
    alpha = np.where(shrink(shape | (eyes > 0.5), RIM_IN), 1, alpha)
    alpha = np.maximum(alpha, eyes)
    return alpha, lift_antennae(np.where(alpha[..., None] > 0, frame, 0))


def lift_antennae(rgb):
    """The antennae are the film's darkest lit thing, and a dark desktop is where this
    plays most: they get a gain, ramped off before the head starts."""
    x0, y1, ramp, gain, below = ANTENNAE
    y = np.arange(H, dtype=np.float32)[:, None, None]
    g = 1 + gain * np.clip((y1 - y) / ramp, 0, 1)
    g = np.where((rgb.max(axis=2, keepdims=True) < below) & (np.arange(W)[None, :, None] >= x0), g, 1)
    return rgb * g


def eye_alpha(frame, held):
    """The two eyes' discs. `held` is each eye's last y, updated in place."""
    out = np.zeros((H, W), np.float32)
    for i, (cx, rest_y, dx) in enumerate(EYES):
        x0, y0 = int(cx - EYE_R), int(rest_y - EYE_R)
        box = frame[y0:y0 + int(2 * EYE_R), x0:x0 + int(2 * EYE_R)]
        dots = np.argwhere(box.min(axis=2) > HIGHLIGHT)
        if len(dots) > 35:  # the dot, whole: the eye is open and shows where it is
            y = float(dots[:, 0].mean()) + y0
            held[i] = float(np.clip(y, rest_y - EYE_SWING, rest_y + EYE_SWING))
        lit = (box.max(axis=2) > LIT).mean()
        shut = len(dots) == 0 and lit > 0.55
        out = np.maximum(out, disc(cx, held[i], EYE_R_SHUT if shut else EYE_R))
    return out


def star_layer(frames):
    """(alpha, premultiplied colour, mask) of the stars, off the film's last frames."""
    lit = np.zeros((H, W), bool)
    for frame in frames[FIRST:215]:  # before the stars start: subject only
        lit |= frame.max(axis=2) > KEY
    subject = grow(lit, 5)
    lum = frames[-STAR_FRAMES:].mean(axis=0).max(axis=2)
    lum = np.where(subject, 0, lum)
    lum[:SLIVER[2], SLIVER[0]:SLIVER[1]] = 0
    lum = np.where(lum > NOISE + 2, lum, 0)
    alpha = np.clip(lum / 255, 0, 1) ** 0.75  # the glow, lifted: it has no backdrop to read on
    return alpha, alpha[..., None] * STAR_TINT, grow(lum > 0, 2)


def main(source, out):
    frames = read_frames(source)
    star_a, star_rgb, star_mask = star_layer(frames)
    x0, y0, x1, y1 = CROP
    held = [e[1] for e in EYES]
    with tempfile.TemporaryDirectory() as tmp:
        for n, frame in enumerate(frames[FIRST:]):
            alpha, rgb = key(frame, star_mask, eye_alpha(frame, held))
            top = alpha[..., None]
            rgb = rgb + (1 - top) * star_rgb        # the cricket stands in front of the sky
            alpha = alpha + (1 - alpha) * star_a
            # Premultiplied colour cannot exceed its alpha: the antennae's gain would.
            rgba = np.dstack([np.minimum(rgb, alpha[..., None] * 255), alpha * 255])[y0:y1, x0:x1]
            Image.fromarray(np.round(rgba).astype(np.uint8), "RGBA").save(f"{tmp}/{n:03d}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS),
                        "-i", f"{tmp}/%03d.png", "-c:v", "hevc_videotoolbox",
                        "-alpha_quality", "0.9", "-q:v", "70", "-pix_fmt", "bgra",
                        "-tag:v", "hvc1", "-an", str(out)], check=True)
    print(f"{out}: {len(frames) - FIRST} frames, {x1 - x0}x{y1 - y0}, "
          f"{Path(out).stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
