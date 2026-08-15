#!/usr/bin/env python3
"""Crop a door texture to its leaf and repaint its stencilled sign in English.

WHY THIS EXISTS
---------------
`assets_src/textures/intro/door_from_intro_to_lab.png` came back from the generator as a
beautiful asylum door with two problems for this project:

  1. A baked-in dark vignette AROUND the door. `tools/cutout_alpha.py --chroma auto`
     keys most of it away, but a door is a RECTANGLE, so the honest fix is to crop to
     the leaf and go fully opaque — a partially-transparent gradient fringe renders as
     a dark halo on the wall, which is ISSUES_SOLUTIONS Issue 35 wearing a thin coat.
  2. The sign reads ПСИХИАТРИЧЕСКОЕ ОТДЕЛЕНИЕ БЛОК D-7. Every note in the game is in
     English, and the Soviet-facility reveal belongs to KONTUR (level 5), four levels
     later. The user's call (2026-08-15) was to repaint it in English.

WHAT IT DOES
------------
  * crops to the bounding box of ALPHA > 200 — i.e. the solid door leaf — and drops the
    alpha channel, because the result is a plain rectangular door face
  * "erases" the old stencil by marking the ink against a wide median and then DIFFUSING
    the surrounding plate into it — see erase_stencil() for why every cheaper method
    left the Cyrillic readable
  * redraws the sign in English through a worn mask — the glyphs are eroded with noise
    and composited at partial opacity, because a crisp black label on a rotted door is
    the one thing that would look pasted on

⚠️ It does not get the plate perfectly clean, and it is not meant to. A faint mottling
   survives where the old strokes were; at the 0.08 emission `door.gd:84` gives a textured
   door, in a room lit at 0.15 ambient, it reads as corrosion. Chasing it further cost more
   than it was worth — the two dead ends are documented in erase_stencil() so nobody
   repeats them.

⚠️ Idempotent it is NOT. Run it once, on a COPY in `game/assets/` — never on the original in
   `assets_src/`, which is the only file this can be re-run from. It writes in place.
⚠️ Run AFTER cutout_alpha.py (it needs the alpha channel to find the leaf) and BEFORE
   the Godot `--import` pass.
"""

import random
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("error: Pillow is required. Use nano-banana-pro/.venv/bin/python3")

# The sign, in leaf coordinates, measured off the source. Three lines, right-aligned
# against the same margin the Cyrillic used, with the caduceus at x<310 left untouched.
TEXT_BOX = (335, 145, 615, 300)
# (text, size multiple of the fitted base). The third line is larger, as it is in the
# source: БЛОК D-7 is the line the sign is really about.
LINES = [("PSYCHIATRIC", 1.0), ("WING", 1.0), ("BLOCK D-7", 1.18)]

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Narrow Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]


def load_font(size: int) -> "ImageFont.FreeTypeFont":
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def crop_to_leaf(im: "Image.Image") -> "Image.Image":
    """Bounding box of the genuinely opaque pixels, then drop alpha."""
    if im.mode != "RGBA":
        return im.convert("RGB")
    solid = im.getchannel("A").point(lambda v: 255 if v > 200 else 0)
    box = solid.getbbox()
    if box is None:
        return im.convert("RGB")
    return im.crop(box).convert("RGB")


def _mean_luma(im: "Image.Image") -> float:
    g = im.convert("L")
    px = g.load()
    w, h = g.size
    return sum(px[x, y] for y in range(0, h, 3) for x in range(0, w, 3)) / \
        max(1, len(range(0, h, 3)) * len(range(0, w, 3)))


def _ink_fraction(im: "Image.Image") -> float:
    """Share of pixels markedly darker than a wide median — i.e. how lettered/marked it is."""
    g = im.convert("L")
    med = g.filter(ImageFilter.MedianFilter(size=31))
    gp, mp = g.load(), med.load()
    w, h = g.size
    n = hit = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            n += 1
            if gp[x, y] < mp[x, y] - 18:
                hit += 1
    return hit / max(1, n)


