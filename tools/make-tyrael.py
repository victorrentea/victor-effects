#!/usr/bin/env python3
"""✨ Fable's other half: Tyrael (Diablo II, the Act IV NPC) -> assetsDir/tyrael.mov.

    make-tyrael.py <tyrael.gif> <fable-descent.mov> <out.mov>

Victor (2026-11-24): the alternative to ✨ Fable is *"exactly the one from the game"* — the
white archangel with the wings of light. The source is the game's own sprite, the 15-frame
idle loop (0.1 s each, 600x240 on black) as the Diablo wiki hosts it (`Tyrael2.gif`); it is
Blizzard's, so it lives in `assetsDir` with the clip made from it, never in this repo.

The clip is Fable's twin so the two can take turns on one key: same length, same SOUND (the
track of `fable-descent.mov`, copied), same beats on it —

    0.0 - 1.0 s  nothing (the music swells)
    1.0 - 3.9 s  he comes down from above the top edge to the middle, wings beating
    3.3 - 4.0 s  he brightens, a halo gathers behind him
    4.0 s        the bang: a burst of white light and rays, a ring running out
    4.0 - 8.4 s  he hovers in a pulsing halo, sparks drifting off him
    8.4 - 9.2 s  everything fades (the player fades the last 0.8 s again on top)

Keyed like the others: the light is drawn on black and keyed by luminance with Fable's gentle
curve (so it lights the desktop translucently), the sprite with a steeper one (so the dark
armour stays solid). Colour = premultiplied, the sprite's left unclamped so its dim fringes
add light rather than outline the wings in grey. HEVC with alpha + the sound,
muxed in ONE ffmpeg run (re-muxing an HEVC-alpha stream with -c:v copy breaks it).
"""
import math, subprocess, sys, tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter, ImageSequence

W, H, FPS = 1920, 1080, 24
SCALE = 2.2                      # 600x240 -> 1320x528: the wings span ~2/3 of the screen
LIFE = 9.2                       # = fable-descent.mov
T_IN, T_LAND, T_BANG, T_OUT = 1.0, 3.9, 4.0, 8.4
REST_Y = H / 2 + 20              # sprite centre at rest (screen y grows down)
LO, HI, GAMMA = 0.035, 0.60, 0.85   # Fable's glow key
S_LO, S_HI = 0.10, 0.30             # the sprite's: brown armour stays opaque, grey fringes don't

rng = np.random.default_rng(7)
YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)

# rays: a fixed fan of narrow spikes, slowly turning
N_BINS = 2048
_th = np.linspace(-math.pi, math.pi, N_BINS, endpoint=False)
RAYS = np.zeros(N_BINS, np.float32)
for _ in range(56):
    a, w, k = rng.uniform(-math.pi, math.pi), rng.uniform(0.004, 0.02), rng.uniform(0.4, 1.0)
    d = np.angle(np.exp(1j * (_th - a)))
    RAYS += k * np.exp(-(d / w) ** 2)

SPARKS = [(rng.uniform(-math.pi, math.pi), rng.uniform(80, 520), rng.uniform(1.5, 4.0),
           rng.uniform(T_BANG, T_OUT - 0.5)) for _ in range(260)]


