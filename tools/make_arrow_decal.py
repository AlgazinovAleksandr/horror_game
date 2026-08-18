#!/usr/bin/env python3
"""Generate the Backrooms zone-1 navigation arrow as a REAL RGBA CUTOUT.

    <pack>/.venv/bin/python3 tools/make_arrow_decal.py

Writes game/assets/textures/level_backrooms/backrooms_arrow_glyph.png
(768 x 1024, RGBA, transparent background), then run Godot --import.

WHY THIS EXISTS (backlogs/04-backrooms.md B-A3, cross-level X38).
The arrow it replaces, `arrow_decal.png`, was the level's ONLY navigational signal
and a wrong reading costs 18 panic — 36 % of PANIC_MAX — and resets the counter.
Measured from real frames:

    arrow glyph, 3 m ....................... 120.7 lum
    the panel background it is painted on ... 126.3 lum   -> 2.2 % contrast
    the column the panel is stuck to ........ 153.9 lum   -> 22 % contrast

i.e. every part of the sign that carried NO information was ten times louder than
the part that did. Three separate faults, all of them in the asset:

  1. It was a 1254x1254 photograph of YELLOW WALLPAPER with a slightly darker
     arrow sprayed on it — a wall prop whose texture contains a picture of the
     surface it is mounted on (Issue 35 / X24, fifth recurrence). The baked
     background is a different yellow from the column, so the sign read as a
     rectangle stuck to a post rather than as paint on the post.
  2. It was RGB with NO ALPHA CHANNEL while the material set TRANSPARENCY_ALPHA,
     so there was nothing for the cutout to cut.
  3. Square source on a 0.45 x 0.70 quad = 1.556x vertical stretch.

So: no background at all (the column IS the background), a near-black glyph, and
a portrait canvas the mesh is sized from.

⚠️ DELIBERATELY CODE-DRAWN, not generated. An arrow is a geometric primitive with
one job — being unambiguous at 15 m — and a diffusion model cannot be asked for an
exact chevron. Deterministic: seeded, so re-running reproduces the file byte for
byte. This is the `level-1-image-generator` half of the image pipeline.

⚠️ NO EMISSION IS EVER APPLIED TO THIS TEXTURE by the level (see
backrooms.gd:_spawn_arrow_columns). Emission is most of a surface's colour in this
project (Issues 21/27/33), and a self-lit sign is exactly how the old one became a
glowing blob. The contrast here is albedo contrast and nothing else.
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 768, 1024
SS = 4  # supersample factor for clean edges
SEED = 4041

OUT = os.path.normpath(os.path.join(
    os.path.dirname(__file__), "..", "game", "assets", "textures",
    "level_backrooms", "backrooms_arrow_glyph.png"))

# Near-black stencil paint. Kept as ALBEDO only: against the hub-lit wallpaper
# column (measured 153.9 lum) this renders around 20-25 lum, i.e. ~85 % contrast,
# against the 2.2 % the old sign carried.
INK = (14, 13, 11)

# Glyph proportions, as fractions of the canvas. A road-marking arrow: a wide
# chevron head over a narrow shaft, so head and shaft are separable at distance
# and the UP/DOWN flip is legible from the silhouette alone.
TIP_Y = 0.055
HEAD_Y = 0.435
FOOT_Y = 0.945
HEAD_HALF = 0.325
SHAFT_HALF = 0.105


def arrow_polygon(w, h):
    cx = w / 2.0
    return [
        (cx, TIP_Y * h),
        (cx + HEAD_HALF * w, HEAD_Y * h),
        (cx + SHAFT_HALF * w, HEAD_Y * h),
        (cx + SHAFT_HALF * w, FOOT_Y * h),
        (cx - SHAFT_HALF * w, FOOT_Y * h),
        (cx - SHAFT_HALF * w, HEAD_Y * h),
        (cx - HEAD_HALF * w, HEAD_Y * h),
    ]


def stencil_noise(w, h, rng):
    """A coarse, blurred noise field used to erode the glyph's edges and mottle
    its interior, so it reads as sprayed paint rather than as vector art."""
    cell = 16
    small = Image.new("L", (w // cell + 2, h // cell + 2))
    small.putdata([rng.randint(0, 255) for _ in range(small.width * small.height)])
    field = small.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(3.0))
    return field


def main():
    rng = random.Random(SEED)

    big = Image.new("L", (W * SS, H * SS), 0)
    ImageDraw.Draw(big).polygon(arrow_polygon(W * SS, H * SS), fill=255)
    alpha = big.resize((W, H), Image.LANCZOS)

    # Erode the edges with the noise field: anywhere the field is dark, take a
    # bite out of the alpha. Clamped so the glyph's core stays fully opaque.
    field = stencil_noise(W, H, rng)
    fpx = field.load()
    apx = alpha.load()
    for y in range(H):
        for x in range(W):
            a = apx[x, y]
            if a == 0:
                continue
            n = fpx[x, y]
            # 0.78..1.0 multiplier over the interior; the same bite at the edge
            # removes whole pixels because `a` is already partial there.
            bite = 0.80 + 0.20 * (n / 255.0)
            apx[x, y] = int(min(255, a * bite))

    # A second, sparser pass punches a few dropouts right through, the way a worn
    # stencil skips. Only where the noise is extreme, so the shape never breaks.
    for y in range(H):
        for x in range(W):
            if apx[x, y] and fpx[x, y] < 26:
                apx[x, y] = int(apx[x, y] * 0.25)

    rgb = Image.new("RGB", (W, H), INK)
    # Faint tonal variation inside the ink, so it is not a flat die-cut.
    rgbpx = rgb.load()
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            v = (fpx[x, y] - 128) / 255.0
            c = tuple(max(0, min(255, int(INK[i] + v * 9))) for i in range(3))
            for dy in range(2):
                for dx in range(2):
                    if x + dx < W and y + dy < H:
                        rgbpx[x + dx, y + dy] = c

    out = Image.merge("RGBA", (*rgb.split(), alpha))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)

    opaque = sum(1 for p in alpha.getdata() if p > 200)
    print("wrote %s  %dx%d RGBA" % (OUT, W, H))
    print("  aspect        %.4f" % (W / float(H)))
    print("  opaque pixels %.1f %%" % (100.0 * opaque / (W * H)))
    print("  ink RGB       %s  (luminance %.1f)"
          % (str(INK), 0.2126 * INK[0] + 0.7152 * INK[1] + 0.0722 * INK[2]))


if __name__ == "__main__":
    main()
