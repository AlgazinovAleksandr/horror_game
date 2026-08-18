#!/usr/bin/env python3
"""Crop KONTUR's flat props out of the backgrounds their artwork was generated on.

WHY THIS EXISTS
---------------
ISSUES_SOLUTIONS Issue 35 / cross-level X24, SIXTH occurrence, and this time on the two
things the level's hardest gates ask the player to READ:

  * `door_black.png` / `door_red.png` (1254x1254) are a door PLUS the concrete wall and
    reveal around it. Hung on a 1.4 x 2.2 leaf that is a **1.571x** squash, and the whole
    of Gate 1 is telling one from the other — a wrong choice does not cost a strike, it
    drops the player through the floor and demotes them a whole level.
  * `label_{vinegar,bleach,water}.png` (1024x768) are three labels photographed on three
    DIFFERENT backdrops — saturated yellow, white, dark grey. On a 0.09 x 0.117 m quad at
    **1.733x**, on a `TRANSPARENCY_ALPHA` material with **no alpha channel**, that backdrop
    is not a backdrop: it is an opaque rectangle painted onto a bottle. The vinegar bottle
    was wearing a bright yellow flag.
  * `kontur_poster.png` and `kontur_panel_chute.png` are the same shape at 1.867x and
    1.333x — each is a picture of the concrete wall it hangs on.

WHAT IT DOES
------------
Two operations, both deterministic and both recorded here rather than re-derived:

  1. CROP to a box read off the source by eye and verified by viewing the result.
  2. KEY OUT the backdrop into a real alpha channel, by a **border-reachable** flood fill
     with a per-image colour tolerance — the same reachability limit `flatten_alpha_checker.py`
     uses, and for the same reason: it cannot eat a cream panel INSIDE the artwork, because
     the artwork's own border encloses it. Then crop again to the alpha bounding box.

     ⚠️ The keyer is not optional decoration on the labels. "A billboard texture must be a
     real RGBA cutout, or it renders as a solid rectangle" is a standing rule in this
     project, and all three labels shipped as 8-bit RGB.

The two doors are cropped and NOT keyed: a door leaf is a filled rectangle, and their two
crops land at 0.738 and 0.759 — within 3 % of each other, which matters more than either
absolute number. Both doors must be the SAME size in world space or the shape of the door
becomes a second tell alongside the colour, and gate 1's answer is supposed to be the
colour alone.

⚠️ NON-DESTRUCTIVE. Reads the shipped PNGs and writes NEW files beside them
(`tools/restencil_door.py`'s header records the opposite policy going wrong). Re-runnable.

⚠️ Run with the Pillow venv, and `--import` afterwards:
    <image-pack>/.venv/bin/python3 tools/crop_kontur_art.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
"""

import os
import sys
from collections import deque

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(HERE, "game", "assets", "textures", "level_5_kontur")

# (source, output, crop box, keyer tolerance or None)
#
# The crop boxes were read off the sources and verified by viewing every output; they are
# recorded rather than detected, because "find the object" is not a problem worth solving
# generically for seven images. The tolerances were chosen by measuring the distance from
# each backdrop's corner colour to the nearest colour inside the artwork.
JOBS = [
    # Gate 1 — the two doors. Cropped to the leaf, no keyer.
    ("door_black.png", "door_black_leaf.png", (198, 48, 1060, 1216), None),
    ("door_red.png", "door_red_leaf.png", (205, 75, 1055, 1195), None),
    # Gate 2 — the three labels. Keyed, because a bottle label is not a rectangle.
    ("label_vinegar.png", "label_vinegar_paper.png", (60, 140, 968, 640), 95),
    ("label_bleach.png", "label_bleach_paper.png", (0, 0, 1024, 768), 44),
    ("label_water.png", "label_water_paper.png", (0, 0, 1024, 768), 52),
    # Landing props.
    ("kontur_poster.png", "kontur_poster_sheet.png", (290, 80, 756, 676), 40),
    ("kontur_panel_chute.png", "kontur_chute_hatch.png", (196, 54, 850, 686), None),
]


def key_background(img, tol):
    """Alpha-out every pixel REACHABLE FROM THE BORDER whose colour is within `tol` of
    the border colour it was reached from. Returns an RGBA image.

    Reachability is the whole safety property: a cream panel in the middle of a label is
    the same colour family as a cream backdrop, and the artwork's own printed border is
    what stops the fill getting to it."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()

    # Reference colour = the median of the four corners, so one stray speck cannot set it.
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    ref = tuple(sorted(c[i] for c in corners)[1] for i in range(3))

    tol2 = tol * tol
    seen = bytearray(w * h)
    q = deque()

    def near(c):
        d0 = c[0] - ref[0]
        d1 = c[1] - ref[1]
        d2 = c[2] - ref[2]
        return d0 * d0 + d1 * d1 + d2 * d2 <= tol2

    for x in range(w):
        for y in (0, h - 1):
            if not seen[y * w + x] and near(px[x, y]):
                seen[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not seen[y * w + x] and near(px[x, y]):
                seen[y * w + x] = 1
                q.append((x, y))

    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                if near(px[nx, ny]):
                    seen[ny * w + nx] = 1
                    q.append((nx, ny))

    cleared = 0
    for y in range(h):
        row = y * w
        for x in range(w):
            if seen[row + x]:
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 0)
                cleared += 1
    return img, 100.0 * cleared / (w * h)


def main():
    if not os.path.isdir(TEX):
        sys.exit("error: %s not found" % TEX)
    for src, out, box, tol in JOBS:
        img = Image.open(os.path.join(TEX, src)).crop(box)
        note = ""
        if tol is None:
            img = img.convert("RGB")
        else:
            img, pct = key_background(img, tol)
            bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
            img = img.crop(bbox)
            note = "  keyed %.1f%% -> bbox %s" % (pct, bbox)
        img.save(os.path.join(TEX, out))
        print("%-28s %4dx%-4d aspect %.4f%s"
              % (out, img.width, img.height, img.width / img.height, note))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
