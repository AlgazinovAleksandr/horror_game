#!/usr/bin/env python3
"""Draw the Lab observation-room whiteboard.

This is the LEVEL 4 HINT (see CLAUDE.md). A researcher has sketched the shape of the
Backrooms trial: three gated steps, and a final node that is deliberately NOT a door
but a hatched wall with an arrow driven straight through it. Nothing on the board
says "walk into the wall" — the diagram has to be read.

Drawn procedurally rather than generated, because the asset lives or dies on two
short strings staying legible and on the arrow unambiguously piercing the hatching —
exactly the things image models get wrong.

Reproducible: seeded. Run:
    source .venv/bin/activate && python3 tools/make_lab_whiteboard.py
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parents[1] / "game/assets/textures/level_1_lab/lab_whiteboard.png"

W, H = 1024, 640
BOARD = (228, 230, 224)          # grubby white
INK = (24, 24, 26)               # black marker
RED = (150, 28, 24)              # red marker
GHOST = (198, 202, 195)          # half-erased previous writing

random.seed(447)  # subject 47, trial 4


def jitter(n=1.6):
    return random.uniform(-n, n)


def hand_line(d, p0, p1, colour, width=4, wobble=1.7, segments=14):
    """A straight line drawn by a human hand: broken into wobbling segments."""
    x0, y0 = p0
    x1, y1 = p1
    pts = []
    for i in range(segments + 1):
        t = i / segments
        # wobble tapers off at the endpoints, where a hand is steadiest
        damp = math.sin(t * math.pi)
        pts.append((x0 + (x1 - x0) * t + jitter(wobble) * damp,
                    y0 + (y1 - y0) * t + jitter(wobble) * damp))
    d.line(pts, fill=colour, width=width, joint="curve")


def hand_rect(d, box, colour, width=4):
    x0, y0, x1, y1 = box
    hand_line(d, (x0, y0), (x1, y0), colour, width)
    hand_line(d, (x1, y0), (x1, y1), colour, width)
    hand_line(d, (x1, y1), (x0, y1), colour, width)
    hand_line(d, (x0, y1), (x0, y0), colour, width)


def arrow(d, p0, p1, colour, width=4, head=15):
    hand_line(d, p0, p1, colour, width)
    ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    for spread in (2.6, -2.6):
        d.line([p1, (p1[0] + head * math.cos(ang + spread),
                     p1[1] + head * math.sin(ang + spread))],
               fill=colour, width=width)


def load_font(size, bold=False):
    for name in ("Bradley Hand Bold.ttf", "Noteworthy.ttc", "MarkerFelt.ttc",
                 "Chalkduster.ttf", "Helvetica.ttc"):
        try:
            return ImageFont.truetype(f"/System/Library/Fonts/Supplemental/{name}", size)
        except OSError:
            continue
    try:
        return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size)
    except OSError:
        return ImageFont.load_default()


def main():
    img = Image.new("RGB", (W, H), BOARD)
    d = ImageDraw.Draw(img)

    # --- surface grime: smears, streaks, ghosts of things wiped away -----------
    for _ in range(40):
        x, y = random.randint(0, W), random.randint(0, H)
        w, h = random.randint(60, 260), random.randint(18, 70)
        shade = random.randint(-8, 4)
        d.ellipse([x, y, x + w, y + h],
                  fill=tuple(max(0, min(255, c + shade)) for c in BOARD))
    for _ in range(14):  # squeegee streaks
        y = random.randint(0, H)
        d.line([(0, y + jitter(6)), (W, y + jitter(6))], fill=GHOST, width=random.randint(2, 9))

    # ghost of an older, erased diagram — the board has seen other trials
    gf = load_font(46)
    d.text((430, 96), "TRIAL 3", font=gf, fill=GHOST)
    hand_rect(d, (120, 150, 250, 216), GHOST, 5)

    # --- header ---------------------------------------------------------------
    d.text((60, 42), "TRIAL 4", font=load_font(72), fill=INK)
    hand_line(d, (62, 128), (330, 128), INK, 5)

    # --- the three gated steps ------------------------------------------------
    # Boxes are the rounds you survive; the down-arrows under each link are the
    # three DOWN turns the maze actually asks for.
    y_mid = 330
    boxes = [(90, y_mid - 55, 230, y_mid + 55),
             (300, y_mid - 55, 440, y_mid + 55),
             (510, y_mid - 55, 650, y_mid + 55)]
    for b in boxes:
        hand_rect(d, b, INK, 5)

    small = load_font(40)
    for i, b in enumerate(boxes):
        cx = (b[0] + b[2]) / 2
        d.text((cx - 12, y_mid - 26), str(i + 1), font=small, fill=INK)

    # connecting arrows + the little DOWN ticks beneath each
    for a, b in zip(boxes, boxes[1:]):
        arrow(d, (a[2] + 8, y_mid), (b[0] - 10, y_mid), INK, 5)
    # One DOWN tick per numbered step — three of them, matching the three turns
    # the maze actually asks for.
    for b in boxes:
        cx = (b[0] + b[2]) / 2
        arrow(d, (cx, b[3] + 14), (cx, b[3] + 74), INK, 4, head=12)

    # --- the terminal node: a hatched WALL, not a door ------------------------
    wx0, wy0, wx1, wy1 = 730, y_mid - 110, 800, y_mid + 110
    hand_rect(d, (wx0, wy0, wx1, wy1), INK, 5)
    step = 15
    for k in range(-14, 30):          # diagonal cross-hatching = solid wall
        x_top = wx0 + k * step
        d.line([(x_top, wy0), (x_top + (wy1 - wy0), wy1)], fill=INK, width=3)
    # clip the hatching back inside the wall outline
    d.rectangle([0, 0, wx0, H], fill=BOARD)
    d.rectangle([wx1, 0, W, H], fill=BOARD)

    # redraw everything the clipping rectangles just erased
    d.text((60, 42), "TRIAL 4", font=load_font(72), fill=INK)
    hand_line(d, (62, 128), (330, 128), INK, 5)
    d.text((430, 96), "TRIAL 3", font=gf, fill=GHOST)
    hand_rect(d, (120, 150, 250, 216), GHOST, 5)
    for b in boxes:
        hand_rect(d, b, INK, 5)
    for i, b in enumerate(boxes):
        cx = (b[0] + b[2]) / 2
        d.text((cx - 12, y_mid - 26), str(i + 1), font=small, fill=INK)
    for a, b in zip(boxes, boxes[1:]):
        arrow(d, (a[2] + 8, y_mid), (b[0] - 10, y_mid), INK, 5)
    # One DOWN tick per numbered step — three of them, matching the three turns
    # the maze actually asks for.
    for b in boxes:
        cx = (b[0] + b[2]) / 2
        arrow(d, (cx, b[3] + 14), (cx, b[3] + 74), INK, 4, head=12)
    hand_rect(d, (wx0, wy0, wx1, wy1), INK, 5)

    # --- the red arrow THROUGH the wall — the whole point of the board --------
    arrow(d, (boxes[2][2] + 8, y_mid), (wx1 + 92, y_mid), RED, 7, head=22)
    # a second red stroke emerging past the wall, to sell "through, not into"
    hand_line(d, (wx1 + 40, y_mid - 26), (wx1 + 40, y_mid + 26), RED, 3, wobble=1.0)

    # red ring scrawled round the wall
    for off in (0, 3):
        d.ellipse([wx0 - 34 + off, wy0 - 30 + off, wx1 + 34 - off, wy1 + 30 - off],
                  outline=RED, width=4)

    # --- the margin note, mostly wiped away -----------------------------------
    # Half-wiped, not erased: it must still be READABLE at a glance, just clearly
    # something someone tried to remove. Over-erasing turns the hint into noise.
    tmp = Image.new("RGB", (W, H), BOARD)
    ImageDraw.Draw(tmp).text((690, 486), "NO DOOR", font=load_font(58), fill=INK)
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.rectangle([675, 470, 1010, 560], fill=225)
    for _ in range(9):         # a few eraser swipes, thinning but not killing it
        x, y = random.randint(675, 980), random.randint(468, 556)
        md.ellipse([x, y, x + random.randint(34, 74), y + random.randint(14, 30)],
                   fill=random.randint(40, 95))
    img.paste(tmp, (0, 0), mask.filter(ImageFilter.GaussianBlur(2)))

    # --- final pass: marker bleed + dim clinical grade ------------------------
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    px = img.load()
    for y in range(H):          # vignette + faint green-grey institutional cast
        for x in range(0, W, 1):
            r, g, b = px[x, y]
            dx, dy = (x - W / 2) / (W / 2), (y - H / 2) / (H / 2)
            v = 1.0 - 0.34 * (dx * dx + dy * dy)
            px[x, y] = (int(r * v * 0.93), int(g * v * 0.95), int(b * v * 0.88))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, "PNG")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
