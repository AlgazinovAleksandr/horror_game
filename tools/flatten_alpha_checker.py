#!/usr/bin/env python3
"""Flatten a BAKED ALPHA CHECKERBOARD out of an opaque texture, then crop to content.

    nano-banana-pro/.venv/bin/python3 tools/flatten_alpha_checker.py \
        assets_src/textures/level_1_lab/lab_breaker_panel_raw.png \
        game/assets/textures/level_1_lab/lab_breaker_panel.png

Why this exists (2026-08-16, Lab revision round). `lab_breaker_panel.png` shipped as an
8-bit RGB PNG *with no alpha channel* whose background was the light two-tone
transparency checkerboard an image editor draws to represent transparency. Nothing in
Godot can know that is meant to be nothing: it is opaque near-white pixel data, and
near-white is the brightest albedo in a level lit at ~0.45 energy with no tonemapping.

Measured on the shipped build, torch locked off in the pitch-black BreakerNook:
the panel's brightest pixels were 4.1/255 against a wall averaging 0.3/255 — Michelson
contrast 0.86, and ~9 % of the panel's pixels brighter than ANYTHING in the wall around
it, at 6, 10 and 15 m alike. The player photographed it from ~9.4 m and wrote "I am
standing far away from the breaker and I see it".

The border is not croppable on its own: the panel's door hangs at an angle, so 5.5 % of
the checkerboard survives inside the content bounding box, in the corners. So:

  1. FLOOD FILL the background from the image border, over near-neutral near-white
     pixels only — that is exactly the region an alpha channel would have made
     transparent, and it can never eat a cream label or a specular highlight in the
     middle of the artwork because it is reachability-limited, not threshold-limited.
  2. Repaint it FILL (a dark neutral), i.e. composite the art onto black instead of onto
     white.
  3. Crop to the remaining content.

⚠️ Destructive. Run it from the copy in assets_src/, never on the shipped file, or the
second run flattens the already-flattened output's own dark border into the artwork.
⚠️ Godot needs `--headless --path game --import` afterwards, and `file` should report
"PNG image data" (Issues 1 and 25).
"""

import sys
from collections import deque

from PIL import Image

# The checkerboard tones measured in this asset were (254,254,254) and (243,243,243).
WHITE_MIN = 235          # every channel above this ...
NEUTRAL_SPREAD = 8       # ... and max-min channel spread below this = background
FILL = (10, 10, 11)      # a dark neutral: what the art would look like over black
CONTENT_MAX = 235        # a pixel is "content" if any channel is at or below this


def flatten(src: str, dst: str) -> None:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()

    def is_background(x: int, y: int) -> bool:
        r, g, b = px[x, y]
        return min(r, g, b) > WHITE_MIN and (max(r, g, b) - min(r, g, b)) <= NEUTRAL_SPREAD

    # 1 + 2 — flood fill inward from every border pixel.
    seen = bytearray(w * h)
    q: deque = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    filled = 0
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if not is_background(x, y):
            continue
        px[x, y] = FILL
        filled += 1
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))

    # 3 — crop to what is left that is not the fill colour.
    left, top, right, bottom = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if (r, g, b) == FILL:
                continue
            if min(r, g, b) > CONTENT_MAX:
                continue
            left = min(left, x)
            right = max(right, x)
            top = min(top, y)
            bottom = max(bottom, y)
    if right < 0:
        raise SystemExit("no content found — refusing to write an empty texture")

    out = im.crop((left, top, right + 1, bottom + 1))
    out.save(dst)
    print("%s -> %s" % (src, dst))
    print("  background pixels flattened : %d (%.1f%%)" % (filled, 100.0 * filled / (w * h)))
    print("  cropped                     : %dx%d -> %dx%d" % (w, h, out.size[0], out.size[1]))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    flatten(sys.argv[1], sys.argv[2])