def erase_stencil(im: "Image.Image", box: "tuple[int, int, int, int]",
                  donor_dy: int = 230) -> None:
    """Rebuild the plate under the old text, in place — by diffusion, not by thresholding.

    ⚠️ The obvious approach does not work, and it fails *subtly*, which is worse. Taking a
    wide median as the "plate" and pulling every darker pixel toward it leaves a legible
    grey ghost of every thick stroke, because inside a 10 px stroke the median is itself
    contaminated by the stroke. Measured across radii 9/21/31/41 and one and two passes:
    line 1 cleared, lines 2-3 stayed readable every time, and a second pass merely turned
    the ghost from dark to light. A player would still be reading Cyrillic.

    So: mark the ink, then DIFFUSE the surrounding plate into it. Repeated blur-and-paste
    converges on a fill with no memory of what was underneath.

    ⚠️ The second dead end, so nobody tries it: transplanting a clean patch of plate from
    elsewhere on the same door. There isn't one. Measured across every candidate band down
    the leaf, all of them are 20-65 luma darker than the sign area, because the sign plate
    is the BRIGHTEST surface on this door — and scoring bands by "how little ink-like detail
    they contain" happily selected the barred window, whose darkness is one big shape rather
    than thin strokes. Both failures are visible in the git history of this file.
    """
    pad = 26
    region_box = (box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad)
    w = region_box[2] - region_box[0]
    h = region_box[3] - region_box[1]

    region = im.crop(region_box)

    # 1. MARK THE INK. The median radius must exceed the stroke width or the filter is
    #    averaging letters with letters — measured on this source, the ink-vs-plate luma
    #    gap rises from p97=50 at radius 9 to p97=70 at radius 31. Grain sits at p50≈0
    #    and ink above p80≈23, so 18 separates them cleanly.
    plate = region.filter(ImageFilter.MedianFilter(size=31))
    mask = Image.new("L", (w, h), 0)
    rp, pp, mp = region.load(), plate.load(), mask.load()
    for y in range(h):
        for x in range(w):
            r, g, b = rp[x, y]
            pr, pg, pb = pp[x, y]
            # Rec. 601 luma, same weighting cutout_alpha.py uses.
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            plum = 0.299 * pr + 0.587 * pg + 0.114 * pb
            if lum < plum - 11.0:
                mp[x, y] = 255

    # ⚠️ Dilate by ONE pixel, not three. Letters sit ~6-10 px apart, so a 7-wide MaxFilter
    # closes the gaps between them and merges the whole sign into one blob: measured, it
    # takes 23% ink coverage to 91%, and the fill then reads as a smooth rectangle pasted
    # over corroded steel. At size 3 the mask still follows the glyphs.
    mask = mask.filter(ImageFilter.MaxFilter(size=3)).filter(
        ImageFilter.GaussianBlur(radius=1.2))

    # 2. DIFFUSE. Each round pulls surrounding plate one blur-radius further inward; 30
    #    rounds is comfortably more than the half-width of the widest stroke, so nothing
    #    of the original survives in the middle. This is what finally removed the Cyrillic
    #    outright — every threshold-and-replace variant left a readable grey ghost.
    #
    # ⚠️ No synthetic re-grain. Borrowing high-frequency detail from elsewhere on the door
    # was tried and produced visible speckle: measured, every candidate donor band on this
    # door is 20-65 luma darker than the sign plate, because the plate is the brightest
    # surface on it. There is nothing here to transplant from.
    filled = region.copy()
    for _ in range(45):
        filled.paste(filled.filter(ImageFilter.GaussianBlur(radius=4.0)), (0, 0), mask)
    im.paste(filled, region_box, mask)


def draw_sign(im: "Image.Image", box: "tuple[int, int, int, int]", seed: int = 4711) -> None:
    """Stencil the English text through a worn mask."""
    rng = random.Random(seed)
    x0, y0, x1, y1 = box
    mask = Image.new("L", im.size, 0)
    md = ImageDraw.Draw(mask)

    # ⚠️ FIT each line to the box rather than trusting a point size. The replacement text
    # must occupy the footprint the original stencil did — a first pass at a fixed size
    # rendered narrower than the Cyrillic and, right-aligned, slid under the hinge.
    # Left-aligned and width-fitted, the sign lands exactly where the old one was.
    box_w = x1 - x0

    # One base size, derived from the LONGEST line filling the box. A real stencil is cut
    # at one size; fitting each line independently would blow "WING" up to the width of
    # "PSYCHIATRIC".
    longest = max((t for t, _ in LINES), key=len)
    base = 40
    for _ in range(120):
        w = md.textlength(longest, font=load_font(base))
        if abs(w - box_w) <= 3 or base <= 10 or base >= 200:
            break
        base += 1 if w < box_w else -1

    y = y0
    for text, scale in LINES:
        size = max(10, int(round(base * scale)))
        font = load_font(size)
        md.text((x0, y), text, font=font, fill=255)
        y += size + 10

    # Wear: punch holes in the glyphs and soften the edges, so it reads as sprayed
    # paint that has been weathering for decades rather than as a text layer.
    mp = mask.load()
    for py in range(y0 - 4, min(im.size[1], y1 + 8)):
        for px in range(x0 - 4, min(im.size[0], x1 + 8)):
            if mp[px, py] and rng.random() < 0.22:
                mp[px, py] = rng.randint(0, 110)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=0.6))

    # The ink is dark grey-brown, never black, and only ~78% opaque — the plate has to
    # show through it exactly as it does through the original stencil.
    ink = Image.new("RGB", im.size, (34, 30, 27))
    faded = mask.point(lambda v: int(v * 0.78))
    im.paste(ink, (0, 0), faded)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: restencil_door.py FILE [FILE ...]")
    for path in sys.argv[1:]:
        im = Image.open(path)
        before = im.size
        leaf = crop_to_leaf(im)
        erase_stencil(leaf, TEXT_BOX)
        draw_sign(leaf, TEXT_BOX)
        leaf.save(path)
        print("OK   %-26s %sx%s -> %sx%s  aspect 1:%.3f"
              % (path.split("/")[-1], before[0], before[1],
                 leaf.size[0], leaf.size[1], leaf.size[1] / leaf.size[0]))


if __name__ == "__main__":
    main()
