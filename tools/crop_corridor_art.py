#!/usr/bin/env python3
"""Crop two Corridor wall props out of the walls their artwork was generated on.

WHY THIS EXISTS
---------------
ISSUES_SOLUTIONS Issue 35, fourth and fifth occurrence: **a wall prop's texture may not
contain a picture of the wall it is mounted on.** Both of these did.

  * `ordinary_hotel_door.png` (1122x1402) is a door PLUS its architrave PLUS the wallpaper
    and wainscot to either side. Hung on a 1.3 x 2.1 m leaf it was also squashed 1.29x.
    Cropping to the leaf gives a 616 x 1334 (0.4618) source, so a 2.1 m tall door is
    **0.97 m** wide — a door-shaped door, with the architrave rebuilt as real geometry by
    `corridor.gd:_spawn_door_frame()`. Silhouette carries a prop; art does not.
  * `kontur_plate.png` (1024x768) is a brass plate on damask wallpaper above a wainscot.
    It carries KONTUR Gate 3's only hint in this level — four words the player has to be
    able to READ — and it was hung on a 2.0 x 3.0 m full-height panel, i.e. a 1.333
    landscape source squashed onto a 0.667 portrait mesh: **2.00x**, the worst distortion
    measured anywhere in the level. Cropped to the plate it is 474 x 239 (1.983) and hangs
    at plate size, at eye height.

The plate crop also gets an ALPHA MASK. Its outline is an ogee-cornered rectangle, so a
rectangular crop keeps four triangles of the generator's own wallpaper in the corners —
which is Issue 35 again, in miniature. The mask is a plain octagon: deterministic, no
keying heuristics, and it costs a couple of millimetres of the brass bead at each corner.

⚠️ NON-DESTRUCTIVE. Reads the shipped PNGs and writes NEW files beside them, because
`tools/restencil_door.py`'s header records the opposite policy going wrong ("run it once,
on a copy"). Re-runnable.

⚠️ Run with the Pillow venv, and `--import` afterwards:
    nano-banana-pro/.venv/bin/python3 tools/crop_corridor_art.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
"""

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(HERE, "game", "assets", "textures", "level_3_corridor")

# Crop boxes were read off the source images by eye and then verified by viewing the
# result; they are recorded here rather than re-derived, because "find the leaf" is not a
# problem worth solving generically for two images.
DOOR_SRC = "ordinary_hotel_door.png"
DOOR_OUT = "hotel_door_leaf.png"
DOOR_BOX = (272, 18, 888, 1352)          # 616 x 1334 -> 0.4618

PLATE_SRC = "kontur_plate.png"
PLATE_OUT = "kontur_plate_crop.png"
PLATE_BOX = (268, 183, 742, 422)         # 474 x 239 -> 1.983
# Octagon in crop-local pixels: the plate's flat edges with its corners cut.
PLATE_MASK = [
    (52, 2), (421, 2), (471, 55), (471, 184),
    (421, 236), (52, 236), (2, 184), (2, 55),
]


def main() -> int:
    src = Image.open(os.path.join(TEX, DOOR_SRC)).convert("RGB")
    leaf = src.crop(DOOR_BOX)
    leaf.save(os.path.join(TEX, DOOR_OUT))
    print("%s  %dx%d  aspect %.4f" % (DOOR_OUT, leaf.width, leaf.height,
                                      leaf.width / leaf.height))

    src = Image.open(os.path.join(TEX, PLATE_SRC)).convert("RGB")
    plate = src.crop(PLATE_BOX).convert("RGBA")
    mask = Image.new("L", plate.size, 0)
    ImageDraw.Draw(mask).polygon(PLATE_MASK, fill=255)
    plate.putalpha(mask)
    plate.save(os.path.join(TEX, PLATE_OUT))
    opaque = sum(mask.point(lambda v: 1 if v > 0 else 0).convert("L").tobytes())
    print("%s  %dx%d  aspect %.4f  opaque %.1f%%" % (
        PLATE_OUT, plate.width, plate.height, plate.width / plate.height,
        100.0 * opaque / (plate.width * plate.height)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