def ease_out(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return 1 - (1 - x) ** 3


def smooth(a: float, b: float, t: float) -> float:
    x = min(max((t - a) / (b - a), 0.0), 1.0)
    return x * x * (3 - 2 * x)


def load_sprite(gif: str) -> list[np.ndarray]:
    im = Image.open(gif)
    w, h = round(im.width * SCALE), round(im.height * SCALE)
    return [np.asarray(f.convert("RGB").resize((w, h), Image.LANCZOS), np.float32) / 255
            for f in ImageSequence.Iterator(im)]


def centre(t: float) -> tuple[float, float]:
    top = -H * 0.35
    y = top + (REST_Y - top) * ease_out((t - T_IN) / (T_LAND - T_IN))
    if t > T_LAND:
        y += 8 * math.sin((t - T_LAND) * 2 * math.pi / 2.4)
    return W / 2, y


def glow(t: float, cx: float, cy: float) -> np.ndarray:
    """The light, additive, on black."""
    dx, dy = XX - cx, YY - cy
    r = np.sqrt(dx * dx + dy * dy)
    out = np.zeros((H, W, 3), np.float32)
    blue, white, gold = (np.array(c, np.float32) for c in ((0.65, 0.82, 1.0), (1, 1, 1), (1.0, 0.86, 0.6)))

    # the halo: gathers before the bang, pulses after it
    gather = smooth(3.3, T_BANG, t)
    pulse = 0.55 + 0.12 * math.sin((t - T_BANG) * 2 * math.pi / 1.6) if t > T_BANG else 0
    halo = max(0.45 * gather, pulse) * (1 - smooth(T_OUT, LIFE, t))
    if halo > 0:
        out += (halo * np.exp(-(r / 330) ** 2))[..., None] * blue
        out += (0.6 * halo * np.exp(-(r / 90) ** 2))[..., None] * white

    if t >= T_BANG:
        s = t - T_BANG
        fade = 1 - smooth(T_OUT, LIFE, t)
        flash = math.exp(-s / 0.35) * 2.2 + 0.25                    # white-out, then settles
        R = 160 + 1500 * ease_out(s / 1.6)
        out += (fade * flash * np.exp(-(r / R) ** 2))[..., None] * white
        # rays
        th = np.arctan2(dy, dx) + 0.08 * s
        idx = ((th + math.pi) / (2 * math.pi) * N_BINS).astype(np.int32) % N_BINS
        L = 250 + 1400 * ease_out(s / 1.2)
        ray = RAYS[idx] * np.exp(-r / L) * (0.9 * math.exp(-s / 1.4) + 0.25) * fade
        out += ray[..., None] * gold
        # the ring running out
        rr = 120 + 2200 * ease_out(s / 1.3)
        ring = math.exp(-s / 0.7) * np.exp(-((r - rr) / 40) ** 2) * fade
        out += ring[..., None] * blue
        # sparks
        sp = Image.new("L", (W, H))
        px = sp.load()
        for a, v, size, born in SPARKS:
            age = t - born
            if 0 <= age < 2.2:
                d = 140 + v * age
                x, y = int(cx + d * math.cos(a)), int(cy + d * math.sin(a) + 30 * age * age)
                life = (1 - age / 2.2) * fade
                for ox in range(-1, 2):
                    for oy in range(-1, 2):
                        if 0 <= x + ox < W and 0 <= y + oy < H:
                            px[x + ox, y + oy] = max(px[x + ox, y + oy], int(255 * life))
        spark = np.asarray(sp.filter(ImageFilter.GaussianBlur(1.6)), np.float32) / 255 * 3
        out += spark[..., None] * white
    return out


def frame(t: float, sprite: list[np.ndarray]) -> np.ndarray:
    cx, cy = centre(t)
    g = glow(t, cx, cy)
    ga = np.clip((g.max(axis=2) - LO) / (HI - LO), 0, 1) ** GAMMA
    rgb = np.minimum(g, ga[..., None])
    a = ga.copy()

    if t >= T_IN:
        s = sprite[int(t / 0.1) % len(sprite)]
        gain = 1 + 0.6 * smooth(3.3, T_BANG, t) - 0.25 * smooth(T_BANG, T_BANG + 1.2, t)
        s = np.clip(s * gain, 0, 1) * (1 - smooth(T_OUT, LIFE, t))
        sa = np.clip((s.max(axis=2) - S_LO) / (S_HI - S_LO), 0, 1)
        sp = s   # NOT clamped to sa: the wings' dim grey fringes ADD light (as over black) instead
                 # of painting a dark outline round the wings on a light desktop
        h, w = sa.shape
        x0, y0 = int(round(cx - w / 2)), int(round(cy - h / 2))
        X0, Y0, X1, Y1 = max(x0, 0), max(y0, 0), min(x0 + w, W), min(y0 + h, H)
        if X1 > X0 and Y1 > Y0:
            sub = (slice(Y0, Y1), slice(X0, X1))
            ss = (slice(Y0 - y0, Y1 - y0), slice(X0 - x0, X1 - x0))
            k = sa[ss][..., None]
            rgb[sub] = sp[ss] + rgb[sub] * (1 - k)
            a[sub] = sa[ss] + a[sub] * (1 - sa[ss])
    return np.round(np.clip(np.dstack([rgb, a]), 0, 1) * 255).astype(np.uint8)


def main(gif: str, fable: str, out: str) -> None:
    sprite = load_sprite(gif)
    n = round(LIFE * FPS)
    with tempfile.TemporaryDirectory() as tmp:
        for i in range(n):
            Image.fromarray(frame(i / FPS, sprite), "RGBA").save(f"{tmp}/{i:04d}.png", compress_level=1)
        subprocess.run(["ffmpeg", "-v", "error", "-y",
                        "-framerate", str(FPS), "-i", f"{tmp}/%04d.png", "-i", fable,
                        "-map", "0:v", "-map", "1:a",
                        "-c:v", "hevc_videotoolbox", "-alpha_quality", "0.9", "-q:v", "70",
                        "-pix_fmt", "bgra", "-tag:v", "hvc1",
                        "-c:a", "copy", "-shortest", out], check=True)
    print(f"{out}: {n} frames, {Path(out).stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
