#!/usr/bin/env python3
"""`screamer_false_door.png` — the picture the false room 217 throws in your face.

    <pack>/.venv/bin/python3 tools/make_false_door_screamer.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

WHY THE SHIPPED ART WAS REPLACED
--------------------------------
Playtest capture 002, 2026-08-18: *"Make the image more dark and aggressive"*.

That is not a mood note in this renderer, it is a measurement. `flash_scare` puts this image
FULLSCREEN over a black panel for 0.9 s, and the game has no tonemapping, no glow and no
exposure control — whatever is in the file is what hits the eye. Measured mean luminance of
every screamer this level can show, on a 0-255 scale:

    screamer_false_door.png (v1)   57.97      1.97 % of pixels above 0.90 sRGB
    screamer_hotel.png (the FATAL  15.04      0.00 %
      Corridor screamer)
    screamer_manager.png           10.82      0.00 %
    screamers/shared_screamer.png   8.48      0.00 %

v1 was a pale, evenly-lit cream face on a lit background: **4x brighter than the level's own
death screamer and the only screamer in the game with blown-out pixels in it.** After 185 m of
a hall lit at ~0.45 energy it reads as a flashbang with a face in it, which is why "aggressive"
and "dark" arrived in the same sentence — the image had no shadow to be aggressive in.

WHAT THIS DOES
--------------
1. Picks up the flux generation kept at
   `assets_src/textures/level_3_corridor/screamer_false_door_raw.jpg` (prompt in the header of
   the git history and in `backlogs/03-corridor.md` §11). Composition chosen deliberately: a
   LUNGE out of a doorway with the frame visible either side, so it cannot be confused with
   `screamer_hotel.png`, which is a static head-on portrait and means *you are dead*.
2. Grades it: a radial vignette that crushes the surround to true black, a global multiply,
   a shadow-deepening gamma, and a faint rust cast to sit in the level's palette.

⚠️ THE GRADE IS AIMED AT A NUMBER, NOT AT TASTE. The target is the level's own fatal screamer
(mean ~15), because that is the brightness the player's eye is already calibrated to in this
corridor. `check_corridor_events.gd` asserts the shipped file against `screamer_hotel.png`
directly, so this tool and that guard cannot drift apart.

⚠️ AND "DARK" MUST NOT BECOME "A BLACK RECTANGLE". The picture is on screen for 0.9 s and has
to be legible in that time, so the grade preserves the subject's own highlights and spends the
darkening on the surround. The guard asserts that floor too. Shipped:

    screamer_false_door.png (v2)   11.35      0.00 % hot   p99 114.4   peak 185.6

i.e. **5.1x darker than v1, still darker than the fatal screamer it must not be mistaken for,
and with a p99 nearly three times the legibility floor.**

⚠️ NOT AN RGBA CUTOUT, on purpose. This is a full frame shown over `Screamer`'s black panel
with STRETCH_KEEP_ASPECT_CENTERED, not a billboard in the world — there is nothing behind it
for an alpha channel to reveal, and the project's cutout rule (a billboard texture must be a
real RGBA cutout or it renders as a solid rectangle) is about world-space quads.

Deterministic: same input, byte-identical output. Pillow only.
"""
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets_src", "textures", "level_3_corridor",
                   "screamer_false_door_raw.jpg")
DST = os.path.join(ROOT, "game", "assets", "textures", "level_3_corridor",
                   "screamer_false_door.png")

# ---- the grade -----------------------------------------------------------------------------
# Swept against the measured target (mean <= 15, hot 0.00 %, p99 >= 40) rather than eyeballed;
# the numbers each run of this file prints are the acceptance criteria. EXPOSURE was swept at
# 0.62 / 0.70 / 0.78 -> mean 8.35 / 10.18 / 11.35 and p99 88.9 / 102.6 / 114.4; 0.78 is the
# brightest that still lands under the fatal screamer, which is the ceiling that matters.
VIGNETTE_INNER = 0.30   # fraction of the half-diagonal held at full strength
VIGNETTE_OUTER = 0.92   # ...and where it has fallen to VIGNETTE_FLOOR
VIGNETTE_FLOOR = 0.06   # the corners are all but black; the doorway frame stops being a shape
EXPOSURE = 0.78         # global multiply
GAMMA = 1.16            # > 1 deepens the shadows and leaves the highlights roughly alone
TINT = (1.00, 0.93, 0.83)   # the level's antique rust cast; `screamer_hotel.png` reads warm


def _vignette(x: int, y: int, w: int, h: int) -> float:
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    half = math.hypot(cx, cy)
    r = math.hypot(x - cx, y - cy) / half
    if r <= VIGNETTE_INNER:
        return 1.0
    if r >= VIGNETTE_OUTER:
        return VIGNETTE_FLOOR
    t = (r - VIGNETTE_INNER) / (VIGNETTE_OUTER - VIGNETTE_INNER)
    t = t * t * (3.0 - 2.0 * t)          # smoothstep
    return 1.0 + (VIGNETTE_FLOOR - 1.0) * t


def main() -> int:
    if not os.path.exists(SRC):
        print("missing source: %s" % SRC)
        return 1
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    px = im.load()

    # Precompute the vignette per (x, y) via separable-ish direct evaluation; the image is
    # 1024x1024 so a straight double loop is fine and keeps this readable.
    for y in range(h):
        for x in range(w):
            v = _vignette(x, y, w, h)
            r, g, b = px[x, y]
            out = []
            for c, t in zip((r, g, b), TINT):
                f = (c / 255.0) ** GAMMA * EXPOSURE * v * t
                out.append(max(0, min(255, int(round(f * 255.0)))))
            px[x, y] = tuple(out)

    im.save(DST, "PNG")

    # ---- report the acceptance numbers, every run.
    lums = []
    hot = 0
    for y in range(0, h, 3):
        for x in range(0, w, 3):
            r, g, b = px[x, y]
            l = 0.2126 * r + 0.7152 * g + 0.0722 * b
            lums.append(l)
            if l > 0.90 * 255:
                hot += 1
    lums.sort()
    print("wrote %s" % DST)
    print("  %dx%d  mean=%.2f  p50=%.1f  p99=%.1f  peak=%.1f  >0.90=%.2f%%  (n=%d)"
          % (w, h, sum(lums) / len(lums), lums[len(lums) // 2],
             lums[int(len(lums) * 0.99)], lums[-1], hot / len(lums) * 100.0, len(lums)))
    print("  target: mean <= screamer_hotel.png's 15.0 x 1.25, hot ~ 0.00 %, p99 >= 40")
    return 0


if __name__ == "__main__":
    sys.exit(main())
